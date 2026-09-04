#!/usr/bin/env bash
# emit.sh — deterministic emitter for the AI Orchestration Kit.
# Twin: emit.ps1 (PowerShell 7+, behaviorally identical — same flags, same
# stdout/stderr, same exit codes, same tree + manifest bytes; any divergence is
# a bug). Replaces the LLM compile of /setup Steps 4–6: resolve IF / BOOTSTRAP /
# tokens, translate per harness, write seeds/pointers/manifest, prune, verify.
#
# CLI CONTRACT (frozen — SKILL.md Steps 4–6 describe the flow):
#
#   emit.sh [--answers F] [--upgrade] [--dry-run] [--force] [--check-answers]
#           [--root DIR] [--kit DIR]
#
#   --root  repo root (default: cwd). --kit  setup skill dir (default: dirname $0/..).
#           Templates are read from <kit>/templates.
#   --answers F   answers JSON (schema 1). Without --answers, answers are read from
#                 an existing manifest (upgrade). A pre-v0.27.0 manifest without
#                 answers and no --answers ⇒ exit 3.
#   --upgrade     explicit upgrade path (optional when a manifest exists).
#   --dry-run     print one action line per planned write|skip|prune|keep|seed|warn|blocked
#                 path; touch nothing. Any blocked line ⇒ exit 4, else 0.
#   --force       overwrite user-modified kit files.
#   --check-answers  print <id>\t<template path relative to <kit>/templates> for every
#                 class-a BOOTSTRAP id missing from answers.bootstrap (empty string
#                 counts as answered; kit-* never listed). Exit 3 if any line, else 0.
#
#   Exit codes: 0 ok · 2 usage / jq missing / answers file unreadable · 3 answers
#   invalid or unanswered ids under --check-answers · 4 upgrade blocked by
#   user-modified files (listed on stderr; --force overrides) · 5 verify failed ·
#   6 template syntax error. Errors: one stderr line each, prefixed `emit: `.
#   --help prints usage to stderr and exits 2.
#
#   Success stdout is exactly one line:
#     emit: written N · unchanged M · pruned P · seeds-kept S · warnings W · manifest orchestration-kit.manifest.json · kit <VERSION>
#   N/M count emit-set files only (written = bytes differ or file absent; unchanged
#   = identical). The manifest is always rewritten and never counted in N.
#
#   Determinism: no timestamps except installedAt (kept from an existing manifest,
#   else EMIT_DATE, else today YYYY-MM-DD). Sorted walks (LC_ALL=C). Manifest
#   top-level keys in fixed order; nested objects ordinal-sorted (jq -S).
#
# Requires bash 4+ and jq. Zero other runtime deps (pwsh optional for verify).
set -euo pipefail
export LC_ALL=C

LB='{'
RB='}'

usage() {
  cat <<'EOF' >&2
usage: emit.sh [--answers F] [--upgrade] [--dry-run] [--force] [--check-answers]
               [--root DIR] [--kit DIR]
  --root DIR   repo root (default: cwd)
  --kit DIR    setup skill dir (default: dirname $0/..)
  --answers F  answers JSON (schema 1). omitted ⇒ read from manifest
  --upgrade    upgrade using answers embedded in the manifest
  --dry-run    print planned actions; touch nothing
  --force      overwrite user-modified kit files
  --check-answers  list unanswered class-a bootstrap ids; exit 3 if any
exit: 0 ok · 2 usage/jq/unreadable · 3 answers invalid · 4 blocked · 5 verify · 6 template syntax
EOF
}

die() { # <code> <message>
  printf 'emit: %s\n' "$2" >&2
  exit "$1"
}

need_val() { [ $# -ge 2 ] || die 2 "flag '$1' needs a value"; }

ANSWERS_FILE=""
DO_UPGRADE=0
DRY_RUN=0
FORCE=0
CHECK_ANSWERS=0
ROOT=""
KIT=""

[ $# -eq 0 ] && { usage; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help|help) usage; exit 2 ;;
    --answers)        need_val "$@"; ANSWERS_FILE="$2"; shift 2 ;;
    --root)           need_val "$@"; ROOT="$2"; shift 2 ;;
    --kit)            need_val "$@"; KIT="$2"; shift 2 ;;
    --upgrade)        DO_UPGRADE=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --force)          FORCE=1; shift ;;
    --check-answers)  CHECK_ANSWERS=1; shift ;;
    *) die 2 "unknown flag '$1'" ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  kit_disp="${KIT:-<kit>}"
  die 2 "jq not found — install jq or run: pwsh ${kit_disp}/bin/emit.ps1 …"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$KIT" ]; then
  KIT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  [ -d "$KIT" ] || die 2 "kit directory not found: $KIT"
  KIT="$(cd "$KIT" && pwd)"
fi
if [ -z "$ROOT" ]; then
  ROOT="$PWD"
