#!/usr/bin/env bash
# Guard: the `hook-log` stop-hook telemetry tool (skills/agent-kit/templates/tools/hook-log.sh).
#
# Behavioral section — runs the CANONICAL tool (override with HOOK_LOG_BIN=<path> for mutation
# testing) over fixture payloads built in this suite, in temp roots only (no network, no LLM,
# no emit, no self-install):
#   - the five valid payloads (Claude Code SubagentStop / Stop / StopFailure, Cursor subagentStop /
#     stop) each give one line with the exact expected bytes (HOOK_LOG_NOW fixed), the SHA-256 key
#     has a known answer, and the other awk flavors on this machine agree
#   - the output contract: `hook cursor` prints exactly `{}` plus a newline and `hook claude`
#     prints nothing, with exit 0, on logged, skipped, failed and malformed paths alike
#   - skip rules 1-5 (AGENT_KIT_HOOK_LOG=0, empty / brace-less stdin or a first non-whitespace
#     character other than a left brace, a Cursor caller on the claude path, a foreign
#     hook_event_name, an unwritable log dir) write nothing; every skip case has a logging
#     control so no probe is vacuous
#   - metadata only: a unique marker in each never-logged field (error_details included) never
#     reaches the log
#   - top-level keys only: an escaped key inside a string and a key inside a nested object or
#     array are never read; value types (numbers, strings, modified_files arrays) are checked
#   - StopFailure: status "error" and the `error` field (snake_case strings only, null for every
#     other event and every other value)
#   - idempotency by payload hash (also against events.1.jsonl), rotation at a byte cap, the
#     mkdir lock (fresh, stale), a duplicate that never rotates, the cksum fallback, and a PATH
#     limited to the documented tools
#   - `summary` output (exact bytes, the error column, the zero-claude hint), its empty case,
#     a root holding a backslash, usage errors, and that it only reads
#   - an exported CDPATH never changes a resolved root (hook-log and kit-guard)
#   - mutation proofs: each probe above passes on the tool and fails on a mutated copy
#   - static guards on the tool file (portability, never-steers strings, no names, no templates tokens,
#     header columns)
# Output follows the trace-lint suite: PASS:/FAIL: lines, a summary, RESULT.
# Exit 0 when no FAIL; 1 otherwise.
set -u

export LC_ALL=C
unset CURSOR_PROJECT_DIR CLAUDE_PROJECT_DIR AGENT_KIT_HOOK_LOG AGENT_KIT_HOOK_LOG_MAX_BYTES
export HOOK_LOG_NOW=2026-10-29T12:00:00Z

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

HOOK="${HOOK_LOG_BIN:-$REPO_ROOT/skills/agent-kit/templates/tools/hook-log.sh}"
KG_HOOK="${KIT_GUARD_BIN:-$REPO_ROOT/skills/agent-kit/templates/tools/kit-guard.sh}"

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

pass=0
fail=0
skip=0

_suite_cleanup() {
  chmod -R u+rwx "$FIXTURE_TMPDIR" 2>/dev/null
  rm -rf "$FIXTURE_TMPDIR"
}
trap _suite_cleanup EXIT

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

FX="$FIXTURE_TMPDIR/fx"
mkdir -p "$FX"
printf '{}\n' > "$FX/want-obj"
EXTRA_ENV=''
LOGREL='_memory/work/hooks'

# --- helpers -----------------------------------------------------------------------------------

new_root() { # → ROOT (an empty temp dir inside FIXTURE_TMPDIR)
  ROOT="$(mktemp -d "$FIXTURE_TMPDIR/root.XXXXXX")" || exit 1
  assert_fixture_root "$ROOT" || exit 1
}

logf() { printf '%s/%s/events.jsonl' "$1" "$LOGREL"; }
log1f() { printf '%s/%s/events.1.jsonl' "$1" "$LOGREL"; }

nlines() { # <file> → line count (0 when missing)
  if [ -f "$1" ]; then wc -l < "$1" | sed 's/ //g'; else echo 0; fi
}

# run_hook <harness> <root> <payload>: RC, ERR; stdout bytes in $FX/out.bin. EXTRA_ENV
# (space-separated NAME=value words) is applied through env(1) and then cleared.
run_hook() {
  printf '%s' "$3" | env $EXTRA_ENV "$BASH" "$HOOK" hook "$1" --root "$2" >"$FX/out.bin" 2>"$FX/err.txt"
  RC=$?
  ERR="$(cat "$FX/err.txt")"
  EXTRA_ENV=''
}

# contract_ok <harness>: exit 0, nothing on stderr, and stdout is exactly `{}\n` (cursor) / empty (claude).
contract_ok() {
  [ "$RC" -eq 0 ] || return 1
  [ -z "$ERR" ] || return 1
  if [ "$1" = cursor ]; then
    cmp -s "$FX/out.bin" "$FX/want-obj"
  else
    [ ! -s "$FX/out.bin" ]
  fi
}

# file_is <file> <text>: the file holds exactly <text> plus one trailing newline.
file_is() {
  printf '%s\n' "$2" > "$FX/want.txt"
  cmp -s "$FX/want.txt" "$1"
}

sha_hex() { # stdin → SHA-256 hex digest
  local h
  if command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum)"
  else
    h="$(shasum -a 256)"
  fi
  printf '%s' "${h%% *}"
}
exp_key() { local h; h="$(printf '%s' "$1" | sha_hex)"; printf '%s' "${h:0:16}"; }
exp_cksum_key() { local c; c="$(printf '%s' "$1" | cksum)"; printf 'c%s' "${c%% *}"; }

fld() { # <log> <name> <next-name> → the JSON token of field <name> (up to the next field)
  sed -n 's/.*,"'"$2"'":\(.*\),"'"$3"'":.*/\1/p' "$1"
}

# expect_logged <name> <harness> <payload> <want-template>: one exact line (@KEY@ → sha key) + contract.
expect_logged() {
  local name="$1" h="$2" p="$3" tpl="$4" want
  want="${tpl/@KEY@/$(exp_key "$p")}"
  new_root
  run_hook "$h" "$ROOT" "$p"
  if ! contract_ok "$h"; then
    report FAIL "$name" "contract: rc=$RC err=[$ERR] out=[$(cat "$FX/out.bin")]"
  elif ! file_is "$(logf "$ROOT")" "$want"; then
    report FAIL "$name" "log=[$(cat "$(logf "$ROOT")" 2>/dev/null)] want=[$want]"
  else
    report PASS "$name"
  fi
}

# expect_skip <name> <harness> <payload>: contract holds and nothing at all is written.
expect_skip() {
  local name="$1" h="$2" p="$3"
  new_root
  run_hook "$h" "$ROOT" "$p"
  if ! contract_ok "$h"; then
    report FAIL "$name" "contract: rc=$RC err=[$ERR] out=[$(cat "$FX/out.bin")]"
  elif [ -e "$ROOT/_memory" ]; then
    report FAIL "$name" "wrote under _memory: $(find "$ROOT" -type f | sed "s|$ROOT/||" | tr '\n' ' ')"
  else
    report PASS "$name"
  fi
}

# --- fixture payloads ---------------------------------------------------------------------------

P_CLAUDE_SUB='{"session_id":"sess-1","prompt_id":"prm-1","transcript_path":"/t/a.jsonl","cwd":"/work","permission_mode":"default","hook_event_name":"SubagentStop","stop_hook_active":false,"agent_id":"ag-1","agent_type":"implementer","agent_transcript_path":"/t/ag.jsonl","last_assistant_message":"done","background_tasks":[],"session_crons":[]}'
W_CLAUDE_SUB='{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"SubagentStop","session":"sess-1","generation":"prm-1","agent_id":"ag-1","agent_type":"implementer","status":null,"error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"@KEY@"}'

P_CLAUDE_STOP='{"session_id":"sess-2","prompt_id":"prm-2","transcript_path":"/t/b.jsonl","cwd":"/work","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false}'
W_CLAUDE_STOP='{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"Stop","session":"sess-2","generation":"prm-2","agent_id":null,"agent_type":null,"status":null,"error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"@KEY@"}'

P_CLAUDE_SF='{"session_id":"sess-3","prompt_id":"prm-3","transcript_path":"/t/e.jsonl","cwd":"/work","permission_mode":"default","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 secret-detail","last_assistant_message":"API Error: secret-msg"}'
W_CLAUDE_SF='{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"StopFailure","session":"sess-3","generation":"prm-3","agent_id":null,"agent_type":null,"status":"error","error":"rate_limit","duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"@KEY@"}'

P_CURSOR_SUB='{"conversation_id":"conv-1","generation_id":"gen-1","model":"test-model","hook_event_name":"subagentStop","cursor_version":"1.0.0","workspace_roots":["/w"],"user_email":"u@example.com","transcript_path":"/t/c.jsonl","subagent_type":"explore","status":"completed","task":"do the thing","description":"desc","summary":"sum","duration_ms":1234,"message_count":5,"tool_call_count":7,"loop_count":0,"modified_files":["a.txt","b.txt"],"agent_transcript_path":"/t/ca.jsonl"}'
W_CURSOR_SUB='{"ts":"2026-10-29T12:00:00Z","harness":"cursor","event":"subagentStop","session":"conv-1","generation":"gen-1","agent_id":null,"agent_type":"explore","status":"completed","error":null,"duration_ms":1234,"message_count":5,"tool_call_count":7,"loop_count":0,"model":"test-model","modified_files":2,"key":"@KEY@"}'

P_CURSOR_STOP='{"conversation_id":"conv-2","generation_id":"gen-2","model":"test-model","hook_event_name":"stop","cursor_version":"1.0.0","workspace_roots":["/w"],"user_email":"u@example.com","transcript_path":"/t/d.jsonl","status":"aborted","loop_count":1}'
W_CURSOR_STOP='{"ts":"2026-10-29T12:00:00Z","harness":"cursor","event":"stop","session":"conv-2","generation":"gen-2","agent_id":null,"agent_type":null,"status":"aborted","error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":1,"model":"test-model","modified_files":null,"key":"@KEY@"}'

cursor_stop() { # <conv> <gen> → a distinct, valid cursor stop payload
  printf '{"conversation_id":"%s","generation_id":"%s","model":"test-model","hook_event_name":"stop","cursor_version":"1.0.0","workspace_roots":["/w"],"user_email":"u@example.com","transcript_path":"/t/d.jsonl","status":"aborted","loop_count":1}' "$1" "$2"
}

cursor_with() { # <json-fragment> → a cursor subagentStop payload ending in the fragment
  printf '{"conversation_id":"conv-t","generation_id":"gen-t","hook_event_name":"subagentStop",%s}' "$1"
}

