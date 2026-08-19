#!/usr/bin/env bash
# Model circuit breaker for the {{PROJECT_NAME}} autonomous loop — CLOSED/OPEN/
# HALF-OPEN state machine that degrades to cheaper models on rate limits and
# self-heals. Sourced by the loop driver (`loop.sh`); never executed directly.
#
# Twin: skills/setup/templates/loop/breaker.ps1 (PowerShell 7+) — behaviorally
# identical — same states, thresholds, transitions, and schema; any divergence is a
# bug. Function-name mapping (bash -> PowerShell):
#   breaker_load          -> Breaker-Load
#   breaker_should_skip    -> Breaker-ShouldSkip
#   breaker_record         -> Breaker-Record
#   breaker_current_model  -> Breaker-CurrentModel
#
# Cooldown threshold: 600s (OPEN -> HALF-OPEN eligible after 600s elapsed).
# Recovery threshold: HALF-OPEN closes at exactly 2 consecutive successes.
#
# State schema (flat JSON, one key per line — never nested, never minified/reflowed;
# both twins hand-write this exact layout so the file stays a byte-for-byte parity
# contract, not merely a JSON-equivalence one):
#   {
#   "state": "CLOSED"|"OPEN"|"HALF-OPEN",
#   "chain": "<comma-separated model chain, first = preferred>",
#   "fallbackIndex": <int, 0-based index of currentModel within chain — at chain
#     end the index stays put (pointing at the last entry) while currentModel
#     empties (omit-the-pin), so the two fields diverge by design>,
#   "currentModel": "<model id, or \"\" = omit the model flag/pin>",
#   "cooldownSeconds": 600,
#   "openedAt": <epoch seconds when OPEN was (re)entered, or 0>,
#   "halfOpenSuccesses": <int, consecutive successes while HALF-OPEN>,
#   "totalFallbacks": <int, lifetime>,
#   "totalRecoveries": <int, lifetime>
#   }
# NOTE: there is no `consecutiveFailures` key — it was a dead key in the original
# design note and is intentionally dropped from this schema.
#
# `chain` is normally seeded by the driver from the chain configured at install
# time (the LOOP_MODEL_CHAIN placeholder; see models.map.md's "Loop fallback
# chain" row) — this file never reads that token itself; the chain always
# arrives as a plain argument.
#
# Zero runtime deps: no jq/python/other JSON library. Parsing relies only on bash
# builtins plus grep (line presence) — never `eval`, never `source`s the state file
# — because the flat, one-key-per-line layout above is simple enough that a real
# JSON parser buys nothing but a new dependency. This also means the state file is
# read as inert data: its bytes are never treated as code, so a corrupted or
# adversarially-edited file can only fail validation, not execute anything.
#
# Testability: all timestamps are passed in as `<now-epoch>` parameters — no
# wall-clock reads inside any transition logic. Wall-clock anomaly guard: the
# remaining-cooldown value is CLAMPED to [0, cooldownSeconds] so a system clock that
# jumps backward or forward can never produce a negative or absurdly long skip.
#
# Sourcing this file has zero side effects: it only defines functions.

# --- internal helpers (leading underscore; not part of the pinned API) -----------

# _breaker_get <file> <key> -> prints the raw value for a flat-JSON key, or ""
# if the key line is absent. Strips the surrounding quotes/comma for string values;
# numeric values pass through unquoted.
_breaker_get() {
  local file="$1" key="$2" line value
  line="$(grep -m1 "\"${key}\":" "$file" 2>/dev/null)" || true
  [[ -z "$line" ]] && { printf '%s' ""; return 0; }
  value="${line#*:}"
  # trim leading/trailing whitespace (guaranteed progress each iteration — handles
  # space/tab/CR/LF/VT/FF on either end; ordering matches the PS twin's .Trim())
  while [[ -n "$value" && "$value" == [[:space:]]* ]]; do value="${value:1}"; done
  while [[ -n "$value" && "$value" == *[[:space:]] ]]; do value="${value%?}"; done
  value="${value%,}"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