else
  if [ ! -d "$ROOT" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      die 2 "root directory not found: $ROOT"
    fi
    mkdir -p "$ROOT"
  fi
  ROOT="$(cd "$ROOT" && pwd)"
fi

TPL="$KIT/templates"
[ -d "$TPL" ] || die 2 "templates directory not found: $TPL"
VERSION="$(tr -d '[:space:]' < "$KIT/VERSION")"
[ -n "$VERSION" ] || die 2 "kit VERSION file is empty"

MANIFEST="$ROOT/orchestration-kit.manifest.json"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
index_of() { # hay needle → index or -1
  local hay="$1" needle="$2" rest
  rest="${hay%%"$needle"*}"
  if [ "$rest" = "$hay" ]; then
    printf '%s' '-1'
  else
    printf '%s' "${#rest}"
  fi
}

read_file_raw() { # path → stdout (LF, no CR, trailing bytes preserved)
  local data
  data="$(cat -- "$1"; printf x)"
  data="${data%x}"
  data="${data//$'\r'/}"
  printf '%s' "$data"
}

sha256_str() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

sha256_file() {
  sha256sum -- "$1" | awk '{print $1}'
}

rel_tpl() { # abs path under TPL → path relative to templates/
  local p="$1"
  printf '%s' "${p#"$TPL"/}"
}

ensure_trailing_nl() { # stdin/arg via nameref-like printf
  local s="$1"
  if [ -n "$s" ] && [ "${s: -1}" != $'\n' ]; then
    printf '%s\n' "$s"
  else
    printf '%s' "$s"
  fi
}

# ---------------------------------------------------------------------------
# IF / ENDIF
# ---------------------------------------------------------------------------
declare -A KNOWN_FLAG=()
for _f in research loop greenfield lint typecheck models_pinned \
          is_claude is_cursor is_copilot is_codex \
          want_claude want_cursor want_copilot want_codex; do
  KNOWN_FLAG["$_f"]=1
done

declare -A FLAGS=()
for _f in "${!KNOWN_FLAG[@]}"; do
  FLAGS["$_f"]=false
done

parse_if_line() { # line → 0 if marker; sets MK_KIND MK_SPEC
  local line="$1" s
  s="${line%"${line##*[![:space:]]}"}"
  s="${s#"${s%%[![:space:]]*}"}"
  if [ "${s:0:1}" = '>' ]; then
    s="${s:1}"
    s="${s#"${s%%[![:space:]]*}"}"
  fi
  MK_KIND=""
  MK_SPEC=""
  if [[ "$s" =~ ^\<!--\ IF\ (!?[a-z][a-z0-9_]*)\ --\>$ ]]; then
    MK_KIND=IF
    MK_SPEC="${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$s" =~ ^\<!--\ ENDIF\ (!?[a-z][a-z0-9_]*)\ --\>$ ]]; then
    MK_KIND=ENDIF
    MK_SPEC="${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

SYNTAX_ERRS=()
declare -A UNKNOWN_FLAGS=()

record_syntax() { SYNTAX_ERRS+=("$1"); }

scan_if_syntax() { # file rel
  local file="$1" rel="$2" content line n=0
  local -a st_spec=() st_line=()
  content="$(read_file_raw "$file")"
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if parse_if_line "$line"; then
      local name="${MK_SPEC#!}"
      if [ -z "${KNOWN_FLAG[$name]+x}" ]; then
        UNKNOWN_FLAGS["$name"]="$rel:$n"
      fi
      if [ "$MK_KIND" = IF ]; then
        st_spec+=("$MK_SPEC")
        st_line+=("$n")
      else
        if [ ${#st_spec[@]} -eq 0 ]; then
          record_syntax "$rel:$n: unmatched ENDIF '$MK_SPEC'"
        else
          local top="${st_spec[${#st_spec[@]}-1]}"
          if [ "$top" != "$MK_SPEC" ]; then
            record_syntax "$rel:$n: mismatched ENDIF '$MK_SPEC' (open IF '$top' at line ${st_line[${#st_line[@]}-1]})"
          fi
          unset 'st_spec[-1]'
          unset 'st_line[-1]'
        fi
      fi
    fi
  done < <(printf '%s' "$content")
  local i
  for i in "${!st_spec[@]}"; do
    record_syntax "$rel:${st_line[$i]}: unmatched IF '${st_spec[$i]}'"
  done
}

resolve_if() { # content rel → stdout
  local content="$1"
  local line n=0 keep=1
  local -a st_spec=() st_keep=()
  local -a out=()
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if parse_if_line "$line"; then
      local name="${MK_SPEC#!}"
      if [ "$MK_KIND" = IF ]; then
        local cond=0
        [ "${FLAGS[$name]:-false}" = true ] && cond=1
        if [ "${MK_SPEC:0:1}" = '!' ]; then
          cond=$((1 - cond))
        fi
        st_spec+=("$MK_SPEC")
        st_keep+=("$keep")
        if [ "$keep" -eq 1 ] && [ "$cond" -eq 1 ]; then
          keep=1
        else
          keep=0
        fi
      else
        keep="${st_keep[-1]}"
        unset 'st_spec[-1]'
        unset 'st_keep[-1]'
      fi
      continue
    fi
    if [ "$keep" -eq 1 ]; then
      out+=("$line")
    fi
  done < <(printf '%s' "$content")
  if [ ${#out[@]} -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${out[@]}"
}

# ---------------------------------------------------------------------------
# BOOTSTRAP
# ---------------------------------------------------------------------------
declare -A BOOTSTRAP_VAL=()   # id → value (only if key present)
declare -A BOOTSTRAP_HAS=()   # id → 1 if key present
declare -A BOOTSTRAP_ID_PATH=() # id → first rel path
MISSING_BOOTSTRAP=()

collapse_join() {
  local left="$1" right="$2"
  local trail=0 lead=0
  while [ -n "$left" ] && [ "${left: -1}" = $'\n' ]; do
    left="${left%$'\n'}"
    trail=$((trail + 1))
  done
  while [ -n "$right" ] && [ "${right:0:1}" = $'\n' ]; do
    right="${right:1}"
    lead=$((lead + 1))
  done
  if [ -z "$left" ]; then
    printf '%s' "$right"
    return
  fi
  if [ -z "$right" ]; then
    printf '%s\n' "$left"
    return
  fi
  if [ $((trail + lead)) -ge 2 ]; then
    printf '%s\n\n%s' "$left" "$right"
  else
    printf '%s\n%s' "$left" "$right"
  fi
}

# Find BOOTSTRAP comments in $1. For each, invoke callback-style via collecting
# arrays: BS_START BS_END BS_ID BS_LINE BS_WHOLE
find_bootstrap() {
  local text="$1"
  BS_START=() BS_END=() BS_ID=() BS_LINE=() BS_WHOLE=()
  local pos=0 needle='<!-- BOOTSTRAP['
  while true; do
    local hay="${text:pos}"
    local idx
    idx="$(index_of "$hay" "$needle")"
    if [ "$idx" -lt 0 ]; then
      break
    fi
    local abs=$((pos + idx))
    local after="${text:abs}"
    if [[ ! "$after" =~ ^\<!--\ BOOTSTRAP\[([a-z0-9]+(-[a-z0-9]+)*)\]: ]]; then
      pos=$((abs + 16))
      continue
    fi
    local id="${BASH_REMATCH[1]}"
    local open_len=${#BASH_REMATCH[0]}
    local rest="${text:abs+open_len}"
    local close
    close="$(index_of "$rest" '-->')"
    if [ "$close" -lt 0 ]; then
      local pre="${text:0:abs}"
      local lineno
      lineno="$(printf '%s' "$pre" | awk 'END{print NR}')"
      record_syntax "${2:-?}:$lineno: unclosed BOOTSTRAP[$id]"
      break
    fi
    local comment_end=$((abs + open_len + close + 3))
    local pre="${text:0:abs}"
    local line_start=0
    if [ -n "$pre" ]; then
      local stripped="${pre##*$'\n'}"
      line_start=$((${#pre} - ${#stripped}))
    fi
    local line_prefix="${text:line_start:abs-line_start}"
    local region_start=$abs
    if [[ "$line_prefix" =~ ^[[:space:]]*$ ]] || [[ "$line_prefix" =~ ^[[:space:]]*(\>[[:space:]]*)+$ ]] || [[ "$line_prefix" =~ ^[[:space:]]*([*+-]|[0-9]+\.)[[:space:]]*$ ]]; then
      region_start=$line_start
    fi
    local region_end=$comment_end
    local whole=0
    local tail="${text:comment_end}"
    if [ "$region_start" -eq 0 ] || [ "${text:region_start-1:1}" = $'\n' ]; then
      if [ -z "$tail" ]; then
        whole=1
      elif [[ "$tail" =~ ^[[:space:]]*$'\n' ]] || [[ "$tail" =~ ^[[:space:]]*$ ]]; then
        local nl
        nl="$(index_of "$tail" $'\n')"
        if [ "$nl" -ge 0 ]; then
          region_end=$((comment_end + nl + 1))
        else
          region_end=${#text}
        fi
        whole=1
      fi
    fi
    local lineno
    lineno="$(printf '%s' "${text:0:abs}" | awk 'END{print NR}')"
    [ -z "$lineno" ] && lineno=1
    BS_START+=("$region_start")
    BS_END+=("$region_end")
    BS_ID+=("$id")
    BS_LINE+=("$lineno")
    BS_WHOLE+=("$whole")
    pos=$comment_end
  done
}

scan_bootstrap_ids_in() { # file rel
  local file="$1" rel="$2" content
  content="$(read_file_raw "$file")"
  find_bootstrap "$content" "$rel"
  local i id
  for i in "${!BS_ID[@]}"; do
    id="${BS_ID[$i]}"
    case "$id" in
      kit-*) continue ;;
    esac
    if [ -z "${BOOTSTRAP_ID_PATH[$id]+x}" ]; then
      BOOTSTRAP_ID_PATH["$id"]="$rel"
    fi
  done
}

bootstrap_apply() { # content rel mode(strip|apply) → stdout
  local text="$1" rel="$2" mode="$3"
  find_bootstrap "$text" "$rel"
  if [ ${#BS_ID[@]} -eq 0 ]; then
    printf '%s' "$text"
    return
  fi
  local i
  for (( i=${#BS_ID[@]}-1; i>=0; i-- )); do
    local id="${BS_ID[$i]}" start="${BS_START[$i]}" end="${BS_END[$i]}" whole="${BS_WHOLE[$i]}"
    local left="${text:0:start}" right="${text:end}"
    local repl=""
    local do_delete=1
    if [ "$mode" = apply ]; then
      case "$id" in
        kit-*) do_delete=1 ;;
        *)
          if [ -n "${BOOTSTRAP_HAS[$id]+x}" ]; then
            repl="${BOOTSTRAP_VAL[$id]}"
            if [ -n "$repl" ]; then
              do_delete=0
            else
              do_delete=1
            fi
          else
            do_delete=1
          fi
          ;;
      esac
    fi
    if [ "$do_delete" -eq 1 ]; then
      if [ "$whole" -eq 1 ]; then
        text="$(collapse_join "$left" "$right")"
      else
        text="${left}${right}"
      fi
    else
      if [ "$whole" -eq 1 ] && [ "$end" -gt 0 ] && [ "${text:end-1:1}" = $'\n' ]; then
        text="${left}${repl}"$'\n'"${right}"
      else
        text="${left}${repl}${right}"
      fi
    fi
  done
  printf '%s' "$text"
}

# ---------------------------------------------------------------------------
# tokens
# ---------------------------------------------------------------------------
declare -A TOKENS=()
PROBLEMS=()
RESOLVED=""

add_problem() { PROBLEMS+=("$1"); }

replace_tokens() { # content → stdout
  local text="$1" name needle changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    for name in "${!TOKENS[@]}"; do
      needle="${LB}${LB}${name}${RB}${RB}"
      if [[ "$text" == *"$needle"* ]]; then
        text="${text//"$needle"/${TOKENS[$name]}}"
        changed=1
      fi
    done
  done
  printf '%s' "$text"
}

scan_unresolved_tokens() { # content rel
  local text rel tmp tok
  text="$1"
  rel="$2"
  tmp="$text"
  while [[ "$tmp" =~ \{\{([A-Z_]+)\}\} ]]; do
    tok="${BASH_REMATCH[1]}"
    if [ -z "${TOKENS[$tok]+x}" ]; then
      add_problem "token '$tok' has no value in $rel"
    fi
    tmp="${tmp#*"${BASH_REMATCH[0]}"}"
  done
}

# ---------------------------------------------------------------------------
# frontmatter translation
# ---------------------------------------------------------------------------
split_fm() { # content → sets FM_INNER BODY_AFTER; return 1 if no fm
  local content="$1"
  if [ "${content:0:4}" != $'---\n' ]; then
    return 1
  fi
  local rest="${content:4}"
  local close
  close="$(index_of "$rest" $'\n---')"
  [ "$close" -ge 0 ] || return 1
  FM_INNER="${rest:0:close}"
  BODY_AFTER="${rest:close+4}" # starts at whatever follows \n---
  return 0
}

filter_fm_lines() { # inner role mode → stdout inner (no wrapping ---)
  local inner="$1" role="$2" mode="$3"
  local line out="" seen_user=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$mode" in
      cursor-agent)
        case "$line" in
          effort:*|tools:*) continue ;;
        esac
        out+="$line"$'\n'
        if [[ "$line" == model:* ]]; then
          case "$role" in
            evaluator|qa-evaluator|diagnostician) out+="readonly: true"$'\n' ;;
          esac
        fi
        ;;
      cursor-skill)
        case "$line" in
          model:*|effort:*) continue ;;
        esac
        out+="$line"$'\n'
        ;;
      copilot-agent)
        case "$line" in
          effort:*) continue ;;
          model:*)
            local mv="${line#model:}"
            mv="${mv#"${mv%%[![:space:]]*}"}"
            out+="model: [\"${mv}\"]"$'\n'
            continue
            ;;
          tools:*)
            if [ "$role" = terminal ]; then
              out+="tools: ['read', 'execute']"$'\n'
              continue
            fi
            out+="$line"$'\n'
            ;;
          user-invocable:*) seen_user=1; out+="$line"$'\n' ;;
          *) out+="$line"$'\n' ;;
        esac
        ;;
      copilot-feature)
        case "$line" in
          effort:*) continue ;;
          user-invocable:*) seen_user=1; out+="$line"$'\n' ;;
          *) out+="$line"$'\n' ;;
        esac
        ;;
      *) out+="$line"$'\n' ;;
    esac
  done < <(printf '%s' "$inner")
  if [ "$mode" = copilot-agent ] && [ "$seen_user" -eq 0 ]; then
    out+="user-invocable: false"$'\n'
  fi
  if [ "$mode" = copilot-feature ]; then
    out+="model: [\"${TOKENS[MODEL_FRONTIER]}\"]"$'\n'
    if [ "$seen_user" -eq 0 ]; then
      out+="user-invocable: true"$'\n'
    fi
    out+="agents: [implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician]"$'\n'
    out+="tools: ['agent']"$'\n'
  fi
  printf '%s' "$out"
}