# --- 1. valid payloads: exact bytes, output contract ----------------------------------------------
expect_logged 'valid: Claude Code SubagentStop → one exact line' claude "$P_CLAUDE_SUB" "$W_CLAUDE_SUB"
expect_logged 'valid: Claude Code Stop → one exact line' claude "$P_CLAUDE_STOP" "$W_CLAUDE_STOP"
expect_logged 'valid: Claude Code StopFailure → status "error", the error enum, no free text' claude "$P_CLAUDE_SF" "$W_CLAUDE_SF"
expect_logged 'valid: Cursor subagentStop → one exact line' cursor "$P_CURSOR_SUB" "$W_CURSOR_SUB"
expect_logged 'valid: Cursor stop → one exact line' cursor "$P_CURSOR_STOP" "$W_CURSOR_STOP"

new_root
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
if cmp -s "$FX/out.bin" "$FX/want-obj" && [ "$RC" -eq 0 ]; then
  report PASS 'contract: logged cursor event prints exactly {} plus a newline, exit 0'
else
  report FAIL 'contract: logged cursor event prints exactly {} plus a newline' "rc=$RC out=[$(cat "$FX/out.bin")]"
fi
run_hook claude "$ROOT" "$P_CLAUDE_SUB"
if [ ! -s "$FX/out.bin" ] && [ "$RC" -eq 0 ]; then
  report PASS 'contract: logged claude event prints nothing, exit 0'
else
  report FAIL 'contract: logged claude event prints nothing' "rc=$RC out=[$(cat "$FX/out.bin")]"
fi
if [ "$(nlines "$(logf "$ROOT")")" = 2 ]; then
  report PASS 'both harnesses append to the one events.jsonl (2 lines)'
else
  report FAIL 'both harnesses append to the one events.jsonl' "lines=$(nlines "$(logf "$ROOT")")"
fi

# known answer for the key: SHA-256 of {"hook_event_name":"stop"} starts with 313c615162dda827
expect_logged 'key: known SHA-256 prefix of the raw bytes' cursor '{"hook_event_name":"stop"}' \
  '{"ts":"2026-10-29T12:00:00Z","harness":"cursor","event":"stop","session":null,"generation":null,"agent_id":null,"agent_type":null,"status":null,"error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"313c615162dda827"}'

# trailing newline is part of the raw bytes: the same JSON plus "\n" has a different key
new_root
run_hook cursor "$ROOT" "$P_CURSOR_STOP
"
want="${W_CURSOR_STOP/@KEY@/$(exp_key "$P_CURSOR_STOP
")}"
if file_is "$(logf "$ROOT")" "$want"; then
  report PASS 'key: hashes the raw stdin bytes including a trailing newline'
else
  report FAIL 'key: hashes the raw stdin bytes including a trailing newline' "log=[$(cat "$(logf "$ROOT")" 2>/dev/null)]"
fi

# the default timestamp (HOOK_LOG_NOW unset) is UTC YYYY-MM-DDTHH:MM:SSZ
new_root
EXTRA_ENV='HOOK_LOG_NOW='
run_hook cursor "$ROOT" "$P_CURSOR_STOP"
if grep -Eq '^\{"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z","harness":"cursor"' "$(logf "$ROOT")" 2>/dev/null; then
  report PASS 'ts: without HOOK_LOG_NOW the ts is UTC YYYY-MM-DDTHH:MM:SSZ'
else
  report FAIL 'ts: without HOOK_LOG_NOW the ts is UTC YYYY-MM-DDTHH:MM:SSZ' "log=[$(cat "$(logf "$ROOT")" 2>/dev/null)]"
fi

# the other awk flavors on this machine produce the same bytes
for flavor in gawk mawk nawk original-awk; do
  fp="$(command -v "$flavor" 2>/dev/null)" || fp=""
  if [ -z "$fp" ]; then
    report SKIP "awk flavor $flavor: same bytes" "not installed"
    continue
  fi
  shim="$FX/awk-$flavor"
  mkdir -p "$shim"
  ln -sf "$fp" "$shim/awk"
  ok=1
  for pair in "claude|$P_CLAUDE_SUB|$W_CLAUDE_SUB" "claude|$P_CLAUDE_SF|$W_CLAUDE_SF" "cursor|$P_CURSOR_SUB|$W_CURSOR_SUB"; do
    h="${pair%%|*}"
    rest="${pair#*|}"
    p="${rest%%|*}"
    tpl="${rest#*|}"
    new_root
    EXTRA_ENV="PATH=$shim:$PATH"
    run_hook "$h" "$ROOT" "$p"
    contract_ok "$h" && file_is "$(logf "$ROOT")" "${tpl/@KEY@/$(exp_key "$p")}" || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    report PASS "awk flavor $flavor: same bytes for a claude, a claude StopFailure and a cursor payload"
  else
    report FAIL "awk flavor $flavor: same bytes for a claude, a claude StopFailure and a cursor payload"
  fi
done

# a multi-line (pretty-printed, CRLF) payload gives the same fields as the compact one
pretty="$(printf '{\r\n  "conversation_id": "conv-2",\r\n  "generation_id": "gen-2",\r\n  "model": "test-model",\r\n  "hook_event_name": "stop",\r\n  "workspace_roots": [\r\n    "/w"\r\n  ],\r\n  "status": "aborted",\r\n  "loop_count": 1\r\n}\r\n')"
new_root
run_hook cursor "$ROOT" "$pretty"
want='{"ts":"2026-10-29T12:00:00Z","harness":"cursor","event":"stop","session":"conv-2","generation":"gen-2","agent_id":null,"agent_type":null,"status":"aborted","error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":1,"model":"test-model","modified_files":null,"key":"'"$(exp_key "$pretty")"'"}'
if contract_ok cursor && file_is "$(logf "$ROOT")" "$want"; then
  report PASS 'valid: pretty-printed multi-line CRLF payload → same fields'
else
  report FAIL 'valid: pretty-printed multi-line CRLF payload → same fields' "log=[$(cat "$(logf "$ROOT")" 2>/dev/null)]"
fi

# a large payload (300 KB task text full of escapes) and a 5000-element modified_files array
big="$(awk 'BEGIN { for (i = 0; i < 100000; i++) printf "a\\\"\\n" }')"
bigp='{"conversation_id":"big","generation_id":"g","hook_event_name":"subagentStop","task":"'"$big"'","subagent_type":"explore","status":"completed"}'
new_root
run_hook cursor "$ROOT" "$bigp"
if contract_ok cursor && [ "$(fld "$(logf "$ROOT")" status error)" = '"completed"' ] \
   && [ "$(fld "$(logf "$ROOT")" agent_type status)" = '"explore"' ]; then
  report PASS 'large: a 500 KB task string full of escapes does not hide later keys'
else
  report FAIL 'large: a 500 KB task string full of escapes' "log=[$(head -c 300 "$(logf "$ROOT")" 2>/dev/null)]"
fi
mf="$(awk 'BEGIN { for (i = 0; i < 5000; i++) printf "%s\"f%d.txt\"", (i ? "," : ""), i }')"
new_root
run_hook cursor "$ROOT" "$(cursor_with '"modified_files":['"$mf"']')"
if contract_ok cursor && [ "$(fld "$(logf "$ROOT")" modified_files key)" = 5000 ]; then
  report PASS 'large: a 5000-element modified_files array counts 5000'
else
  report FAIL 'large: a 5000-element modified_files array counts 5000' "got=[$(fld "$(logf "$ROOT")" modified_files key)]"
fi

# --- 2. skip rules ---------------------------------------------------------------------------------
# rule 1: AGENT_KIT_HOOK_LOG=0 (control: unset, 1 and any other value log)
for h in claude cursor; do
  if [ "$h" = claude ]; then p="$P_CLAUDE_SUB"; else p="$P_CURSOR_SUB"; fi
  new_root
  EXTRA_ENV='AGENT_KIT_HOOK_LOG=0'
  run_hook "$h" "$ROOT" "$p"
  if contract_ok "$h" && [ ! -e "$ROOT/_memory" ]; then
    report PASS "skip 1: AGENT_KIT_HOOK_LOG=0 writes nothing ($h)"
  else
    report FAIL "skip 1: AGENT_KIT_HOOK_LOG=0 writes nothing ($h)" "rc=$RC err=[$ERR]"
  fi
done
for v in 1 yes false 00; do
  new_root
  EXTRA_ENV="AGENT_KIT_HOOK_LOG=$v"
  run_hook cursor "$ROOT" "$P_CURSOR_SUB"
  if contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
    report PASS "skip 1 control: AGENT_KIT_HOOK_LOG=$v keeps logging on"
  else
    report FAIL "skip 1 control: AGENT_KIT_HOOK_LOG=$v keeps logging on" "rc=$RC"
  fi
done

# rule 2: empty stdin, or stdin without both { and }
for h in claude cursor; do
  expect_skip "skip 2: empty stdin ($h)" "$h" ''
  expect_skip "skip 2: whitespace-only stdin ($h)" "$h" '   
'
  expect_skip "skip 2: not JSON ($h)" "$h" 'hello'
  expect_skip "skip 2: a left brace only ($h)" "$h" '{"hook_event_name":"stop"'
  expect_skip "skip 2: a right brace only ($h)" "$h" '"hook_event_name":"stop"}'
  expect_skip "skip 2: braces in the wrong order ($h)" "$h" '}{'
  expect_skip "skip 2: both braces but no top-level object ($h)" "$h" '[{}]'
done
# a payload whose first non-whitespace character is not { is never read, a top-level array included
expect_skip 'skip 2: a top-level array holding a valid claude payload is not logged as its inner object' claude "[$P_CLAUDE_STOP]"
expect_skip 'skip 2: a top-level array holding a valid cursor payload is not logged as its inner object' cursor "[$P_CURSOR_STOP]"
expect_skip 'skip 2: a whitespace-led top-level array is not logged (claude)' claude "
  [ $P_CLAUDE_STOP ]
"
expect_skip 'skip 2: text before the left brace is not logged (claude)' claude "x$P_CLAUDE_STOP"
expect_skip 'skip 2: text before the left brace is not logged (cursor)' cursor "x$P_CURSOR_STOP"
expect_skip 'skip 2: a string value before the object is not logged (claude)' claude "\"s\" $P_CLAUDE_STOP"
expect_logged 'skip 2 control: leading spaces, tabs, CR and newlines before the left brace still log (claude)' claude \
  "$(printf ' \t\r\n  \n')$P_CLAUDE_STOP" "$W_CLAUDE_STOP"
expect_logged 'skip 2 control: leading whitespace before the left brace still logs (cursor)' cursor \
  "  $P_CURSOR_STOP" "$W_CURSOR_STOP"