# _breaker_valid <file> -> return 0 iff every required key is present and every
# typed field parses (state is one of the three enum values; numeric fields are
# numeric). This is the "parseable" gate breaker_load uses to decide reset-vs-keep.
_breaker_valid() {
  local file="$1" key
  for key in state chain fallbackIndex currentModel cooldownSeconds openedAt \
             halfOpenSuccesses totalFallbacks totalRecoveries; do
    grep -q "\"${key}\":" "$file" 2>/dev/null || return 1
  done
  local state idx cooldown opened half fb rec
  state="$(_breaker_get "$file" state)"
  case "$state" in
    CLOSED|OPEN|HALF-OPEN) ;;
    *) return 1 ;;
  esac
  idx="$(_breaker_get "$file" fallbackIndex)"; [[ "$idx" =~ ^[0-9]+$ ]] || return 1
  cooldown="$(_breaker_get "$file" cooldownSeconds)"; [[ "$cooldown" =~ ^[0-9]+$ ]] || return 1
  opened="$(_breaker_get "$file" openedAt)"; [[ "$opened" =~ ^-?[0-9]+$ ]] || return 1
  half="$(_breaker_get "$file" halfOpenSuccesses)"; [[ "$half" =~ ^[0-9]+$ ]] || return 1
  fb="$(_breaker_get "$file" totalFallbacks)"; [[ "$fb" =~ ^[0-9]+$ ]] || return 1
  rec="$(_breaker_get "$file" totalRecoveries)"; [[ "$rec" =~ ^[0-9]+$ ]] || return 1
  return 0
}

# _breaker_write <file> <state> <chain> <idx> <model> <cooldown> <openedAt> <half>
#                <totalFallbacks> <totalRecoveries>
# The ONE place that serializes the schema — every transition below funnels through
# this so the on-disk layout never drifts.
_breaker_write() {
  local file="$1" state="$2" chain="$3" idx="$4" model="$5" cooldown="$6" \
        opened="$7" half="$8" fb="$9" rec="${10}"
  {
    printf '{\n'
    printf '"state": "%s",\n' "$state"
    printf '"chain": "%s",\n' "$chain"
    printf '"fallbackIndex": %s,\n' "$idx"
    printf '"currentModel": "%s",\n' "$model"
    printf '"cooldownSeconds": %s,\n' "$cooldown"
    printf '"openedAt": %s,\n' "$opened"
    printf '"halfOpenSuccesses": %s,\n' "$half"
    printf '"totalFallbacks": %s,\n' "$fb"
    printf '"totalRecoveries": %s\n' "$rec"
    printf '}\n'
  } > "$file"
}

# _breaker_seed <file> <chain> -> writes a fresh CLOSED state seeded from <chain>.
# currentModel = first chain entry, or "" when the chain is empty.
_breaker_seed() {
  local file="$1" chain="$2" first=""
  [[ -n "$chain" ]] && first="${chain%%,*}"
  _breaker_write "$file" CLOSED "$chain" 0 "$first" 600 0 0 0 0
}

# _breaker_read_all <file> -> populates the _BRK_* scratch variables used by
# breaker_should_skip/breaker_record. Not namerefs (bash 3.2 on stock macOS has no
# `local -n`), so these are deliberately module-scoped globals under the _BRK_
# prefix — internal to this file, never part of the pinned API.
_breaker_read_all() {
  local file="$1"
  _BRK_STATE="$(_breaker_get "$file" state)"
  _BRK_CHAIN="$(_breaker_get "$file" chain)"
  _BRK_INDEX="$(_breaker_get "$file" fallbackIndex)"
  _BRK_MODEL="$(_breaker_get "$file" currentModel)"
  _BRK_COOLDOWN="$(_breaker_get "$file" cooldownSeconds)"
  _BRK_OPENED="$(_breaker_get "$file" openedAt)"
  _BRK_HALF="$(_breaker_get "$file" halfOpenSuccesses)"
  _BRK_FALLBACKS="$(_breaker_get "$file" totalFallbacks)"
  _BRK_RECOVERIES="$(_breaker_get "$file" totalRecoveries)"
}