wrap_fm() { # inner body → stdout
  local inner="$1" body="$2"
  # inner from command subst has trailing newlines stripped; restore the
  # newline that closes the last frontmatter line before the closing fence.
  printf -- '---\n%s\n---%s' "$inner" "$body"
}

translate_cursor_agent() {
  local role="$1" content="$2"
  split_fm "$content" || { printf '%s' "$content"; return; }
  wrap_fm "$(filter_fm_lines "$FM_INNER" "$role" cursor-agent)" "$BODY_AFTER"
}

translate_cursor_skill() {
  local content="$1"
  split_fm "$content" || { printf '%s' "$content"; return; }
  wrap_fm "$(filter_fm_lines "$FM_INNER" "" cursor-skill)" "$BODY_AFTER"
}

translate_copilot_agent() {
  local role="$1" content="$2"
  split_fm "$content" || { printf '%s' "$content"; return; }
  wrap_fm "$(filter_fm_lines "$FM_INNER" "$role" copilot-agent)" "$BODY_AFTER"
}

translate_copilot_feature() {
  local content="$1"
  split_fm "$content" || { printf '%s' "$content"; return; }
  wrap_fm "$(filter_fm_lines "$FM_INNER" feature copilot-feature)" "$BODY_AFTER"
}

strip_frontmatter() {
  local content="$1"
  split_fm "$content" || { printf '%s' "$content"; return; }
  local body="$BODY_AFTER"
  while [ "${body:0:1}" = $'\n' ]; do
    body="${body:1}"
  done
  printf '%s' "$body"
}

# ---------------------------------------------------------------------------
# kit-owned predicate, path helpers
# ---------------------------------------------------------------------------
ide_dir_for() {
  case "$1" in
    claude-code) printf '%s' '.claude' ;;
    cursor)      printf '%s' '.cursor' ;;
    copilot)     printf '%s' '.github' ;;
    codex)       printf '%s' '.codex' ;;
    *) die 3 "unknown harness '$1'" ;;
  esac
}

harness_suffix() {
  case "$1" in
    claude-code) printf '%s' 'claude' ;;
    cursor)      printf '%s' 'cursor' ;;
    copilot)     printf '%s' 'copilot' ;;
    codex)       printf '%s' 'codex' ;;
    *) die 3 "unknown harness '$1'" ;;
  esac
}

harness_prefix() {
  case "$1" in
    claude-code) printf '%s' 'CLAUDE' ;;
    cursor)      printf '%s' 'CURSOR' ;;
    copilot)     printf '%s' 'COPILOT' ;;
    codex)       printf '%s' 'CODEX' ;;
  esac
}