# rule 3: a Cursor caller on the claude path (control: cursor logs with the same env / payload)
new_root
EXTRA_ENV='CURSOR_PROJECT_DIR=/some/project'
run_hook claude "$ROOT" "$P_CLAUDE_SUB"
if contract_ok claude && [ ! -e "$ROOT/_memory" ]; then
  report PASS 'skip 3: claude hook with CURSOR_PROJECT_DIR set writes nothing'
else
  report FAIL 'skip 3: claude hook with CURSOR_PROJECT_DIR set writes nothing' "rc=$RC"
fi
new_root
EXTRA_ENV='CURSOR_PROJECT_DIR=/some/project'
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
if contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'skip 3 control: cursor hook still logs with CURSOR_PROJECT_DIR set'
else
  report FAIL 'skip 3 control: cursor hook still logs with CURSOR_PROJECT_DIR set' "rc=$RC"
fi
claude_cv="${P_CLAUDE_SUB%\}},\"cursor_version\":\"1.0.0\"}"
case "$claude_cv" in
  *'"agent_type":"implementer"'*',"cursor_version":"1.0.0"}') report PASS 'fixture: claude payload with a cursor_version key is built' ;;
  *) report FAIL 'fixture: claude payload with a cursor_version key is built' "$claude_cv" ;;
esac
expect_skip 'skip 3: claude hook with "cursor_version" in the payload writes nothing' claude "$claude_cv"
expect_logged 'skip 3 control: the same claude payload without cursor_version logs' claude "$P_CLAUDE_SUB" "$W_CLAUDE_SUB"

# rule 4: hook_event_name outside the harness list
expect_skip 'skip 4: claude hook with PreToolUse' claude \
  "${P_CLAUDE_SUB/\"SubagentStop\"/\"PreToolUse\"}"
expect_skip 'skip 4: claude hook with a lowercase cursor event name' claude \
  "${P_CLAUDE_STOP/\"Stop\"/\"stop\"}"
expect_skip 'skip 4: claude hook with SessionStart' claude \
  "${P_CLAUDE_STOP/\"Stop\"/\"SessionStart\"}"
expect_skip 'skip 4: cursor hook with a claude event name (Stop)' cursor \
  "${P_CURSOR_STOP/\"stop\"/\"Stop\"}"
expect_skip 'skip 4: cursor hook with the claude StopFailure event name' cursor \
  "${P_CURSOR_STOP/\"stop\"/\"StopFailure\"}"
expect_skip 'skip 4: claude hook with a lowercase stopFailure' claude \
  "${P_CLAUDE_SF/\"StopFailure\"/\"stopFailure\"}"
expect_skip 'skip 4: claude hook with a longer StopFailureX' claude \
  "${P_CLAUDE_SF/\"StopFailure\"/\"StopFailureX\"}"
expect_skip 'skip 4: cursor hook with preToolUse' cursor \
  "${P_CURSOR_STOP/\"stop\"/\"preToolUse\"}"
expect_skip 'skip 4: cursor hook with a null event name' cursor \
  "${P_CURSOR_STOP/\"stop\"/null}"
expect_skip 'skip 4: cursor hook without hook_event_name' cursor \
  '{"conversation_id":"c","generation_id":"g","status":"completed"}'
expect_skip 'skip 4: an event name only inside a nested value does not count' cursor \
  '{"conversation_id":"c","extra":{"hook_event_name":"stop"}}'
expect_skip 'skip 4: an escaped event name inside a string does not count' cursor \
  '{"conversation_id":"c","task":"{\"hook_event_name\":\"stop\"}"}'

# rule 5: any write failure
new_root
mkdir -p "$ROOT/$LOGREL"
chmod 555 "$ROOT/$LOGREL"
if [ "$(id -u)" = 0 ]; then
  report SKIP 'skip 5: read-only hooks dir writes nothing' 'running as root (permissions are not enforced)'
else
  run_hook cursor "$ROOT" "$P_CURSOR_SUB"
  rc_c="$RC"; ok_c=1; contract_ok cursor || ok_c=0
  run_hook claude "$ROOT" "$P_CLAUDE_SUB"
  ok_l=1; contract_ok claude || ok_l=0
  chmod 755 "$ROOT/$LOGREL"
  if [ "$ok_c" -eq 1 ] && [ "$ok_l" -eq 1 ] && [ -z "$(find "$ROOT/$LOGREL" -type f 2>/dev/null)" ]; then
    report PASS 'skip 5: read-only hooks dir writes nothing, contract holds (cursor and claude)'
  else
    report FAIL 'skip 5: read-only hooks dir writes nothing' "rc_c=$rc_c ok_c=$ok_c ok_l=$ok_l files=$(find "$ROOT/$LOGREL" -type f 2>/dev/null)"
  fi
  run_hook cursor "$ROOT" "$P_CURSOR_SUB"
  if [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
    report PASS 'skip 5 control: the same root logs once the dir is writable'
  else
    report FAIL 'skip 5 control: the same root logs once the dir is writable'
  fi
fi
new_root
printf 'not a directory\n' > "$ROOT/_memory"
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
if contract_ok cursor && [ -f "$ROOT/_memory" ] && [ "$(cat "$ROOT/_memory")" = 'not a directory' ]; then
  report PASS 'skip 5: _memory is a file (mkdir fails) → nothing written, contract holds'
else
  report FAIL 'skip 5: _memory is a file (mkdir fails)' "rc=$RC err=[$ERR] out=[$(cat "$FX/out.bin")]"
fi

# no tool at all on PATH (only builtins): still {} / nothing, exit 0, nothing written
mkdir -p "$FX/emptybin"
for h in cursor claude; do
  if [ "$h" = claude ]; then p="$P_CLAUDE_SUB"; else p="$P_CURSOR_SUB"; fi
  new_root
  EXTRA_ENV="PATH=$FX/emptybin"
  run_hook "$h" "$ROOT" "$p"
  if contract_ok "$h" && [ ! -e "$ROOT/_memory" ]; then
    report PASS "fail open: no tools on PATH → contract holds, nothing written ($h)"
  else
    report FAIL "fail open: no tools on PATH ($h)" "rc=$RC err=[$ERR] out=[$(cat "$FX/out.bin")]"
  fi
done

# an unreadable / missing root fails open too
new_root
run_hook cursor "$ROOT/does-not-exist" "$P_CURSOR_SUB"
if contract_ok cursor && [ ! -e "$ROOT/does-not-exist" ]; then
  report PASS 'fail open: a missing --root dir → {} and exit 0, nothing created'
else
  report FAIL 'fail open: a missing --root dir' "rc=$RC err=[$ERR]"
fi

# --- 3. never-logged markers ---------------------------------------------------------------------
NEVER='task description summary last_assistant_message error_details transcript_path agent_transcript_path cwd workspace_roots user_email permission_mode background_tasks session_crons'
marker_value() { # <field> → a JSON value holding a unique marker for that field
  case "$1" in
    workspace_roots) printf '["HLMARK_%s_9c41"]' "$1" ;;
    background_tasks) printf '[{"agent_id":"HLMARK_%s_9c41","status":"error"}]' "$1" ;;
    session_crons) printf '[{"id":"HLMARK_%s_9c41"}]' "$1" ;;
    *) printf '"HLMARK_%s_9c41"' "$1" ;;
  esac
}
marker_fields() {
  local f out=""
  for f in $NEVER; do out="${out},\"${f}\":$(marker_value "$f")"; done
  printf '%s' "$out"
}
mp_cursor='{"conversation_id":"conv-m","generation_id":"gen-m","model":"test-model","hook_event_name":"subagentStop","cursor_version":"1.0.0","subagent_type":"explore","status":"completed"'"$(marker_fields)"'}'
mp_claude='{"session_id":"sess-m","prompt_id":"prm-m","hook_event_name":"SubagentStop","agent_id":"ag-m","agent_type":"implementer"'"$(marker_fields)"'}'
mp_claude_sf='{"session_id":"sess-m","prompt_id":"prm-m","hook_event_name":"StopFailure","error":"server_error"'"$(marker_fields)"'}'
for h in cursor claude claude-sf; do
  case "$h" in
    cursor) p="$mp_cursor"; hh=cursor ;;
    claude) p="$mp_claude"; hh=claude ;;
    *) p="$mp_claude_sf"; hh=claude ;;
  esac
  new_root
  run_hook "$hh" "$ROOT" "$p"
  lf="$(logf "$ROOT")"
  if ! contract_ok "$hh" || [ "$(nlines "$lf")" != 1 ]; then
    report FAIL "never logged ($h): the marker payload is logged at all" "rc=$RC lines=$(nlines "$lf")"
    continue
  fi
  report PASS "never logged ($h): the marker payload itself is logged (probe is not vacuous)"
  if [ "$h" = claude-sf ] && ! grep -qF '"status":"error","error":"server_error"' "$lf"; then
    report FAIL "never logged ($h): the StopFailure line carries its status and error" "log=[$(cat "$lf")]"
  fi
  for f in $NEVER; do
    mk="HLMARK_${f}_9c41"
    if ! printf '%s' "$p" | grep -qF "$mk"; then
      report FAIL "never logged ($h): $f" "marker not in the input payload"
    elif grep -qF "$mk" "$lf"; then
      report FAIL "never logged ($h): $f" "marker reached the log: $(cat "$lf")"
    else
      report PASS "never logged ($h): $f"
    fi
  done
done

# --- 4. top-level keys only ----------------------------------------------------------------------
# escaped-key decoy in a string that comes BEFORE the real key
new_root
run_hook cursor "$ROOT" '{"conversation_id":"c","generation_id":"g","hook_event_name":"subagentStop","task":"say \"status\":\"error\" and \"model\":\"evil\"","status":"completed","model":"real-model"}'
lf="$(logf "$ROOT")"
if [ "$(fld "$lf" status error)" = '"completed"' ] && [ "$(fld "$lf" model modified_files)" = '"real-model"' ]; then
  report PASS 'decoy: an escaped "status" / "model" inside a task string is never read'
else
  report FAIL 'decoy: an escaped key inside a string' "status=$(fld "$lf" status error) model=$(fld "$lf" model modified_files)"
fi
new_root
run_hook cursor "$ROOT" '{"conversation_id":"c","generation_id":"g","hook_event_name":"subagentStop","task":"say \"status\":\"error\"","description":"{\"status\":\"error\"}"}'
lf="$(logf "$ROOT")"
if [ "$(fld "$lf" status error)" = null ]; then
  report PASS 'decoy: an escaped "status" with no real status stays null'
else
  report FAIL 'decoy: an escaped "status" with no real status stays null' "status=$(fld "$lf" status error)"
fi