# _breaker_advance_chain -> mutates _BRK_INDEX/_BRK_MODEL per the pinned rule:
# index++ (and currentModel = that entry) if a next entry exists, ELSE
# currentModel="" (chain-end reconciles with models.map's omit-the-pin rule).
# A further advance while already at chain-end computes the same false condition
# again, so currentModel simply stays "" — no special "exhausted" sentinel needed.
_breaker_advance_chain() {
  local -a entries=()
  if [[ -n "$_BRK_CHAIN" ]]; then
    IFS=',' read -r -a entries <<< "$_BRK_CHAIN"
  fi
  local n=${#entries[@]}
  if (( _BRK_INDEX + 1 < n )); then
    _BRK_INDEX=$(( _BRK_INDEX + 1 ))
    _BRK_MODEL="${entries[$_BRK_INDEX]}"
  else
    _BRK_MODEL=""
  fi
}

# --- pinned API --------------------------------------------------------------

# breaker_load <state-file> <chain>
# Missing file -> create fresh CLOSED seeded from <chain>, silently.
# Unparseable file -> rewrite fresh CLOSED (same seeding) + one stderr warning.
# Parseable file -> left untouched (the chain argument is ignored in this case;
# only a fresh file is ever seeded from it).
breaker_load() {
  local state_file="$1" chain="$2"
  if [[ ! -f "$state_file" ]]; then
    _breaker_seed "$state_file" "$chain"
    return 0
  fi
  if _breaker_valid "$state_file"; then
    return 0
  fi
  echo "breaker: $state_file is unparseable — resetting to fresh CLOSED state" >&2
  _breaker_seed "$state_file" "$chain"
}

# breaker_current_model <state-file> -> echoes currentModel (may be empty).
breaker_current_model() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo ""; return 0; }
  _breaker_get "$state_file" currentModel
  echo
}

# breaker_should_skip <state-file> <now-epoch>
# OPEN & cooldown not elapsed -> echo remaining seconds (clamped to
#   [0, cooldownSeconds]).
# OPEN & cooldown elapsed -> transition to HALF-OPEN (halfOpenSuccesses=0),
#   persist, echo 0.
# Any other state -> echo 0, no state change.
breaker_should_skip() {
  local state_file="$1" now="$2"
  _breaker_read_all "$state_file"

  if [[ "$_BRK_STATE" != "OPEN" ]]; then
    echo 0
    return 0
  fi

  local elapsed remaining
  elapsed=$(( now - _BRK_OPENED ))
  remaining=$(( _BRK_COOLDOWN - elapsed ))
  # Wall-clock anomaly guard: clamp to [0, cooldownSeconds].
  (( remaining < 0 )) && remaining=0
  (( remaining > _BRK_COOLDOWN )) && remaining=$_BRK_COOLDOWN

  if (( remaining > 0 )); then
    echo "$remaining"
    return 0
  fi

  _BRK_STATE="HALF-OPEN"
  _BRK_HALF=0
  _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
    "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" "$_BRK_FALLBACKS" \
    "$_BRK_RECOVERIES"
  echo 0
}

# breaker_record <state-file> <rate-limited:0|1> <now-epoch>
# Transitions exactly per goal.md's exhaustive table:
#   CLOSED   + 0 -> no-op.
#   CLOSED   + 1 -> OPEN; advance chain; openedAt=now; totalFallbacks++.
#   HALF-OPEN+ 0 -> halfOpenSuccesses++; at exactly 2 -> CLOSED (reset
#                   halfOpenSuccesses/openedAt; totalRecoveries++).
#   HALF-OPEN+ 1 -> OPEN; advance chain; openedAt=now (reset).
#   OPEN     +any -> defensive path (normally unreachable under mechanism B):
#                   log a warning, then treat exactly as the HALF-OPEN input above.
breaker_record() {
  local state_file="$1" rate_limited="$2" now="$3"
  _breaker_read_all "$state_file"

  if [[ "$_BRK_STATE" == "OPEN" ]]; then
    echo "breaker: breaker_record called while OPEN (defensive path — mechanism B should make this unreachable); treating as HALF-OPEN input" >&2
    _BRK_STATE="HALF-OPEN"
  fi

  case "$_BRK_STATE" in
    CLOSED)
      if [[ "$rate_limited" == "1" ]]; then
        _breaker_advance_chain
        _BRK_STATE="OPEN"
        _BRK_OPENED="$now"
        _BRK_FALLBACKS=$(( _BRK_FALLBACKS + 1 ))
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES"
      fi
      # CLOSED + success -> no-op: nothing written.
      ;;
    HALF-OPEN)
      if [[ "$rate_limited" == "1" ]]; then
        _breaker_advance_chain
        _BRK_STATE="OPEN"
        _BRK_OPENED="$now"
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES"
      else
        _BRK_HALF=$(( _BRK_HALF + 1 ))
        if (( _BRK_HALF == 2 )); then
          _BRK_STATE="CLOSED"
          _BRK_HALF=0
          _BRK_OPENED=0
          _BRK_RECOVERIES=$(( _BRK_RECOVERIES + 1 ))
        fi
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES"
      fi
      ;;
  esac
}