KIT_SKILLS=()
load_kit_skills() {
  local d
  KIT_SKILLS=()
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    KIT_SKILLS+=("$(basename "$d")")
  done < <(LC_ALL=C find "$TPL/skills" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
  local has_al=0 s
  for s in "${KIT_SKILLS[@]}"; do
    [ "$s" = auto-loop ] && has_al=1
  done
  [ "$has_al" -eq 0 ] && KIT_SKILLS+=(auto-loop)
}

is_seed_path() { [ "$1" = '_goals/backlog.md' ]; }

is_kit_owned() {
  local p="$1" dir skill
  case "$p" in
    .claude/agents/*|.cursor/agents/*|.github/agents/*|.codex/agents/*) return 0 ;;
    .cursor/rules/orchestration.mdc) return 0 ;;
    _loop/*|_kit/*) return 0 ;;
    ORCHESTRATION.md) return 0 ;;
    .claude/ORCHESTRATION.md|.cursor/ORCHESTRATION.md) return 0 ;;
    .claude/skills/setup-models.map.md|.cursor/skills/setup-models.map.md) return 0 ;;
  esac
  for dir in .claude .cursor .github .codex; do
    for skill in "${KIT_SKILLS[@]}"; do
      case "$p" in
        "$dir/skills/$skill"|"$dir/skills/$skill"/*) return 0 ;;
      esac
    done
  done
  return 1
}

# ---------------------------------------------------------------------------
# embedded pointer / config texts (not read from emitters at run time)
# ---------------------------------------------------------------------------
POINTER_MARKER='<!-- orchestration-kit:pointer -->'
CODEX_AGENTS_MARKER='# orchestration-kit:agents'

pointer_claude() {
  cat <<EOF
## Orchestration
Feature work runs through the orchestrator/worker/evaluator system — see
.claude/ORCHESTRATION.md. Start features with /feature.
${POINTER_MARKER}
EOF
}

pointer_copilot() {
  cat <<EOF
## Orchestration
Feature work runs through the orchestrator/worker/evaluator system — see ORCHESTRATION.md. Start features with the \`feature\` agent.
${POINTER_MARKER}
EOF
}

pointer_agents_md() {
  cat <<EOF
## Orchestration
Non-trivial features run through the orchestrator/worker/evaluator flow in
ORCHESTRATION.md: plan → evaluate the plan → implement per task (spawn \`implementer\` /
\`test-writer\`) → evaluate every task (spawn \`evaluator\`) → final audit → quality checks.
Fixes are always re-evaluated. After three fix cycles, spawn \`diagnostician\` for rung 4
diagnosis. Quality checks spawn \`terminal\` for the full-suite run so its raw output stays
out of the session. Role instructions: .codex/agents/*.md (six roles).
${POINTER_MARKER}
EOF
}

pointer_cursor_mdc() {
  cat <<'EOF'
---
alwaysApply: true
---
Feature work runs through the orchestrator/worker/evaluator system described in
.cursor/ORCHESTRATION.md. Non-trivial features start with the `feature` skill;
implementation goes to the implementer/test-writer subagents; all verification goes to
the evaluator subagents. Never mark orchestrated work complete without an evaluator PASS.
EOF
}

codex_config_tables() { # light-model-id
  local light="$1"
  cat <<EOF
${CODEX_AGENTS_MARKER}
[agents]
default_subagent_model = "${light}"
default_subagent_reasoning_effort = "medium"

[agents.evaluator]
description = "Skeptical goal/task/code evaluator. Spawn to verify any completed work; returns PASS/NEEDS FIXES/REJECT. Read .codex/agents/evaluator.md first."
config_file = "agents/evaluator.toml"

[agents.qa-evaluator]
description = "User-perspective behavioral QA evaluator for captured evidence. Read .codex/agents/qa-evaluator.md first."
config_file = "agents/qa-evaluator.toml"

[agents.implementer]
description = "Checklist-driven implementer for one task per spawn. Read .codex/agents/implementer.md first."
config_file = "agents/implementer.toml"

[agents.test-writer]
description = "Coverage-obsessed test writer, external services mocked. Read .codex/agents/test-writer.md first."
config_file = "agents/test-writer.toml"

[agents.terminal]
description = "Command runner — any Bash or PowerShell command; returns only the result the caller asked for. Read .codex/agents/terminal.md first."
config_file = "agents/terminal.toml"

[agents.diagnostician]
description = "Root-cause diagnostician for task failures after fix-cycle exhaustion. Read .codex/agents/diagnostician.md first."
config_file = "agents/diagnostician.toml"
EOF
}

codex_role_toml() { # model-id
  printf 'model = "%s"\n' "$1"
}

settings_json_min() {
  jq -n '{env:{CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:"3"}}'
}

# ---------------------------------------------------------------------------
# emit-set
# ---------------------------------------------------------------------------
declare -A EMIT=()
WARNINGS=0
bump_warn() { WARNINGS=$((WARNINGS + 1)); }

DRY_ACTIONS=()
dry_action() { DRY_ACTIONS+=("$1 $2"); }

set_want_flags() {
  local h s
  FLAGS[want_claude]=false
  FLAGS[want_cursor]=false
  FLAGS[want_copilot]=false
  FLAGS[want_codex]=false
  for h in "${HARNESSES[@]}"; do
    s="$(harness_suffix "$h")"
    FLAGS[want_$s]=true
  done
}

set_is_flags() { # harness or empty (all false)
  FLAGS[is_claude]=false
  FLAGS[is_cursor]=false
  FLAGS[is_copilot]=false
  FLAGS[is_codex]=false
  if [ -n "${1:-}" ]; then
    FLAGS[is_$(harness_suffix "$1")]=true
  fi
}

jq_model() { # harness field
  jq -r --arg h "$1" --arg f "$2" '.models[$h][$f] // empty' <<<"$ANSWERS"
}

load_global_tokens() {
  TOKENS=()
  local k v pn
  pn="$(jq -r '.tokens.PROJECT_NAME // empty' <<<"$ANSWERS")"
  if [ -z "$pn" ]; then
    pn="$(jq -r '.projectName // empty' <<<"$ANSWERS")"
  fi
  [ -n "$pn" ] && TOKENS[PROJECT_NAME]="$pn"
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    v="$(jq -r --arg k "$k" '.tokens[$k] // empty' <<<"$ANSWERS")"
    if jq -e --arg k "$k" '.tokens | has($k)' <<<"$ANSWERS" >/dev/null; then
      TOKENS["$k"]="$v"
    fi
  done < <(jq -r '.tokens // {} | keys[]' <<<"$ANSWERS")
  [ -n "$pn" ] && TOKENS[PROJECT_NAME]="$pn"
  local h pre
  for h in "${HARNESSES[@]}"; do
    pre="$(harness_prefix "$h")"
    v="$(jq_model "$h" frontier)"; [ -n "$v" ] && TOKENS["${pre}_MODEL_FRONTIER"]="$v"
    v="$(jq_model "$h" light)";    [ -n "$v" ] && TOKENS["${pre}_MODEL_LIGHT"]="$v"
  done
  v="$(jq_model "$PRIMARY" loop_chain)"
  TOKENS[LOOP_MODEL_CHAIN]="$v"
}

set_harness_tokens() { # harness
  local h="$1" v
  TOKENS[IDE_DIR]="$(ide_dir_for "$h")"
  v="$(jq_model "$h" frontier)";  [ -n "$v" ] && TOKENS[MODEL_FRONTIER]="$v" || unset 'TOKENS[MODEL_FRONTIER]'
  v="$(jq_model "$h" light)";     [ -n "$v" ] && TOKENS[MODEL_LIGHT]="$v" || unset 'TOKENS[MODEL_LIGHT]'
  v="$(jq_model "$h" alt_family)"; [ -n "$v" ] && TOKENS[MODEL_ALT_FAMILY]="$v" || unset 'TOKENS[MODEL_ALT_FAMILY]'
  v="$(jq_model "$h" frontier_alt_family)"; [ -n "$v" ] && TOKENS[MODEL_FRONTIER_ALT_FAMILY]="$v" || unset 'TOKENS[MODEL_FRONTIER_ALT_FAMILY]'
}

resolve_template() { # abs-src rel → sets RESOLVED (IF → BOOTSTRAP → tokens)
  local src="$1" rel="$2" content stripped
  content="$(read_file_raw "$src")"
  content="$(resolve_if "$content" "$rel")"
  stripped="$(bootstrap_apply "$content" "$rel" strip)"
  scan_unresolved_tokens "$stripped" "$rel"
  content="$(bootstrap_apply "$content" "$rel" apply)"
  content="$(replace_tokens "$content")"
  RESOLVED="$content"
}

put_emit() { # relpath content
  local p="$1" c="$2"
  if [ -n "$c" ] && [ "${c: -1}" != $'\n' ]; then
    c+=$'\n'
  fi
  EMIT["$p"]="$c"
}

copy_skill_tree() { # name dest_prefix translate_mode(claude|cursor|copilot)
  local name="$1" dest_prefix="$2" mode="$3"
  local src_root="$TPL/skills/$name"
  [ -d "$src_root" ] || return 0
  local f rel dest content
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel="${f#"$src_root"/}"
    dest="$rel"
    if [ "$(basename "$rel")" = SKILL.template.md ]; then
      dest="$(dirname "$rel")"
      [ "$dest" = . ] && dest="SKILL.md" || dest="$dest/SKILL.md"
    fi
    resolve_template "$f" "skills/$name/$rel"
    content="$RESOLVED"
    if [ "$(basename "$dest")" = SKILL.md ]; then
      case "$mode" in
        cursor) content="$(translate_cursor_skill "$content")" ;;
      esac
    fi
    put_emit "$dest_prefix/$dest" "$content"
  done < <(LC_ALL=C find "$src_root" -type f | LC_ALL=C sort)
}

emit_agents() { # harness
  local h="$1" dest_dir role src content
  dest_dir="$(ide_dir_for "$h")/agents"
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    role="$(basename "$f" .md)"
    resolve_template "$f" "agents/$(basename "$f")"
    content="$RESOLVED"
    case "$h" in
      claude-code)
        put_emit "$dest_dir/$role.md" "$content"
        ;;
      cursor)
        put_emit "$dest_dir/$role.md" "$(translate_cursor_agent "$role" "$content")"
        ;;
      copilot)
        put_emit ".github/agents/${role}.agent.md" "$(translate_copilot_agent "$role" "$content")"
        ;;
      codex)
        put_emit ".codex/agents/${role}.md" "$(strip_frontmatter "$content")"
        local mid
        case "$role" in
          evaluator|qa-evaluator|diagnostician) mid="${TOKENS[MODEL_FRONTIER]}" ;;
          *) mid="${TOKENS[MODEL_LIGHT]}" ;;
        esac
        put_emit ".codex/agents/${role}.toml" "$(codex_role_toml "$mid")"
        ;;
    esac
  done < <(LC_ALL=C find "$TPL/agents" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
}

emit_skills_for() { # harness
  local h="$1" ide mode name
  ide="$(ide_dir_for "$h")"
  case "$h" in
    claude-code) mode=claude ;;
    cursor)      mode=cursor ;;
    copilot)     mode=copilot ;;
    codex)       return 0 ;; # no skills tree
  esac
  local d
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    name="$(basename "$d")"
    if [ "$name" = research ] && [ "${FLAGS[research]}" != true ]; then
      continue
    fi
    if [ "$h" = copilot ] && [ "$name" = feature ]; then
      local src="$TPL/skills/feature/SKILL.template.md"
      local content
      resolve_template "$src" "skills/feature/SKILL.template.md"
      content="$RESOLVED"
      put_emit ".github/agents/feature.agent.md" "$(translate_copilot_feature "$content")"
      local sub f rel
      for sub in reference templates; do
        if [ -d "$TPL/skills/feature/$sub" ]; then
          while IFS= read -r f; do
            [ -z "$f" ] && continue
            rel="${f#"$TPL/skills/feature/"}"
            resolve_template "$f" "skills/feature/$rel"
            put_emit ".github/skills/feature/$rel" "$RESOLVED"
          done < <(LC_ALL=C find "$TPL/skills/feature/$sub" -type f | LC_ALL=C sort)
        fi
      done
      continue
    fi
    copy_skill_tree "$name" "$ide/skills/$name" "$mode"
  done < <(LC_ALL=C find "$TPL/skills" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
  if [ "${FLAGS[loop]}" = true ]; then
    local src="$TPL/loop/SKILL.template.md"
    if [ -f "$src" ]; then
      local content
      resolve_template "$src" "loop/SKILL.template.md"
      content="$RESOLVED"
      if [ "$mode" = cursor ]; then
        content="$(translate_cursor_skill "$content")"
      fi
      put_emit "$ide/skills/auto-loop/SKILL.md" "$content"
    fi
  fi
}

MODELS_MAP_BYTES=""

emit_models_map_once() {
    resolve_template "$TPL/models.map.md" "models.map.md"
    MODELS_MAP_BYTES="$RESOLVED"
}

emit_orchestration() { # harness (skip root-shared if not writer)
  local h="$1" content dest
  resolve_template "$TPL/ORCHESTRATION.md" "ORCHESTRATION.md"
  content="$RESOLVED"
  case "$h" in
    claude-code|cursor)
      dest="$(ide_dir_for "$h")/ORCHESTRATION.md"
      put_emit "$dest" "$content"
      ;;
    copilot|codex)
      if [ "$h" = "$ORCH_ROOT_WRITER" ]; then
        put_emit "ORCHESTRATION.md" "$content"
      fi
      ;;
  esac
}

emit_single_copy() {
  set_is_flags "$PRIMARY"
  set_harness_tokens "$PRIMARY"
  local f dest content
  if [ "${FLAGS[loop]}" = true ]; then
    for f in loop.sh loop.ps1 breaker.sh breaker.ps1 PROMPT.md; do
      if [ -f "$TPL/loop/$f" ]; then
        resolve_template "$TPL/loop/$f" "loop/$f"
        content="$RESOLVED"
        put_emit "_loop/$f" "$content"
      fi
    done
  fi
  for f in log-spawn.sh log-spawn.ps1; do
    if [ -f "$TPL/tools/$f" ]; then
      resolve_template "$TPL/tools/$f" "tools/$f"
      content="$RESOLVED"
      put_emit "_kit/$f" "$content"
    fi
  done
}

SEED_CONTENT=""
prepare_seed() {
  SEED_CONTENT=""
  if [ "${FLAGS[loop]}" = true ] && [ -f "$TPL/loop/backlog.md" ]; then
    set_is_flags "$PRIMARY"
    set_harness_tokens "$PRIMARY"
    resolve_template "$TPL/loop/backlog.md" "loop/backlog.md"
    SEED_CONTENT="$RESOLVED"
  fi
}

# ---------------------------------------------------------------------------
# answers load / validate
# ---------------------------------------------------------------------------
KNOWN_HARNESS='["claude-code","cursor","copilot","codex"]'
HARNESSES=()
PRIMARY=""
ANSWERS=""
FORGE_KIND=""
FORGE_HOST=""

load_answers_json() { # json string
  ANSWERS="$1"
  if ! jq -e . >/dev/null 2>&1 <<<"$ANSWERS"; then
    die 2 "answers file unreadable"
  fi
}

validate_answers_schema() {
  local v
  v="$(jq -r '.schema // empty' <<<"$ANSWERS")"
  if [ "$v" != 1 ]; then
    add_problem "schema must be 1 (got '${v:-missing}')"
  fi
  if ! jq -e '.harnesses | type == "array" and length >= 1' <<<"$ANSWERS" >/dev/null; then
    add_problem "harnesses must be a non-empty array"
  else
    local h
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      case "$h" in
        claude-code|cursor|copilot|codex) HARNESSES+=("$h") ;;
        *) add_problem "unknown harness '$h'" ;;
      esac
    done < <(jq -r '.harnesses[]' <<<"$ANSWERS")
  fi
  PRIMARY="$(jq -r '.primary // empty' <<<"$ANSWERS")"
  if [ -z "$PRIMARY" ]; then
    add_problem "primary is missing"
  else
    local found=0 h
    for h in "${HARNESSES[@]+"${HARNESSES[@]}"}"; do
      [ "$h" = "$PRIMARY" ] && found=1
    done
    if [ "$found" -eq 0 ]; then
      add_problem "primary '$PRIMARY' is not in harnesses"
    fi
  fi
  local h
  for h in "${HARNESSES[@]+"${HARNESSES[@]}"}"; do
    if ! jq -e --arg h "$h" '.models[$h] | type == "object"' <<<"$ANSWERS" >/dev/null; then
      add_problem "models entry missing for harness '$h'"
    fi
  done
  local f
  for f in research loop greenfield lint typecheck models_pinned; do
    if ! jq -e --arg f "$f" '.flags | type == "object" and has($f)' <<<"$ANSWERS" >/dev/null; then
      add_problem "flags.$f missing"
      FLAGS[$f]=false
    else
      if jq -e --arg f "$f" '.flags[$f] == true' <<<"$ANSWERS" >/dev/null; then
        FLAGS[$f]=true
      else
        FLAGS[$f]=false
      fi
    fi
  done
  FORGE_KIND="$(jq -r '.forge.kind // empty' <<<"$ANSWERS")"
  FORGE_HOST="$(jq -r '.forge.host // empty' <<<"$ANSWERS")"
  case "$FORGE_KIND" in
    github|azuredevops|gitlab|none) ;;
    *) add_problem "forge.kind must be github|azuredevops|gitlab|none (got '${FORGE_KIND:-missing}')" ;;
  esac
}

load_bootstrap_map() {
  BOOTSTRAP_VAL=()
  BOOTSTRAP_HAS=()
  if jq -e '.bootstrap | type == "object"' <<<"$ANSWERS" >/dev/null; then
    local id
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      BOOTSTRAP_HAS["$id"]=1
      BOOTSTRAP_VAL["$id"]="$(jq -r --arg id "$id" '.bootstrap[$id] // ""' <<<"$ANSWERS")"
    done < <(jq -r '.bootstrap | keys[]' <<<"$ANSWERS")
  fi
}

walk_all_templates() {
  LC_ALL=C find "$TPL" -type f | LC_ALL=C sort
}

scan_all_templates() {
  local f rel
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel="$(rel_tpl "$f")"
    scan_if_syntax "$f" "$rel"
    scan_bootstrap_ids_in "$f" "$rel"
  done < <(walk_all_templates)
}

flush_syntax() {
  if [ ${#SYNTAX_ERRS[@]} -gt 0 ]; then
    printf 'emit: %s\n' "${SYNTAX_ERRS[@]}" | LC_ALL=C sort >&2
    exit 6
  fi
}

flush_problems() {
  if [ ${#PROBLEMS[@]} -gt 0 ]; then
    printf 'emit: %s\n' "${PROBLEMS[@]}" | LC_ALL=C sort >&2
    exit 3
  fi
}

flush_unknown_flags() {
  if [ ${#UNKNOWN_FLAGS[@]} -gt 0 ]; then
    local n
    for n in $(printf '%s\n' "${!UNKNOWN_FLAGS[@]}" | LC_ALL=C sort); do
      printf 'emit: unknown IF flag %s at %s\n' "$n" "${UNKNOWN_FLAGS[$n]}" >&2
    done
    exit 3
  fi
}

compute_missing_bootstrap() {
  MISSING_BOOTSTRAP=()
  local id
  for id in $(printf '%s\n' "${!BOOTSTRAP_ID_PATH[@]}" | LC_ALL=C sort); do
    if [ -z "${BOOTSTRAP_HAS[$id]+x}" ]; then
      MISSING_BOOTSTRAP+=("$id")
    fi
  done
}

# ---------------------------------------------------------------------------
# pointers, line appends, settings, config
# ---------------------------------------------------------------------------
file_has_marker() {
  local path="$1" marker="$2"
  [ -f "$path" ] && grep -Fq -- "$marker" "$path"
}

planned_pointer_content() { # destpath new-section → full file bytes or empty if skip
  local dest="$1" section="$2"
  if [ -f "$dest" ] && grep -Fq -- "$POINTER_MARKER" "$dest"; then
    printf ''
    return 1
  fi
  if [ ! -f "$dest" ]; then
    printf '%s' "$(ensure_trailing_nl "$section")"
    return 0
  fi
  local existing
  existing="$(read_file_raw "$dest")"
  existing="$(ensure_trailing_nl "$existing")"
  printf '%s\n%s' "${existing%$'\n'}" "$(ensure_trailing_nl "$section")"
  return 0
}

append_line_once_bytes() { # current-or-empty line → stdout ending with NL
  local current="$1" line="$2"
  current="${current%$'\n'}"
  LINE_CHANGED=0
  if [ -n "$current" ] && printf '%s\n' "$current" | grep -Fxq -- "$line"; then
    printf '%s\n' "$current"
    return
  fi
  LINE_CHANGED=1
  if [ -z "$current" ]; then
    printf '%s\n' "$line"
  else
    printf '%s\n%s\n' "$current" "$line"
  fi
}

planned_git_lines() {
  GA_LINES=('_goals/*/orchestration-log.md merge=union')
  GI_LINES=('_kit/')
  if [ "${FLAGS[loop]}" = true ]; then
    GA_LINES+=('_goals/LEARNINGS.md merge=union' '_goals/ESCALATIONS.md merge=union' '*.sh text eol=lf' '*.ps1 text eol=lf')
    GI_LINES+=('_goals/breaker-state.json')
  fi
}

# 0 = would append or create; 1 = every planned line already present.
git_append_would_change() {
  local file="$1"
  shift
  if [ ! -f "$file" ]; then
    return 0
  fi
  local cur line
  cur="$(read_file_raw "$file")"
  cur="${cur%$'\n'}"
  for line in "$@"; do
    if [ -z "$cur" ] || ! printf '%s\n' "$cur" | grep -Fxq -- "$line"; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# collect emit set for all harnesses
# ---------------------------------------------------------------------------
ORCH_ROOT_WRITER=""
choose_orch_root_writer() {
  ORCH_ROOT_WRITER=""
  local h
  for h in "${HARNESSES[@]}"; do
    case "$h" in
      copilot|codex)
        if [ "$PRIMARY" = copilot ] || [ "$PRIMARY" = codex ]; then
          if [ "$h" = "$PRIMARY" ]; then
            ORCH_ROOT_WRITER="$h"
            return
          fi
        fi
        ;;
    esac
  done
  for h in "${HARNESSES[@]}"; do
    case "$h" in
      copilot|codex) ORCH_ROOT_WRITER="$h"; return ;;
    esac
  done
}