# nested decoy: background_tasks entries before the real top-level keys
new_root
run_hook claude "$ROOT" '{"session_id":"s","prompt_id":"p","hook_event_name":"SubagentStop","background_tasks":[{"agent_id":"x","status":"error"}],"agent_id":"real","agent_type":"implementer"}'
lf="$(logf "$ROOT")"
if contract_ok claude && [ "$(fld "$lf" agent_id agent_type)" = '"real"' ] && [ "$(fld "$lf" status error)" = null ]; then
  report PASS 'nested decoy: background_tasks agent_id/status never win; claude status stays null'
else
  report FAIL 'nested decoy: background_tasks' "agent_id=$(fld "$lf" agent_id agent_type) status=$(fld "$lf" status error)"
fi
new_root
run_hook claude "$ROOT" '{"session_id":"s","hook_event_name":"Stop","background_tasks":[{"agent_id":"x","status":"error"}],"session_crons":[{"agent_id":"y"}]}'
lf="$(logf "$ROOT")"
if [ "$(fld "$lf" agent_id agent_type)" = null ]; then
  report PASS 'nested decoy: no top-level agent_id → null even with nested ones'
else
  report FAIL 'nested decoy: no top-level agent_id → null' "agent_id=$(fld "$lf" agent_id agent_type)"
fi
new_root
run_hook cursor "$ROOT" '{"conversation_id":"c","hook_event_name":"subagentStop","workspace_roots":[{"status":"error","model":"nested"}],"extra":{"status":"error","loop_count":9},"status":"completed","model":"real-model","loop_count":2}'
lf="$(logf "$ROOT")"
if [ "$(fld "$lf" status error)" = '"completed"' ] && [ "$(fld "$lf" model modified_files)" = '"real-model"' ] \
   && [ "$(fld "$lf" loop_count model)" = 2 ]; then
  report PASS 'nested decoy: cursor status / model / loop_count inside nested objects are never read'
else
  report FAIL 'nested decoy: cursor nested keys' "status=$(fld "$lf" status error) model=$(fld "$lf" model modified_files) loop=$(fld "$lf" loop_count model)"
fi

# --- 5. value types --------------------------------------------------------------------------------
type_case() { # <name> <fragment> <field> <next> <want-token>
  new_root
  run_hook cursor "$ROOT" "$(cursor_with "$2")"
  local got
  got="$(fld "$(logf "$ROOT")" "$3" "$4")"
  if contract_ok cursor && [ "$got" = "$5" ]; then
    report PASS "type: $1"
  else
    report FAIL "type: $1" "got=[$got] want=[$5] rc=$RC"
  fi
}
type_case 'duration_ms 1234 → 1234' '"duration_ms":1234' duration_ms message_count 1234
type_case 'duration_ms 0 → 0' '"duration_ms":0' duration_ms message_count 0
type_case 'duration_ms "abc" (string) → null' '"duration_ms":"abc"' duration_ms message_count null
type_case 'duration_ms "12" (digit string) → null' '"duration_ms":"12"' duration_ms message_count null
type_case 'duration_ms -5 → null' '"duration_ms":-5' duration_ms message_count null
type_case 'duration_ms 1.5 → null' '"duration_ms":1.5' duration_ms message_count null
type_case 'duration_ms 1e3 → null' '"duration_ms":1e3' duration_ms message_count null
type_case 'duration_ms true → null' '"duration_ms":true' duration_ms message_count null
type_case 'duration_ms null → null' '"duration_ms":null' duration_ms message_count null
type_case 'duration_ms nested object → null' '"duration_ms":{"a":1}' duration_ms message_count null
type_case 'message_count / tool_call_count / loop_count numbers' '"message_count":5,"tool_call_count":7,"loop_count":3' tool_call_count loop_count 7
type_case 'loop_count 3 → 3' '"message_count":5,"tool_call_count":7,"loop_count":3' loop_count model 3
type_case 'status number → null' '"status":5' status error null
type_case 'modified_files [] → 0' '"modified_files":[]' modified_files key 0
type_case 'modified_files one element → 1' '"modified_files":["a.txt"]' modified_files key 1
type_case 'modified_files three elements → 3' '"modified_files":["a.txt","b.txt","c.txt"]' modified_files key 3
type_case 'modified_files strings with commas and brackets → count of elements' '"modified_files":["a,b","c]d","e\"f,g"]' modified_files key 3
type_case 'modified_files nested objects / arrays → count of top-level elements' '"modified_files":[{"p":"a","q":[1,2]},[3,4],"x"]' modified_files key 3
type_case 'modified_files null → null' '"modified_files":null' modified_files key null
type_case 'modified_files string → null' '"modified_files":"a.txt"' modified_files key null
type_case 'modified_files object → null' '"modified_files":{"a":1}' modified_files key null
type_case 'modified_files absent → null' '"loop_count":1' modified_files key null
type_case 'model null → null' '"model":null' model modified_files null
type_case 'model number → null' '"model":5' model modified_files null
type_case 'model empty string is copied as ""' '"model":""' model modified_files '""'
type_case 'model with \" and \u00e9 copied byte for byte' '"model":"a\"b\u00e9c"' model modified_files '"a\"b\u00e9c"'
type_case 'model with an escaped backslash before the closing quote' '"model":"a\\","status":"completed"' model modified_files '"a\\"'
type_case 'raw UTF-8 bytes in a string are copied byte for byte' "\"model\":\"caf$(printf '\303\251')\"" model modified_files "\"caf$(printf '\303\251')\""
type_case 'agent_type from subagent_type with an escape' '"subagent_type":"x\ty"' agent_type status '"x\ty"'
type_case 'duplicate top-level key: the first occurrence wins' '"status":"completed","status":"error"' status error '"completed"'

# --- 5b. Claude Code StopFailure: status "error" and the error field --------------------------------
# sf_case <name> <fragment> <want-error-token>: a StopFailure payload with <fragment> (leading comma)
# logs status "error" and the wanted error token.
sf_case() {
  local name="$1" frag="$2" want="$3" got st
  new_root
  run_hook claude "$ROOT" '{"session_id":"s","hook_event_name":"StopFailure"'"$frag"'}'
  got="$(fld "$(logf "$ROOT")" error duration_ms)"
  st="$(fld "$(logf "$ROOT")" status error)"
  if contract_ok claude && [ "$(nlines "$(logf "$ROOT")")" = 1 ] && [ "$got" = "$want" ] && [ "$st" = '"error"' ]; then
    report PASS "StopFailure: $name"
  else
    report FAIL "StopFailure: $name" "got error=[$got] status=[$st] want error=[$want] rc=$RC log=[$(cat "$(logf "$ROOT")" 2>/dev/null)]"
  fi
}
for v in rate_limit overloaded authentication_failed oauth_org_not_allowed account_on_hold billing_error \
         invalid_request model_not_found server_error max_output_tokens cloud_credential_error unknown; do
  sf_case "the documented error $v is logged as given" ",\"error\":\"$v\"" "\"$v\""
done
sf_case 'a snake_case value outside the documented list is logged as given' ',"error":"brand_new_kind"' '"brand_new_kind"'
sf_case 'free text with spaces → null' ',"error":"rate limit exceeded"' null
sf_case 'free text with a colon and digits → null' ',"error":"429: secret-detail"' null
sf_case 'a hyphenated value → null' ',"error":"rate-limit"' null
sf_case 'an upper-case value → null' ',"error":"RATE_LIMIT"' null
sf_case 'a camelCase value → null' ',"error":"rateLimit"' null
sf_case 'an empty string → null' ',"error":""' null
sf_case 'a unicode escape inside the value → null' ',"error":"rate\u005flimit"' null
sf_case 'an escaped quote inside the value → null' ',"error":"a\"b"' null
sf_case 'a path-like value → null' ',"error":"/etc/passwd"' null
sf_case 'a number → null' ',"error":5' null
sf_case 'true → null' ',"error":true' null
sf_case 'null → null' ',"error":null' null
sf_case 'an object → null' ',"error":{"x":"rate_limit"}' null
sf_case 'an array → null' ',"error":["rate_limit"]' null
sf_case 'no error key → null' '' null
sf_case 'error_details never stands in for error' ',"error_details":"rate_limit"' null
sf_case 'the first duplicate error wins' ',"error":"overloaded","error":"rate_limit"' '"overloaded"'
sf_case 'a nested error before the real one is never read' ',"background_tasks":[{"error":"overloaded"}],"error":"billing_error"' '"billing_error"'
sf_case 'a nested error alone is never read' ',"background_tasks":[{"error":"overloaded"}]' null
sf_case 'an escaped error key inside a string is never read' ',"last_assistant_message":"{\"error\":\"overloaded\"}"' null
sf_case 'a status in the payload never overrides the literal "error"' ',"status":"completed","error":"unknown"' '"unknown"'

# the error field is null for every event but StopFailure (claude and cursor alike)
ev_err_case() { # <name> <harness> <payload-with-error-key>
  local name="$1" h="$2" p="$3" lf
  new_root
  run_hook "$h" "$ROOT" "$p"
  lf="$(logf "$ROOT")"
  if contract_ok "$h" && [ "$(nlines "$lf")" = 1 ] && [ "$(fld "$lf" error duration_ms)" = null ] && ! grep -qF 'rate_limit' "$lf"; then
    report PASS "error field: $name"
  else
    report FAIL "error field: $name" "log=[$(cat "$lf" 2>/dev/null)]"
  fi
}
ev_err_case 'a Claude Code Stop with an error key logs error null' claude "${P_CLAUDE_STOP%\}},\"error\":\"rate_limit\"}"
ev_err_case 'a Claude Code SubagentStop with an error key logs error null' claude "${P_CLAUDE_SUB%\}},\"error\":\"rate_limit\"}"
ev_err_case 'a Cursor stop with an error key logs error null' cursor "${P_CURSOR_STOP%\}},\"error\":\"rate_limit\"}"
ev_err_case 'a Cursor subagentStop with an error key logs error null' cursor "${P_CURSOR_SUB%\}},\"error\":\"rate_limit\"}"
new_root
run_hook claude "$ROOT" "${P_CLAUDE_SF%\}},\"status\":\"completed\",\"model\":\"m\",\"duration_ms\":5}"
if contract_ok claude && [ "$(fld "$(logf "$ROOT")" status error)" = '"error"' ] && [ "$(fld "$(logf "$ROOT")" duration_ms message_count)" = null ] \
   && [ "$(fld "$(logf "$ROOT")" model modified_files)" = null ]; then
  report PASS 'StopFailure: the Cursor-only fields (status, duration_ms, model) of a claude payload stay unread'
else
  report FAIL 'StopFailure: the Cursor-only fields stay unread' "log=[$(cat "$(logf "$ROOT")" 2>/dev/null)]"
fi

# the acceptance smoke: StopFailure through the hook, no Cursor caller → status error, error enum, no free text
d="$(mktemp -d "$FIXTURE_TMPDIR/sfsmoke.XXXXXX")"
assert_fixture_root "$d" || exit 1
printf '%s' '{"session_id":"s1","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 secret-detail","last_assistant_message":"API Error: secret-msg"}' \
  | env -u CURSOR_PROJECT_DIR "$BASH" "$HOOK" hook claude --root "$d" >"$FX/out.bin" 2>/dev/null
sfl="$(cat "$d/$LOGREL/events.jsonl" 2>/dev/null)"
if [ ! -s "$FX/out.bin" ] && case "$sfl" in *'"status":"error","error":"rate_limit"'*) true ;; *) false ;; esac \
   && ! printf '%s' "$sfl" | grep -qE 'secret-detail|secret-msg'; then
  report PASS 'smoke: a StopFailure payload logs "status":"error","error":"rate_limit" and neither free-text field'
else
  report FAIL 'smoke: a StopFailure payload' "line=[$sfl] out=[$(cat "$FX/out.bin")]"
fi

# --- 6. idempotency --------------------------------------------------------------------------------
new_root
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
if contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'idempotent: the same payload twice gives one line'
else
  report FAIL 'idempotent: the same payload twice gives one line' "lines=$(nlines "$(logf "$ROOT")")"
fi
run_hook cursor "$ROOT" "$P_CURSOR_STOP"
if [ "$(nlines "$(logf "$ROOT")")" = 2 ]; then
  report PASS 'idempotent control: a different payload still appends (2 lines)'
else
  report FAIL 'idempotent control: a different payload still appends' "lines=$(nlines "$(logf "$ROOT")")"
fi
new_root
mkdir -p "$ROOT/$LOGREL"
printf '{"ts":"x","key":"%s"}\n' "$(exp_key "$P_CURSOR_SUB")" > "$(log1f "$ROOT")"
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
if contract_ok cursor && [ ! -e "$(logf "$ROOT")" ]; then
  report PASS 'idempotent: a key present only in events.1.jsonl is skipped'
else
  report FAIL 'idempotent: a key present only in events.1.jsonl is skipped' "lines=$(nlines "$(logf "$ROOT")")"
fi
run_hook cursor "$ROOT" "$P_CURSOR_STOP"
if [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'idempotent control: another payload next to that events.1.jsonl logs'
else
  report FAIL 'idempotent control: another payload next to that events.1.jsonl logs'
fi
new_root
run_hook claude "$ROOT" "$P_CLAUDE_SUB"
run_hook claude "$ROOT" "$P_CLAUDE_SUB"
if contract_ok claude && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'idempotent: the same claude payload twice gives one line'
else
  report FAIL 'idempotent: the same claude payload twice gives one line'
fi

# --- 7. rotation ------------------------------------------------------------------------------------
pa="$(cursor_stop rot-a g1)"; pb="$(cursor_stop rot-b g2)"; pc="$(cursor_stop rot-c g3)"
new_root
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=200'; run_hook cursor "$ROOT" "$pa"
la="$(cat "$(logf "$ROOT")")"
size_a="$(wc -c < "$(logf "$ROOT")" | sed 's/ //g')"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=200'; run_hook cursor "$ROOT" "$pb"
lb="$(tail -n 1 "$(logf "$ROOT")")"
if [ "$size_a" -ge 200 ] && contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ] \
   && file_is "$(log1f "$ROOT")" "$la" && file_is "$(logf "$ROOT")" "$lb" && [ "$la" != "$lb" ]; then
  report PASS 'rotate: at a 200-byte cap events.jsonl moves to events.1.jsonl and a fresh one-line events.jsonl starts'
else
  report FAIL 'rotate: first rotation' "size_a=$size_a main=$(nlines "$(logf "$ROOT")") old=$(nlines "$(log1f "$ROOT")")"
fi
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=200'; run_hook cursor "$ROOT" "$pc"
lc="$(cat "$(logf "$ROOT")")"
if file_is "$(log1f "$ROOT")" "$lb" && [ "$(nlines "$(logf "$ROOT")")" = 1 ] && [ "$lc" != "$lb" ] \
   && ! grep -qF 'rot-a' "$(log1f "$ROOT")" "$(logf "$ROOT")"; then
  report PASS 'rotate: a second rotation replaces the older events.1.jsonl'
else
  report FAIL 'rotate: a second rotation replaces the older events.1.jsonl'
fi
if [ ! -e "$ROOT/$LOGREL/.rotate.lock" ]; then
  report PASS 'rotate: the lock directory is removed afterwards'
else
  report FAIL 'rotate: the lock directory is removed afterwards'
fi

new_root
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=abc'; run_hook cursor "$ROOT" "$pa"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=abc'; run_hook cursor "$ROOT" "$pb"
if [ "$(nlines "$(logf "$ROOT")")" = 2 ] && [ ! -e "$(log1f "$ROOT")" ]; then
  report PASS 'rotate: a non-numeric cap means the 5 MB default (no rotation at 2 small lines)'
else
  report FAIL 'rotate: a non-numeric cap means the default'
fi
new_root
run_hook cursor "$ROOT" "$pa"
run_hook cursor "$ROOT" "$pb"
if [ "$(nlines "$(logf "$ROOT")")" = 2 ] && [ ! -e "$(log1f "$ROOT")" ]; then
  report PASS 'rotate: an unset cap means the default (no rotation)'
else
  report FAIL 'rotate: an unset cap means the default'
fi
new_root
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=100000'; run_hook cursor "$ROOT" "$pa"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=100000'; run_hook cursor "$ROOT" "$pb"
if [ "$(nlines "$(logf "$ROOT")")" = 2 ] && [ ! -e "$(log1f "$ROOT")" ]; then
  report PASS 'rotate control: a file under the cap is not rotated'
else
  report FAIL 'rotate control: a file under the cap is not rotated'
fi

# rotation lock: fresh lock → no rotation but still appended; stale lock → removed, then rotates
new_root
mkdir -p "$ROOT/$LOGREL"
head_line="$(printf '%0300d' 0)"
printf '%s\n' "$head_line" > "$(logf "$ROOT")"
mkdir "$ROOT/$LOGREL/.rotate.lock"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=200'; run_hook cursor "$ROOT" "$pa"
if contract_ok cursor && [ ! -e "$(log1f "$ROOT")" ] && [ "$(nlines "$(logf "$ROOT")")" = 2 ] \
   && [ -d "$ROOT/$LOGREL/.rotate.lock" ] && [ "$(head -n 1 "$(logf "$ROOT")")" = "$head_line" ]; then
  report PASS 'lock: a fresh .rotate.lock → no rotation, the line is still appended, the lock is untouched'
else
  report FAIL 'lock: a fresh .rotate.lock' "main=$(nlines "$(logf "$ROOT")") old=$(nlines "$(log1f "$ROOT")") lock=$([ -d "$ROOT/$LOGREL/.rotate.lock" ] && echo yes || echo no)"
fi
stamp="$(date -d '11 minutes ago' +%Y%m%d%H%M 2>/dev/null || date -v-11M +%Y%m%d%H%M 2>/dev/null)"
if [ -z "$stamp" ]; then
  report SKIP 'lock: a stale .rotate.lock (11 minutes old) is removed and rotation happens' 'no date -d / -v'
else
  new_root
  mkdir -p "$ROOT/$LOGREL"
  printf '%s\n' "$head_line" > "$(logf "$ROOT")"
  mkdir "$ROOT/$LOGREL/.rotate.lock"
  touch -t "$stamp" "$ROOT/$LOGREL/.rotate.lock"
  EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=200'; run_hook cursor "$ROOT" "$pa"
  if contract_ok cursor && file_is "$(log1f "$ROOT")" "$head_line" && [ "$(nlines "$(logf "$ROOT")")" = 1 ] \
     && [ ! -e "$ROOT/$LOGREL/.rotate.lock" ]; then
    report PASS 'lock: a stale .rotate.lock (11 minutes old) is removed and rotation happens'
  else
    report FAIL 'lock: a stale .rotate.lock' "main=$(nlines "$(logf "$ROOT")") old=$(nlines "$(log1f "$ROOT")") lock=$([ -d "$ROOT/$LOGREL/.rotate.lock" ] && echo yes || echo no)"
  fi
fi

# a duplicate arriving when the file is over the cap changes nothing (no rotation)
new_root
run_hook cursor "$ROOT" "$pa"
cp "$(logf "$ROOT")" "$FX/before-main"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=50'; run_hook cursor "$ROOT" "$pa"
if contract_ok cursor && cmp -s "$FX/before-main" "$(logf "$ROOT")" && [ ! -e "$(log1f "$ROOT")" ] \
   && [ ! -e "$ROOT/$LOGREL/.rotate.lock" ]; then
  report PASS 'duplicate at the cap: events.jsonl unchanged, no events.1.jsonl, no lock'
else
  report FAIL 'duplicate at the cap' "main=$(nlines "$(logf "$ROOT")") old=$(nlines "$(log1f "$ROOT")")"
fi
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=50'; run_hook cursor "$ROOT" "$pb"
if [ -e "$(log1f "$ROOT")" ] && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'duplicate at the cap control: a new payload at the same cap does rotate'
else
  report FAIL 'duplicate at the cap control: a new payload at the same cap does rotate'
fi
new_root
mkdir -p "$ROOT/$LOGREL"
printf '%s\n' "$head_line" > "$(logf "$ROOT")"
printf '{"key":"%s"}\n' "$(exp_key "$pa")" > "$(log1f "$ROOT")"
cp "$(logf "$ROOT")" "$FX/before-main"
cp "$(log1f "$ROOT")" "$FX/before-old"
EXTRA_ENV='AGENT_KIT_HOOK_LOG_MAX_BYTES=50'; run_hook cursor "$ROOT" "$pa"
if cmp -s "$FX/before-main" "$(logf "$ROOT")" && cmp -s "$FX/before-old" "$(log1f "$ROOT")"; then
  report PASS 'duplicate (key only in events.1.jsonl) at the cap: both files unchanged'
else
  report FAIL 'duplicate (key only in events.1.jsonl) at the cap: both files unchanged'
fi

# --- 8. limited PATH: cksum fallback, and only the documented tools ------------------------------------
TOOLBIN="$FX/toolbin"
mkdir -p "$TOOLBIN"
missing=""
for t in sed grep awk mv mkdir rmdir find wc date cksum cat sort; do
  tp="$(command -v "$t" 2>/dev/null)" || tp=""
  if [ -n "$tp" ]; then ln -sf "$tp" "$TOOLBIN/$t"; else missing="$missing $t"; fi