collect_emit_set() {
  EMIT=()
  set_want_flags
  choose_orch_root_writer
  local h want_map=0
  for h in "${HARNESSES[@]}"; do
    case "$h" in claude-code|cursor) want_map=1 ;; esac
  done
  set_is_flags ""
  load_global_tokens
  if [ "$want_map" -eq 1 ]; then
    # is_* unused in models.map.md; resolve once so copies are byte-identical
    set_harness_tokens "$PRIMARY"
    emit_models_map_once
  fi
  for h in "${HARNESSES[@]}"; do
    set_is_flags "$h"
    set_harness_tokens "$h"
    emit_agents "$h"
    emit_skills_for "$h"
    emit_orchestration "$h"
    case "$h" in
      claude-code|cursor)
        put_emit "$(ide_dir_for "$h")/skills/setup-models.map.md" "$MODELS_MAP_BYTES"
        ;;
    esac
    if [ "$h" = cursor ]; then
      put_emit ".cursor/rules/orchestration.mdc" "$(pointer_cursor_mdc)"
    fi
  done
  emit_single_copy
  prepare_seed
}

# ---------------------------------------------------------------------------
# old manifest
# ---------------------------------------------------------------------------
declare -A OLD_HASH=()
OLD_HAS_MANIFEST=0
OLD_INSTALLED_AT=""
HAS_OLD_ANSWERS=0