done
if [ -n "$missing" ]; then
  report SKIP 'limited PATH: cksum fallback, rotation and summary' "tools missing:$missing"
elif PATH="$TOOLBIN" command -v sha256sum >/dev/null 2>&1 || PATH="$TOOLBIN" command -v shasum >/dev/null 2>&1; then
  report SKIP 'limited PATH: cksum fallback, rotation and summary' 'a SHA tool is still on the limited PATH'
else
  new_root
  EXTRA_ENV="PATH=$TOOLBIN"; run_hook cursor "$ROOT" "$P_CURSOR_SUB"
  lf="$(logf "$ROOT")"
  want="${W_CURSOR_SUB/@KEY@/$(exp_cksum_key "$P_CURSOR_SUB")}"
  if contract_ok cursor && file_is "$lf" "$want"; then
    report PASS 'cksum fallback: with no SHA tool on PATH the key is c + the cksum CRC (exact line)'
  else
    report FAIL 'cksum fallback: key is c + the cksum CRC' "log=[$(cat "$lf" 2>/dev/null)] want=[$want]"
  fi
  EXTRA_ENV="PATH=$TOOLBIN"; run_hook cursor "$ROOT" "$P_CURSOR_SUB"
  if [ "$(nlines "$lf")" = 1 ]; then
    report PASS 'cksum fallback: the same payload twice still gives one line'
  else
    report FAIL 'cksum fallback: the same payload twice still gives one line' "lines=$(nlines "$lf")"
  fi
  EXTRA_ENV="PATH=$TOOLBIN"; run_hook cursor "$ROOT" "$P_CURSOR_STOP"
  if [ "$(nlines "$lf")" = 2 ]; then
    report PASS 'cksum fallback: a different payload still appends'
  else
    report FAIL 'cksum fallback: a different payload still appends' "lines=$(nlines "$lf")"
  fi
  EXTRA_ENV="PATH=$TOOLBIN"; run_hook claude "$ROOT" "$P_CLAUDE_SUB"
  if contract_ok claude && [ "$(nlines "$lf")" = 3 ]; then
    report PASS 'limited PATH: the claude path logs with only the documented tools'
  else
    report FAIL 'limited PATH: the claude path logs with only the documented tools' "lines=$(nlines "$lf")"
  fi

  new_root
  EXTRA_ENV="PATH=$TOOLBIN AGENT_KIT_HOOK_LOG_MAX_BYTES=200"; run_hook cursor "$ROOT" "$pa"
  EXTRA_ENV="PATH=$TOOLBIN AGENT_KIT_HOOK_LOG_MAX_BYTES=200"; run_hook cursor "$ROOT" "$pb"
  if contract_ok cursor && [ -e "$(log1f "$ROOT")" ] && [ "$(nlines "$(logf "$ROOT")")" = 1 ] \
     && [ ! -e "$ROOT/$LOGREL/.rotate.lock" ]; then
    report PASS 'limited PATH: rotation (mkdir lock, wc, mv, rmdir) works with only the documented tools'
  else
    report FAIL 'limited PATH: rotation' "main=$(nlines "$(logf "$ROOT")") old=$(nlines "$(log1f "$ROOT")")"
  fi
  out="$(env PATH="$TOOLBIN" "$BASH" "$HOOK" summary --root "$ROOT" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^hook-log: 2 events (' && printf '%s\n' "$out" | grep -q '^errors and aborts$' \
     && [ "$(printf '%s\n' "$out" | grep -c '^  2026-10-29T12:00:00Z cursor stop - aborted -$')" = 2 ]; then
    report PASS 'limited PATH: summary works with only the documented tools'
  else
    report FAIL 'limited PATH: summary' "rc=$rc out=[$out]"
  fi
fi

# --- 9. summary ---------------------------------------------------------------------------------------
sum_run() { # <root> [args...] → RC, OUT, ERR
  local r="$1"
  shift
  OUT="$("$BASH" "$HOOK" summary --root "$r" "$@" 2>"$FX/err.txt")"
  RC=$?
  ERR="$(cat "$FX/err.txt")"
}

snapshot() { # <root> → file list and checksums
  (cd "$1" && find . | sort && find . -type f | sort | while IFS= read -r f; do cksum "$f"; done)
}

HINT='hint: no claude events — if Claude Code is in use, check that .claude/settings.json has the hook-log Stop hooks (merge the emit warning snippet)'

# These hand-written lines are pre-change lines: they have no "error" key, and the errors list shows `-`.
new_root
mkdir -p "$ROOT/$LOGREL"
cat > "$(log1f "$ROOT")" <<'EOF'
{"ts":"2026-10-29T10:00:00Z","harness":"cursor","event":"subagentStop","session":"c1","generation":"g1","agent_id":null,"agent_type":"explore","status":"completed","duration_ms":10,"message_count":1,"tool_call_count":2,"loop_count":0,"model":"test-model","modified_files":0,"key":"k1"}
EOF
cat > "$(logf "$ROOT")" <<'EOF'
{"ts":"2026-10-29T10:05:00Z","harness":"cursor","event":"subagentStop","session":"c1","generation":"g2","agent_id":null,"agent_type":"implementer","status":"error","duration_ms":20,"message_count":3,"tool_call_count":4,"loop_count":0,"model":"test-model","modified_files":2,"key":"k2"}
{"ts":"2026-10-29T10:10:00Z","harness":"claude","event":"Stop","session":"s1","generation":"p1","agent_id":null,"agent_type":null,"status":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"k3"}
EOF
real="$(cd "$ROOT" && pwd -P)"
snap_before="$(snapshot "$ROOT")"
sum_run "$ROOT"
want="hook-log: 3 events ($real/$LOGREL/events.jsonl)
by event
  1 Stop
  2 subagentStop
by harness/agent_type
  1 claude/-
  1 cursor/explore
  1 cursor/implementer
by status
  1 -
  1 completed
  1 error
by model
  1 -
  2 test-model
errors and aborts
  2026-10-29T10:05:00Z cursor subagentStop implementer error -"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ "$OUT" = "$want" ]; then
  report PASS 'summary: exact output over events.1.jsonl + events.jsonl (three pre-change lines, one error, no hint)'
else
  report FAIL 'summary: exact output' "rc=$RC err=[$ERR] out=[$OUT]"
fi
if [ "$(snapshot "$ROOT")" = "$snap_before" ]; then
  report PASS 'summary: reads only (file list and bytes unchanged)'
else
  report FAIL 'summary: reads only' 'root changed'
fi

new_root
mkdir -p "$ROOT/$LOGREL"
cat > "$(logf "$ROOT")" <<'EOF'
{"ts":"2026-10-29T11:00:00Z","harness":"cursor","event":"stop","session":"c2","generation":"g1","agent_id":null,"agent_type":null,"status":"aborted","duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":1,"model":"m\"x","modified_files":null,"key":"k4"}
{"ts":"2026-10-29T11:05:00Z","harness":"cursor","event":"subagentStop","session":"c2","generation":"g1","agent_id":null,"agent_type":"explore","status":"error","duration_ms":5,"message_count":1,"tool_call_count":1,"loop_count":0,"model":"m\"x","modified_files":1,"key":"k5"}
{"ts":"2026-10-29T11:06:00Z","harness":"cursor","event":"subagentStop","session":"c2","generation":"g1","agent_id":null,"agent_type":"explore","status":"completed","duration_ms":5,"message_count":1,"tool_call_count":1,"loop_count":0,"model":"m\"x","modified_files":1,"key":"k6"}
EOF
sum_run "$ROOT"
real="$(cd "$ROOT" && pwd -P)"
want="hook-log: 3 events ($real/$LOGREL/events.jsonl)
by event
  1 stop
  2 subagentStop
by harness/agent_type
  1 cursor/-
  2 cursor/explore
by status
  1 aborted
  1 completed
  1 error
by model
  3 m\\\"x
errors and aborts
  2026-10-29T11:00:00Z cursor stop - aborted -
  2026-10-29T11:05:00Z cursor subagentStop explore error -
$HINT"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then
  report PASS 'summary: aborted and error runs are both listed in log order (cursor only → the claude hint closes the report)'
else
  report FAIL 'summary: aborted and error runs are both listed' "rc=$RC out=[$OUT]"
fi

new_root
mkdir -p "$ROOT/$LOGREL"
printf '%s\n' '{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"Stop","session":"s","generation":"p","agent_id":null,"agent_type":null,"status":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"k7"}' > "$(logf "$ROOT")"
sum_run "$ROOT"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | tail -n 2 | head -n 1 | grep -qx 'errors and aborts' && [ "$(printf '%s\n' "$OUT" | tail -n 1)" = '  none' ]; then
  report PASS 'summary: no error or aborted run → "errors and aborts" lists "  none"'
else
  report FAIL 'summary: no error run → none' "out=[$OUT]"
fi
if ! printf '%s\n' "$OUT" | grep -qF 'hint:'; then
  report PASS 'summary hint control: a log with a claude event prints no hint'
else
  report FAIL 'summary hint control: a log with a claude event prints no hint' "out=[$OUT]"
fi

new_root
snap_before="$(snapshot "$ROOT")"
sum_run "$ROOT"
real="$(cd "$ROOT" && pwd -P)"
if [ "$RC" -eq 0 ] && [ "$OUT" = "hook-log: 0 events ($real/$LOGREL/events.jsonl)
$HINT" ] && [ "$(snapshot "$ROOT")" = "$snap_before" ]; then
  report PASS 'summary: an empty root prints "hook-log: 0 events (<path>)" and the claude hint, exit 0, creates nothing'
else
  report FAIL 'summary: an empty root' "rc=$RC out=[$OUT]"
fi

# an empty events.jsonl (present, zero bytes) is the same empty case
new_root
mkdir -p "$ROOT/$LOGREL"
: > "$(logf "$ROOT")"
sum_run "$ROOT"
real="$(cd "$ROOT" && pwd -P)"
if [ "$RC" -eq 0 ] && [ "$OUT" = "hook-log: 0 events ($real/$LOGREL/events.jsonl)
$HINT" ]; then
  report PASS 'summary hint: an empty events.jsonl prints the claude hint'
else
  report FAIL 'summary hint: an empty events.jsonl prints the claude hint' "rc=$RC out=[$OUT]"
fi

# the hint appears once, after the sections, only when no line has harness claude
new_root
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
sum_run "$ROOT"
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "$HINT" ] && [ "$(printf '%s\n' "$OUT" | grep -cF 'hint:')" = 1 ] \
   && printf '%s\n' "$OUT" | tail -n 2 | head -n 1 | grep -qx '  none'; then
  report PASS 'summary hint: cursor-only log → one hint line after the last section'
else
  report FAIL 'summary hint: cursor-only log → one hint line after the last section' "out=[$OUT]"
fi
run_hook claude "$ROOT" "$P_CLAUDE_STOP"
sum_run "$ROOT"
if [ "$RC" -eq 0 ] && ! printf '%s\n' "$OUT" | grep -qF 'hint:'; then
  report PASS 'summary hint: one claude event added → the hint disappears'
else
  report FAIL 'summary hint: one claude event added → the hint disappears' "out=[$OUT]"
fi

# a Claude Code StopFailure through the hook, then the summary: the error value is listed
SF_RL='{"session_id":"sf-1","prompt_id":"pf-1","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429","last_assistant_message":"API Error"}'
SF_UN='{"session_id":"sf-2","prompt_id":"pf-2","hook_event_name":"StopFailure","error":"unknown"}'
new_root
run_hook claude "$ROOT" "$SF_RL"
run_hook claude "$ROOT" "$SF_UN"
run_hook cursor "$ROOT" "$P_CURSOR_STOP"
sum_run "$ROOT"
real="$(cd "$ROOT" && pwd -P)"
want="hook-log: 3 events ($real/$LOGREL/events.jsonl)
by event
  2 StopFailure
  1 stop
by harness/agent_type
  2 claude/-
  1 cursor/-
by status
  1 aborted
  2 error
by model
  2 -
  1 test-model
errors and aborts
  2026-10-29T12:00:00Z claude StopFailure - error rate_limit
  2026-10-29T12:00:00Z claude StopFailure - error unknown
  2026-10-29T12:00:00Z cursor stop - aborted -"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ "$OUT" = "$want" ]; then
  report PASS 'summary: StopFailure lines list their error value; a cursor abort and an old line list -'
else
  report FAIL 'summary: StopFailure lines list their error value' "rc=$RC err=[$ERR] out=[$OUT]"
fi

# a root path holding a backslash prints verbatim in the header (awk -v would turn \t into a tab)
BSROOT="$FIXTURE_TMPDIR/bs"'\t'"root"
mkdir -p "$BSROOT/$LOGREL" && assert_fixture_root "$BSROOT" || exit 1
printf '%s\n' '{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"Stop","session":"s","generation":"p","agent_id":null,"agent_type":null,"status":null,"error":null,"duration_ms":null,"message_count":null,"tool_call_count":null,"loop_count":null,"model":null,"modified_files":null,"key":"k8"}' > "$(logf "$BSROOT")"
sum_run "$BSROOT"
real="$(cd "$BSROOT" && pwd -P)"
case "$real" in
  *'\t'*) ;;
  *) report FAIL 'summary: backslash root fixture' "pwd -P lost the backslash: [$real]" ;;
esac
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | head -n 1)" = "hook-log: 1 events ($real/$LOGREL/events.jsonl)" ]; then
  report PASS 'summary: a root containing a backslash (\t) prints verbatim in the header'
else
  report FAIL 'summary: a root containing a backslash prints verbatim' "rc=$RC out=[$(printf '%s\n' "$OUT" | head -n 1)] want=[$real]"
fi

# the log written by the hook feeds the summary end to end
new_root
run_hook cursor "$ROOT" "$P_CURSOR_SUB"
run_hook cursor "$ROOT" "$P_CURSOR_STOP"
run_hook claude "$ROOT" "$P_CLAUDE_SUB"
sum_run "$ROOT"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^hook-log: 3 events (' \
   && printf '%s\n' "$OUT" | grep -qx '  1 aborted' && printf '%s\n' "$OUT" | grep -qx '  1 claude/implementer' \
   && printf '%s\n' "$OUT" | grep -qx '  2026-10-29T12:00:00Z cursor stop - aborted -'; then
  report PASS 'summary: reads what the hook wrote (3 events, the aborted stop listed)'
else
  report FAIL 'summary: reads what the hook wrote' "out=[$OUT]"
fi

# the default root is the parent of the script's directory (_kit/..)
new_root
mkdir -p "$ROOT/_kit"
cp "$HOOK" "$ROOT/_kit/hook-log.sh"
printf '%s' "$P_CURSOR_STOP" | (cd "$FX" && "$BASH" "$ROOT/_kit/hook-log.sh" hook cursor >"$FX/out.bin" 2>"$FX/err.txt")
RC=$?
ERR="$(cat "$FX/err.txt")"
if contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]; then
  report PASS 'root: without --root the log goes under the parent of the script directory'
else
  report FAIL 'root: without --root the log goes under the parent of the script directory' "rc=$RC err=[$ERR]"
fi
OUT="$(cd "$FX" && "$BASH" "$ROOT/_kit/hook-log.sh" summary 2>&1)"
real="$(cd "$ROOT" && pwd -P)"
if [ "$(printf '%s\n' "$OUT" | head -n 1)" = "hook-log: 1 events ($real/$LOGREL/events.jsonl)" ]; then
  report PASS 'root: summary without --root resolves the same default root'
else
  report FAIL 'root: summary without --root' "out=[$OUT]"
fi

# --- 10. usage -------------------------------------------------------------------------------------------
usage_case() { # <name> <want-rc> <args...>
  local name="$1" want="$2" rc
  shift 2
  "$BASH" "$HOOK" "$@" >"$FX/uo.txt" 2>"$FX/ue.txt" </dev/null
  rc=$?
  if [ "$rc" -eq "$want" ]; then
    report PASS "usage: $name → exit $want"
  else
    report FAIL "usage: $name" "rc=$rc (want $want) out=[$(cat "$FX/uo.txt")] err=[$(cat "$FX/ue.txt")]"
  fi
}
usage_case 'no arguments' 2
usage_case 'unknown subcommand' 2 bogus
usage_case 'hook without a harness' 2 hook
usage_case 'hook with an unknown harness' 2 hook copilot
usage_case 'hook with a stray argument' 2 hook cursor extra
usage_case 'hook with --root and no value' 2 hook cursor --root
usage_case 'hook with an empty --root' 2 hook cursor --root ''
usage_case 'summary with a stray argument' 2 summary extra
usage_case 'summary with --root and no value' 2 summary --root
usage_case 'summary on a missing root' 2 summary --root "$FX/no-such-dir"
usage_case '--help' 0 --help
usage_case '--help with an extra argument' 2 --help extra
usage_case '-h is not an alias' 2 -h
if "$BASH" "$HOOK" --help 2>/dev/null | grep -q '^usage: hook-log.sh hook <claude|cursor>'; then
  report PASS 'usage: --help prints the usage line on stdout'
else
  report FAIL 'usage: --help prints the usage line on stdout'
fi
new_root
"$BASH" "$HOOK" hook cursor extra --root "$ROOT" >"$FX/uo.txt" 2>/dev/null </dev/null
if [ ! -s "$FX/uo.txt" ]; then
  report PASS 'usage: a usage error on the hook path prints nothing on stdout (no {})'
else
  report FAIL 'usage: a usage error on the hook path prints nothing on stdout' "out=[$(cat "$FX/uo.txt")]"
fi

# --- 11. smoke (the acceptance command) ----------------------------------------------------------------
d="$(mktemp -d "$FIXTURE_TMPDIR/smoke.XXXXXX")"
assert_fixture_root "$d" || exit 1
smoke="$(printf '%s' '{"hook_event_name":"stop","conversation_id":"c1","generation_id":"g1","status":"completed","loop_count":0,"cursor_version":"1","model":"m"}' | "$BASH" "$HOOK" hook cursor --root "$d"; echo; wc -l < "$d/$LOGREL/events.jsonl" | sed 's/ //g')"
if [ "$smoke" = '{}

1' ]; then
  report PASS 'smoke: one cursor stop → {} on stdout and one line in events.jsonl'
else
  report FAIL 'smoke: one cursor stop' "out=[$smoke]"
fi

# --- 11b. probes with mutation proofs ------------------------------------------------------------------------
# Each probe returns 0 when the behavior holds for the tool in $HOOK (or the kit-guard tool in $KG_HOOK). mutant_check
# runs the probe on the real tool (a passing case) and on a copy changed by one sed script (a failing case): a probe that
# still passes on the mutant would prove nothing.
probe_stopfailure() { # the exact StopFailure line: status "error", the error enum, the key
  new_root
  run_hook claude "$ROOT" "$P_CLAUDE_SF"
  contract_ok claude && file_is "$(logf "$ROOT")" "${W_CLAUDE_SF/@KEY@/$(exp_key "$P_CLAUDE_SF")}"
}
probe_error_free_text() { # free text never becomes the error value
  new_root
  run_hook claude "$ROOT" '{"session_id":"s","hook_event_name":"StopFailure","error":"429: secret-detail"}'
  contract_ok claude && [ "$(fld "$(logf "$ROOT")" error duration_ms)" = null ]
}
probe_error_other_event() { # the error field is null outside StopFailure
  new_root
  run_hook claude "$ROOT" "${P_CLAUDE_STOP%\}},\"error\":\"rate_limit\"}"
  contract_ok claude && [ "$(fld "$(logf "$ROOT")" error duration_ms)" = null ] && ! grep -qF rate_limit "$(logf "$ROOT")"
}
probe_array() { # a top-level array is skipped, not logged as its inner object
  new_root
  run_hook claude "$ROOT" "[$P_CLAUDE_STOP]"
  contract_ok claude && [ ! -e "$ROOT/_memory" ]
}
probe_hint() { # an empty log prints the hint as its last line
  new_root
  sum_run "$ROOT"
  [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "$HINT" ]
}
probe_error_col() { # the errors list ends with the error value
  new_root
  run_hook claude "$ROOT" "$P_CLAUDE_SF"
  sum_run "$ROOT"
  printf '%s\n' "$OUT" | grep -qxF '  2026-10-29T12:00:00Z claude StopFailure - error rate_limit'
}
probe_bs_path() { # a root holding a backslash prints verbatim in the header
  local r="$FIXTURE_TMPDIR/bsp"'\t'"root" real
  mkdir -p "$r/$LOGREL"
  assert_fixture_root "$r" || exit 1
  printf '%s\n' '{"ts":"2026-10-29T12:00:00Z","harness":"claude","event":"Stop","key":"k9"}' > "$(logf "$r")"
  real="$(cd "$r" && pwd -P)"
  sum_run "$r"
  [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | head -n 1)" = "hook-log: 1 events ($real/$LOGREL/events.jsonl)" ]
}
probe_cdpath_hook_default_root() { # _kit/hook-log.sh run by a relative path, CDPATH=. exported
  new_root
  mkdir -p "$ROOT/_kit"
  cp "$HOOK" "$ROOT/_kit/hook-log.sh"
  printf '%s' "$P_CURSOR_STOP" | (cd "$ROOT" && env CDPATH=. "$BASH" _kit/hook-log.sh hook cursor >"$FX/out.bin" 2>"$FX/err.txt")
  RC=$?
  ERR="$(cat "$FX/err.txt")"
  contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]
}
probe_cdpath_hook_root_rel() { # --root <relative name>, CDPATH=. exported
  new_root
  printf '%s' "$P_CURSOR_STOP" | (cd "$FIXTURE_TMPDIR" && env CDPATH=. "$BASH" "$HOOK" hook cursor --root "${ROOT##*/}" >"$FX/out.bin" 2>"$FX/err.txt")
  RC=$?
  ERR="$(cat "$FX/err.txt")"
  contract_ok cursor && [ "$(nlines "$(logf "$ROOT")")" = 1 ]
}
probe_cdpath_summary_default_root() { # summary by a relative script path, CDPATH=. exported
  local real
  new_root
  mkdir -p "$ROOT/_kit"
  cp "$HOOK" "$ROOT/_kit/hook-log.sh"
  run_hook cursor "$ROOT" "$P_CURSOR_STOP"
  OUT="$(cd "$ROOT" && env CDPATH=. "$BASH" _kit/hook-log.sh summary 2>&1)"
  real="$(cd "$ROOT" && pwd -P)"
  [ "$(printf '%s\n' "$OUT" | head -n 1)" = "hook-log: 1 events ($real/$LOGREL/events.jsonl)" ]
}
probe_cdpath_summary_root_rel() { # summary --root <relative name>, CDPATH=. exported
  local real
  new_root
  run_hook cursor "$ROOT" "$P_CURSOR_STOP"
  OUT="$(cd "$FIXTURE_TMPDIR" && env CDPATH=. "$BASH" "$HOOK" summary --root "${ROOT##*/}" 2>&1)"
  real="$(cd "$ROOT" && pwd -P)"
  [ "$(printf '%s\n' "$OUT" | head -n 1)" = "hook-log: 1 events ($real/$LOGREL/events.jsonl)" ]
}
probe_cdpath_kit_guard() { # kit-guard: check by a relative script path; hook with a relative --root name; CDPATH=. exported
  local out rc h json
  new_root
  mkdir -p "$ROOT/_kit" "$ROOT/docs"
  cp "$KG_HOOK" "$ROOT/_kit/kit-guard.sh"
  printf '# a\n' > "$ROOT/docs/a.md"
  h="$(sha_hex < "$ROOT/docs/a.md")"
  printf '{\n  "files": {\n    "docs/a.md": "%s"\n  }\n}\n' "$h" > "$ROOT/orchestration-kit.manifest.json"
  out="$(cd "$ROOT" && env CDPATH=. "$BASH" _kit/kit-guard.sh check 2>&1)"
  rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = 'kit-guard: ok (1 kit files)' ] || return 1
  json="{\"file_path\":\"docs/a.md\",\"cwd\":\"$ROOT\"}"
  printf '%s' "$json" | (cd "$FIXTURE_TMPDIR" && env -u CURSOR_PROJECT_DIR CDPATH=. "$BASH" "$ROOT/_kit/kit-guard.sh" hook claude --root "${ROOT##*/}" >/dev/null 2>"$FX/err.txt")
  rc=$?
  [ "$rc" -eq 2 ] && grep -qF 'kit-guard: docs/a.md' "$FX/err.txt"
}