load_old_manifest() {
  OLD_HASH=()
  OLD_HAS_MANIFEST=0
  OLD_INSTALLED_AT=""
  HAS_OLD_ANSWERS=0
  if [ -f "$MANIFEST" ]; then
    OLD_HAS_MANIFEST=1
    if ! jq -e . >/dev/null 2>&1 <"$MANIFEST"; then
      die 2 "answers file unreadable"
    fi
    OLD_INSTALLED_AT="$(jq -r '.installedAt // empty' "$MANIFEST")"
    if jq -e '.answers' "$MANIFEST" >/dev/null 2>&1; then
      HAS_OLD_ANSWERS=1
    fi
    local k v
    while IFS=$'\t' read -r k v; do
      [ -z "$k" ] && continue
      OLD_HASH["$k"]="$v"
    done < <(jq -r '.files // {} | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST")
  fi
}

# ---------------------------------------------------------------------------
# write / prune / manifest / verify
# ---------------------------------------------------------------------------
WRITTEN_N=0
UNCHANGED_M=0
PRUNED_P=0
SEEDS_KEPT=0
BLOCKED_PATHS=()
declare -A NEW_FILES=() # path → hash (emit-set + foreign)

plan_and_maybe_write() {
  BLOCKED_PATHS=()
  WRITTEN_N=0
  UNCHANGED_M=0
  local p disk_hash old new_hash
  local -a sorted=()
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sorted+=("$p")
  done < <(printf '%s\n' "${!EMIT[@]}" | LC_ALL=C sort)
  for p in "${sorted[@]}"; do
    new_hash="$(sha256_str "${EMIT[$p]}")"
    NEW_FILES["$p"]="$new_hash"
    if [ -f "$ROOT/$p" ]; then
      disk_hash="$(sha256_file "$ROOT/$p")"
    else
      disk_hash=""
    fi
    if [ -n "$disk_hash" ] && [ "$disk_hash" = "$new_hash" ]; then
      UNCHANGED_M=$((UNCHANGED_M + 1))
      dry_action skip "$p"
      continue
    fi
    # bytes differ or absent
    if [ "$OLD_HAS_MANIFEST" -eq 1 ] && [ -n "$disk_hash" ]; then
      old="${OLD_HASH[$p]:-}"
      if [ -n "$old" ] && [ "$disk_hash" != "$old" ] && [ "$FORCE" -eq 0 ]; then
        BLOCKED_PATHS+=("$p")
        dry_action blocked "$p"
        continue
      fi
    fi
    WRITTEN_N=$((WRITTEN_N + 1))
    dry_action write "$p"
  done
}

write_emit_files() {
  local p
  local -a sorted=()
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    sorted+=("$p")
  done < <(printf '%s\n' "${!EMIT[@]}" | LC_ALL=C sort)
  for p in "${sorted[@]}"; do
    local dest="$ROOT/$p"
    local new_hash
    new_hash="$(sha256_str "${EMIT[$p]}")"
    if [ -f "$dest" ] && [ "$(sha256_file "$dest")" = "$new_hash" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    printf '%s' "${EMIT[$p]}" > "$dest"
    if [[ "$p" == *.sh ]]; then
      chmod +x "$dest"
    fi
  done
}

plan_seeds() {
  if [ -z "$SEED_CONTENT" ]; then
    return
  fi
  local p='_goals/backlog.md'
  if [ -f "$ROOT/$p" ]; then
    SEEDS_KEPT=$((SEEDS_KEPT + 1))
    dry_action seed "$p"
  else
    dry_action seed "$p"
  fi
}

write_seed() {
  if [ -z "$SEED_CONTENT" ]; then
    return
  fi
  local dest="$ROOT/_goals/backlog.md"
  if [ ! -f "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    if [ -n "$SEED_CONTENT" ] && [ "${SEED_CONTENT: -1}" != $'\n' ]; then
      SEED_CONTENT+=$'\n'
    fi
    printf '%s' "$SEED_CONTENT" > "$dest"
  else
    SEEDS_KEPT=$((SEEDS_KEPT + 1))
  fi
}

plan_prune_and_foreign() {
  PRUNED_P=0
  local p old disk
  for p in "${!OLD_HASH[@]}"; do
    if is_seed_path "$p"; then
      continue
    fi
    if [ -n "${EMIT[$p]+x}" ]; then
      continue
    fi
    old="${OLD_HASH[$p]}"
    if is_kit_owned "$p"; then
      if [ -f "$ROOT/$p" ]; then
        disk="$(sha256_file "$ROOT/$p")"
        if [ "$disk" = "$old" ]; then
          PRUNED_P=$((PRUNED_P + 1))
          dry_action prune "$p"
        else
          bump_warn
          dry_action warn "$p"
        fi
      else
        # already gone; nothing to prune
        :
      fi
    else
      # foreign
      if [ -f "$ROOT/$p" ]; then
        NEW_FILES["$p"]="$(sha256_file "$ROOT/$p")"
        dry_action keep "$p"
      else
        bump_warn
        dry_action warn "$p"
      fi
    fi
  done
}

do_prune() {
  local p old disk
  for p in "${!OLD_HASH[@]}"; do
    if is_seed_path "$p"; then
      continue
    fi
    if [ -n "${EMIT[$p]+x}" ]; then
      continue
    fi
    if ! is_kit_owned "$p"; then
      if [ -f "$ROOT/$p" ]; then
        NEW_FILES["$p"]="$(sha256_file "$ROOT/$p")"
      fi
      continue
    fi
    old="${OLD_HASH[$p]}"
    if [ -f "$ROOT/$p" ]; then
      disk="$(sha256_file "$ROOT/$p")"
      if [ "$disk" = "$old" ]; then
        rm -f "$ROOT/$p"
        PRUNED_P=$((PRUNED_P + 1))
        local dir
        dir="$(dirname "$ROOT/$p")"
        rmdir -p --ignore-fail-on-non-empty "$dir" 2>/dev/null || true
      fi
    fi
  done
}


# Pointers / settings / gitignore — side effects, not emit-set (except
# settings.json / config.toml when this run creates or appends them).
harness_wanted() {
  local h
  for h in "${HARNESSES[@]}"; do
    [ "$h" = "$1" ] && return 0
  done
  return 1
}

put_optional_kit_files() {
  local cf light tables existing
  if harness_wanted claude-code; then
    if [ ! -f "$ROOT/.claude/settings.json" ]; then
      put_emit ".claude/settings.json" "$(settings_json_min)"
    elif ! jq -e '.env.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH' "$ROOT/.claude/settings.json" >/dev/null 2>&1; then
      bump_warn
      dry_action warn ".claude/settings.json"
      printf 'emit: .claude/settings.json present without CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH — left untouched\n' >&2
    fi
  fi
  if harness_wanted codex; then
    cf="$ROOT/.codex/config.toml"
    light="$(jq_model "codex" light)"
    tables="$(codex_config_tables "$light")"
    if [ ! -f "$cf" ]; then
      put_emit ".codex/config.toml" "$(ensure_trailing_nl "$tables")"
    elif ! grep -Fq -- "$CODEX_AGENTS_MARKER" "$cf"; then
      existing="$(read_file_raw "$cf")"
      existing="$(ensure_trailing_nl "$existing")"
      put_emit ".codex/config.toml" "$(printf '%s\n%s' "${existing%$'\n'}" "$(ensure_trailing_nl "$tables")")"
    fi
  fi
}

append_pointer_file() {
  local dest="$1" section="$2" existing
  if file_has_marker "$dest" "$POINTER_MARKER"; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  section="${section%$'\n'}"
  if [ -f "$dest" ]; then
    existing="$(read_file_raw "$dest")"
    existing="${existing%$'\n'}"
    printf '%s\n%s\n' "$existing" "$section" > "$dest"
  else
    printf '%s\n' "$section" > "$dest"
  fi
}

plan_pointers_and_git() {
  if harness_wanted claude-code; then
    if [ -f "$ROOT/CLAUDE.md" ] && grep -Fq -- "$POINTER_MARKER" "$ROOT/CLAUDE.md"; then
      dry_action keep CLAUDE.md
    else
      dry_action write CLAUDE.md
    fi
  fi
  if harness_wanted copilot; then
    if [ -f "$ROOT/.github/copilot-instructions.md" ] && grep -Fq -- "$POINTER_MARKER" "$ROOT/.github/copilot-instructions.md"; then
      dry_action skip ".github/copilot-instructions.md"
    else
      dry_action write ".github/copilot-instructions.md"
    fi
  fi
  if harness_wanted codex; then
    if [ -f "$ROOT/AGENTS.md" ] && grep -Fq -- "$POINTER_MARKER" "$ROOT/AGENTS.md"; then
      dry_action skip AGENTS.md
    else
      dry_action write AGENTS.md
    fi
  fi
  planned_git_lines
  if git_append_would_change "$ROOT/.gitattributes" "${GA_LINES[@]}"; then
    dry_action write .gitattributes
  else
    dry_action keep .gitattributes
  fi
  if git_append_would_change "$ROOT/.gitignore" "${GI_LINES[@]}"; then
    dry_action write .gitignore
  else
    dry_action keep .gitignore
  fi
}

write_pointers_and_git() {
  local line cur sz
  if harness_wanted claude-code; then
    append_pointer_file "$ROOT/CLAUDE.md" "$(pointer_claude)"
  fi
  if harness_wanted copilot; then
    append_pointer_file "$ROOT/.github/copilot-instructions.md" "$(pointer_copilot)"
  fi
  if harness_wanted codex; then
    append_pointer_file "$ROOT/AGENTS.md" "$(pointer_agents_md)"
    if [ -f "$ROOT/AGENTS.md" ]; then
      sz="$(wc -c < "$ROOT/AGENTS.md" | tr -d '[:space:]')"
      if [ "$sz" -gt 32768 ]; then
        bump_warn
        printf 'emit: AGENTS.md exceeds 32 KiB after pointer append\n' >&2
      fi
    fi
  fi
  planned_git_lines
  if [ -f "$ROOT/.gitattributes" ]; then cur="$(read_file_raw "$ROOT/.gitattributes")"; else cur=""; fi
  for line in "${GA_LINES[@]}"; do
    cur="$(append_line_once_bytes "$cur" "$line")"
  done
  mkdir -p "$ROOT"
  printf '%s\n' "$cur" > "$ROOT/.gitattributes"
  if [ -f "$ROOT/.gitignore" ]; then cur="$(read_file_raw "$ROOT/.gitignore")"; else cur=""; fi
  for line in "${GI_LINES[@]}"; do
    cur="$(append_line_once_bytes "$cur" "$line")"
  done
  printf '%s\n' "$cur" > "$ROOT/.gitignore"
}

# jq -n pretty-print already ends with newline. Don't add another.
write_manifest() {
  local installed
  if [ -n "$OLD_INSTALLED_AT" ]; then
    installed="$OLD_INSTALLED_AT"
  elif [ -n "${EMIT_DATE:-}" ]; then
    installed="$EMIT_DATE"
  else
    installed="$(date +%Y-%m-%d)"
  fi
  local options files_json answers_sorted seed_json harness_json opt_extra='{}'
  if [ -n "$FORGE_HOST" ]; then
    opt_extra="$(jq -n --arg h "$FORGE_HOST" '{forgeHost:$h}')"
  fi
  options="$(jq -n -S \
    --argjson research "$(jq -c '.flags.research' <<<"$ANSWERS")" \
    --argjson loop "$(jq -c '.flags.loop' <<<"$ANSWERS")" \
    --argjson greenfield "$(jq -c '.flags.greenfield' <<<"$ANSWERS")" \
    --argjson lint "$(jq -c '.flags.lint' <<<"$ANSWERS")" \
    --argjson typecheck "$(jq -c '.flags.typecheck' <<<"$ANSWERS")" \
    --argjson models_pinned "$(jq -c '.flags.models_pinned' <<<"$ANSWERS")" \
    --arg forge "$FORGE_KIND" \
    --argjson extra "$opt_extra" \
    '{research:$research,loop:$loop,greenfield:$greenfield,lint:$lint,typecheck:$typecheck,models_pinned:$models_pinned,forge:$forge} + $extra')"
  files_json='{}'
  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    files_json="$(jq -c --arg p "$p" --arg h "${NEW_FILES[$p]}" '. + {($p): $h}' <<<"$files_json")"
  done < <(printf '%s\n' "${!NEW_FILES[@]}" | LC_ALL=C sort)
  files_json="$(jq -S '.' <<<"$files_json")"
  answers_sorted="$(jq -S '.' <<<"$ANSWERS")"
  if [ -n "$SEED_CONTENT" ]; then
    seed_json='["_goals/backlog.md"]'
  else
    seed_json='[]'
  fi
  harness_json="$(jq -c '.harnesses' <<<"$ANSWERS")"
  jq -n \
    --arg kit "agent-kit" \
    --arg kitVersion "$VERSION" \
    --arg installedAt "$installed" \
    --argjson harnesses "$harness_json" \
    --arg primary "$PRIMARY" \
    --argjson options "$options" \
    --argjson seedFiles "$seed_json" \
    --argjson files "$files_json" \
    --argjson answers "$answers_sorted" \
    '{kit:$kit,kitVersion:$kitVersion,installedAt:$installedAt,harnesses:$harnesses,primary:$primary,options:$options,seedFiles:$seedFiles,files:$files,answers:$answers}' \
    > "$MANIFEST"
}

VERIFY_ERRS=()
record_verify() { VERIFY_ERRS+=("$1"); }

verify_content() { # path content
  local p="$1" content="$2"
  local hits
  if printf '%s' "$content" | grep -qE '\{\{[A-Z_]+\}\}'; then
    record_verify "verify: $p: leftover token"
    return 1
  fi
  if printf '%s' "$content" | grep -qF '<!-- BOOTSTRAP'; then
    record_verify "verify: $p: leftover BOOTSTRAP"
    return 1
  fi
  if printf '%s' "$content" | grep -qF '<!-- IF'; then
    record_verify "verify: $p: leftover IF"
    return 1
  fi
  if printf '%s' "$content" | grep -qF '<!-- ENDIF'; then
    record_verify "verify: $p: leftover ENDIF"
    return 1
  fi
  return 0
}

fm_name() { # content → name or empty
  local content="$1"
  split_fm "$content" || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == name:* ]]; then
      local n="${line#name:}"
      n="${n#"${n%%[![:space:]]*}"}"
      n="${n%\"}"; n="${n#\"}"
      printf '%s' "$n"
      return
    fi
  done < <(printf '%s' "$FM_INNER")
}

verify_all() {
  local rc=0 p content expected name
  VERIFY_ERRS=()
  for p in "${!EMIT[@]}"; do
    content="${EMIT[$p]}"
    if ! verify_content "$p" "$content"; then
      rc=1
    fi
    case "$p" in
      */agents/*.md|*/agents/*.agent.md|.github/agents/*.agent.md)
        name="$(fm_name "$content")"
        if [ -n "$name" ]; then
          expected="$(basename "$p")"
          expected="${expected%.agent.md}"
          expected="${expected%.md}"
          if [ "$name" != "$expected" ]; then
            record_verify "verify: $p: name: $name != $expected"
            rc=1
          fi
        fi
        ;;
      */skills/*/SKILL.md)
        name="$(fm_name "$content")"
        expected="$(basename "$(dirname "$p")")"
        if [ -n "$name" ] && [ "$name" != "$expected" ]; then
          record_verify "verify: $p: name: $name != $expected"
          rc=1
        fi
        ;;
    esac
  done
  if [ -d "$ROOT/.cursor" ]; then
    local hit
    hit="$(grep -rn '\.claude/' "$ROOT/.cursor" --exclude-dir=setup 2>/dev/null || true)"
    if [ -n "$hit" ]; then
      record_verify 'verify: .cursor/: contains .claude/ reference'
      rc=1
    fi
  fi
  local ps1_files=() q
  for p in "${!EMIT[@]}"; do
    [[ "$p" == *.ps1 ]] && ps1_files+=("$p")
  done
  if [ ${#ps1_files[@]} -gt 0 ]; then
    if command -v pwsh >/dev/null 2>&1; then
      for p in "${ps1_files[@]}"; do
        if [ -f "$ROOT/$p" ]; then
          if ! pwsh -NoProfile -Command "
            \$e = \$null
            [void][System.Management.Automation.Language.Parser]::ParseFile('$ROOT/$p', [ref]\$null, [ref]\$e)
            if (\$e) { \$e | ForEach-Object { \$_.Message }; exit 1 }
          " >/dev/null 2>&1; then
            record_verify "verify: $p: pwsh parse failed"
            rc=1
          fi
        fi
      done
    else
      bump_warn
      printf 'emit: pwsh not on PATH — skipped .ps1 parse\n' >&2
    fi
  fi
  if [ ${#VERIFY_ERRS[@]} -gt 0 ]; then
    printf 'emit: %s\n' "${VERIFY_ERRS[@]}" | LC_ALL=C sort >&2
    return 1
  fi
  return $rc
}

print_summary() {
  printf 'emit: written %s · unchanged %s · pruned %s · seeds-kept %s · warnings %s · manifest orchestration-kit.manifest.json · kit %s\n' \
    "$WRITTEN_N" "$UNCHANGED_M" "$PRUNED_P" "$SEEDS_KEPT" "$WARNINGS" "$VERSION"
}


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
run_emit() {
  local id n rc bp _mid

  load_old_manifest

  if [ -n "$ANSWERS_FILE" ]; then
    [ -f "$ANSWERS_FILE" ] || die 2 "answers file unreadable"
    load_answers_json "$(read_file_raw "$ANSWERS_FILE")"
  elif [ "$OLD_HAS_MANIFEST" -eq 1 ]; then
    if [ "$HAS_OLD_ANSWERS" -eq 0 ]; then
      die 3 "answers missing from manifest — pass --answers (pre-v0.27.0 install)"
    fi
    load_answers_json "$(jq -c '.answers' "$MANIFEST")"
  else
    die 2 "answers file unreadable"
  fi

  validate_answers_schema
  load_kit_skills
  scan_all_templates
  flush_syntax

  if [ ${#UNKNOWN_FLAGS[@]} -gt 0 ]; then
    for n in $(printf '%s\n' "${!UNKNOWN_FLAGS[@]}" | LC_ALL=C sort); do
      add_problem "unknown IF flag '$n' at ${UNKNOWN_FLAGS[$n]}"
    done
  fi

  flush_problems
  load_bootstrap_map
  compute_missing_bootstrap

  if [ "$CHECK_ANSWERS" -eq 1 ]; then
    rc=0
    for id in "${MISSING_BOOTSTRAP[@]+"${MISSING_BOOTSTRAP[@]}"}"; do
      [ -z "$id" ] && continue
      printf '%s\t%s\n' "$id" "${BOOTSTRAP_ID_PATH[$id]}"
      rc=3
    done
    exit "$rc"
  fi

  for _mid in "${MISSING_BOOTSTRAP[@]+"${MISSING_BOOTSTRAP[@]}"}"; do
    [ -z "$_mid" ] && continue
    bump_warn
  done

  collect_emit_set
  put_optional_kit_files
  flush_syntax
  flush_problems

  NEW_FILES=()
  DRY_ACTIONS=()
  plan_and_maybe_write
  plan_seeds
  plan_prune_and_foreign
  plan_pointers_and_git

  if [ ${#BLOCKED_PATHS[@]} -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s\n' "${DRY_ACTIONS[@]}" | LC_ALL=C sort
      exit 4
    fi
    printf 'emit: blocked %s\n' "${BLOCKED_PATHS[@]}" | LC_ALL=C sort >&2
    exit 4
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "${DRY_ACTIONS[@]}" | LC_ALL=C sort
    exit 0
  fi

  write_emit_files
  SEEDS_KEPT=0
  write_seed
  PRUNED_P=0
  do_prune
  write_pointers_and_git
  write_manifest

  if ! verify_all; then
    exit 5
  fi
  print_summary
  exit 0
}

run_emit