mutant_check() { # <id> <var: HOOK|KG_HOOK> <label> <probe> <sed script>
  local id="$1" var="$2" label="$3" probe="$4" script="$5" real mut r_real=0 r_mut=0
  eval "real=\$$var"
  mut="$FX/mut-$id.sh"
  if ! sed -e "$script" "$real" > "$mut" 2>/dev/null || cmp -s "$real" "$mut"; then
    report FAIL "mutation: $label" "the sed script did not change the tool (id $id)"
    return 0
  fi
  "$probe" >/dev/null 2>&1 || r_real=1
  eval "$var=\$mut"
  "$probe" >/dev/null 2>&1 || r_mut=1
  eval "$var=\$real"
  if [ "$r_real" -eq 0 ]; then report PASS "probe: $label"; else report FAIL "probe: $label" "fails on the real tool"; fi
  if [ "$r_mut" -eq 1 ]; then report PASS "mutation: $label → the mutant fails the probe"; else report FAIL "mutation: $label" "the mutant still passes the probe"; fi
}

CDP_SED='s|CDPATH= cd|cd|g'
mutant_check sf-event HOOK 'StopFailure is an accepted claude event' probe_stopfailure \
  's/ || ev == "\\"StopFailure\\""//'
mutant_check sf-status HOOK 'StopFailure sets status "error"' probe_stopfailure \
  's|val[[]"status"[]] = |val["xstatus"] = |'
mutant_check err-regex HOOK 'the error value must be snake_case (free text → null)' probe_error_free_text \
  's|[[]a-z_[]]+"[$]/|.+"$/|'
mutant_check err-other HOOK 'the error field is null outside StopFailure' probe_error_other_event \
  's|else delete val[[]"error"[]]|else delete val["errorx"]|'
mutant_check array HOOK 'a top-level array payload is skipped' probe_array \
  's|if (c != "{") { done = 1; break }|if (c != "{") { i++; continue }|'
mutant_check hint HOOK 'summary prints the zero-claude hint' probe_hint \
  's|if (nclaude == 0) {|if (nclaude == 99) {|'
mutant_check errcol HOOK 'the errors list ends with the error value' probe_error_col \
  's| " " st " " er$| " " st|'
mutant_check environ HOOK 'summary passes the log path through ENVIRON (backslash root)' probe_bs_path \
  's|^  path = ENVIRON.*$|  path = path|;s|HOOK_LOG_EVENTS_PATH="[$]f" awk|awk -v path="$f"|'
mutant_check cdp-default HOOK 'hook: CDPATH=. never changes the default root' probe_cdpath_hook_default_root "$CDP_SED"
mutant_check cdp-hook-root HOOK 'hook: CDPATH=. never changes a relative --root' probe_cdpath_hook_root_rel "$CDP_SED"
mutant_check cdp-sum-default HOOK 'summary: CDPATH=. never changes the default root' probe_cdpath_summary_default_root "$CDP_SED"
mutant_check cdp-sum-root HOOK 'summary: CDPATH=. never changes a relative --root' probe_cdpath_summary_root_rel "$CDP_SED"
mutant_check cdp-kit-guard KG_HOOK 'kit-guard: CDPATH=. never changes the script root or a relative --root' probe_cdpath_kit_guard "$CDP_SED"

# --- 12. static guards on the tool file -------------------------------------------------------------------
if [ -x "$HOOK" ]; then
  report PASS 'static: the tool file is executable'
else
  report FAIL 'static: the tool file is executable'
fi
if bash -n "$HOOK" 2>/dev/null; then
  report PASS 'static: bash -n accepts the tool file'
else
  report FAIL 'static: bash -n accepts the tool file'
fi
if [ "$(head -n 1 "$HOOK")" = '#!/usr/bin/env bash' ]; then
  report PASS 'static: bash shebang'
else
  report FAIL 'static: bash shebang'
fi
static_absent() { # <name> <grep-flags> <pattern>
  if grep "$2" -e "$3" "$HOOK" >/dev/null 2>&1; then
    report FAIL "static: $1" "$(grep -n "$2" -e "$3" "$HOOK" | head -n 3)"
  else
    report PASS "static: $1"
  fi
}
static_absent 'no declare -A (Bash 3.2)' -nF 'declare -A'
static_absent 'no ${var,,} case modification (Bash 3.2)' -nE '\$\{[a-zA-Z_]+,,'
static_absent 'no jq' -n 'jq'
static_absent 'no {{ (emit resolves the file as a template)' -nF '{{'
static_absent 'no HTML comment opener' -nF '<!--'
static_absent 'never steers: no followup_message' -nF 'followup_message'
static_absent 'never steers: no "decision" key' -nF '"decision"'
static_absent 'never steers: no additionalContext' -nF 'additionalContext'
static_absent 'no sibling-project names' -nEi '\bar[g]us\b|\bbe[a]m\b'
static_absent 'no forbidden review wording' -nEi 'jud[g]'
static_absent 'no model IDs' -nEi 'cla[u]de-[0-9a-z]|gp[t]-[0-9]|compos[e]r-[0-9]|gemi[n]i-[0-9]|so[n]net|o[p]us|ha[i]ku'
static_absent 'no BOOTSTRAP marker' -nF 'BOOTSTRAP:'
static_absent 'the summary path never goes through awk -v path= (a backslash would be an escape)' -nF '-v path='
static_absent 'no comment line is wider than 100 columns' -nE '^#.{100,}$'
bare_cd="$(grep -nE '(^|[^[:alnum:]_=])cd[[:space:]]' "$HOOK" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vF 'CDPATH= cd' || true)"
if [ -z "$bare_cd" ]; then
  report PASS 'static: every cd that computes a path runs as CDPATH= cd'
else
  report FAIL 'static: every cd that computes a path runs as CDPATH= cd' "found: $bare_cd"
fi
if grep -q '^set -u$' "$HOOK" && grep -q '^export LC_ALL=C$' "$HOOK"; then
  report PASS 'static: set -u and export LC_ALL=C'
else
  report FAIL 'static: set -u and export LC_ALL=C'
fi
# only the documented tools are called as commands (a rough scan of the non-comment, non-awk code)
bad_tools="$(sed -e '/^EXTRACT_AWK=/,/^'"'"'$/d' -e '/^SUMMARY_AWK=/,/^'"'"'$/d' -e '/^SUMMARY_FORMAT_AWK=/,/^'"'"'$/d' -e '/^[[:space:]]*#/d' "$HOOK" \
  | grep -owE '(^|[|;(`]|\$\()[[:space:]]*(tr|cut|head|tail|dirname|basename|rm|touch|mktemp|tee|xargs|uniq|python3?|perl|ruby|node|stat|realpath|readlink|ls|cp|ln|chmod|env|od|xxd|base64|openssl|md5sum|printenv)[[:space:]]' || true)"
if [ -z "$bad_tools" ]; then
  report PASS 'static: no tool outside the documented set is invoked'
else
  report FAIL 'static: no tool outside the documented set is invoked' "found: $bad_tools"
fi
if [ "$(grep -c -F 'hook_event_name' "$HOOK")" -ge 1 ] && grep -q 'AGENT_KIT_HOOK_LOG_MAX_BYTES' "$HOOK" && grep -q 'HOOK_LOG_NOW' "$HOOK" \
   && grep -q '_memory/work/hooks' "$HOOK"; then
  report PASS 'static: the header documents the log path and the environment variables'
else
  report FAIL 'static: the header documents the log path and the environment variables'
fi

echo
echo "=== hook-log summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
