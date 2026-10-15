#!/usr/bin/env bash
# Guard: memory.sh capture (Release C). Synthetic HOME trees only; no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/memcapbase.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
CANON_MEMORY_SH="$REPO_ROOT/skills/agent-kit/templates/tools/memory.sh"
MEMORY_SH="${MEMORY_SH:-$CANON_MEMORY_SH}"
case "$MEMORY_SH" in /*) ;; *) MEMORY_SH="$REPO_ROOT/$MEMORY_SH" ;; esac

pass=0; fail=0; skip=0
CLEANUP=()

report() {
  local st="$1" name="$2" det="${3:-}"
  case "$st" in
    PASS) pass=$((pass + 1)); echo "PASS: $name" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${det:+ -- $det}" ;;
    *) fail=$((fail + 1)); echo "FAIL: $name${det:+ -- $det}" >&2 ;;
  esac
}

cleanup() {
  [[ ${#CLEANUP[@]} -gt 0 ]] && rm -rf "${CLEANUP[@]}"
  rm -rf "$FIXTURE_TMPDIR"
}
trap cleanup EXIT

mktemp_dir() {
  local v="$1" d
  d="$(mktemp -d "$FIXTURE_TMPDIR/memcap.XXXXXX")" || return 1
  assert_fixture_root "$d" || return 1
  CLEANUP+=("$d")
  printf -v "$v" '%s' "$d"
}

git_fixture() {
  assert_fixture_root "$1" || exit 1
  git -C "$1" "${@:2}"
}

capture_at() {
  assert_fixture_root "$1" || exit 1
  HOME="$H" bash "$MEMORY_SH" capture --root "$1" "${@:2}"
}

slug_s1() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g; s/^-//'; }
slug_s2() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

touch_old() { touch -t 202610010000 "$@"; }

write_cursor_session() { # dir id first_user_text
  local dir="$1" id="$2" text="$3"
  mkdir -p "$dir/$id"
  printf '{"role":"user","message":{"content":[{"type":"text","text":%s}]}}\n' \
    "$(printf '%s' "$text" | jq -Rs .)" > "$dir/$id/$id.jsonl"
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' >> "$dir/$id/$id.jsonl"
}

# --- fixture tree (synthetic only) ---
mktemp_dir T
mktemp_dir B
H="$T/home"
R="$T/proj.v1_x"
mkdir -p "$H" "$R"
assert_fixture_root "$R" || exit 1
git_fixture "$R" init -q

S1="$(slug_s1 "$R")"
S2="$(slug_s2 "$R")"
CU="$H/.cursor/projects/$S1/agent-transcripts"
CC="$H/.claude/projects/$S2"
CX="$H/.codex/sessions/2026/10/13"
mkdir -p "$CU" "$CC" "$CX"

write_cursor_session "$CU" c-top "Please add a feature in $R for the memory tool"
write_cursor_session "$CU" c-sub "Read and follow the context package at /x/spawns/12-context.md exactly."
write_cursor_session "$CU" c-sub2 "Your full context package follows"
write_cursor_session "$CU" c-sub3 $'You are the evaluator subagent. Read: .cursor/agents/evaluator.md'
write_cursor_session "$CU" c-recheck "Re-check request: please verify the capture tests"
write_cursor_session "$CU" c-ctxmd "See /tmp/spawns/12-context.md for details"
write_cursor_session "$CU" c-live "fresh session"
write_cursor_session "$CU" c-old "old session"
mkdir -p "$CU/c-unr"
printf 'garbage\n' > "$CU/c-unr/c-unr.jsonl"

printf '{"type":"user","message":{"role":"user","content":"claude plain string about %s"}}\n' "$R" > "$CC/cc-1.jsonl"
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"answer token=abcdefgh9"}]}}\n' >> "$CC/cc-1.jsonl"

printf '{"type":"session_meta","payload":{"cwd":"%s"}}\n' "$R" > "$CX/rollout-cx-1.jsonl"
printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"codex question"}]}}\n' >> "$CX/rollout-cx-1.jsonl"
printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"codex answer"}]}}\n' >> "$CX/rollout-cx-1.jsonl"

touch_old "$CU"/*/*.jsonl "$CC"/*.jsonl "$CX"/*.jsonl 2>/dev/null || true
touch "$CU/c-live/c-live.jsonl"
touch -t 202501010000 "$CU/c-old/c-old.jsonl"

# --- run 1: all harnesses with --since ---
OUT="$(capture_at "$R" --since 2026-01-01 2>"$B/e1")"; RC=$?
grep -qF 'memory: captured cursor c-top' <<<"$OUT" && grep -qF 'memory: skipped cursor c-sub subagent' <<<"$OUT" \
  && grep -qF 'memory: skipped cursor c-live live' <<<"$OUT" \
  && grep -qF 'memory: captured claude cc-1' <<<"$OUT" \
  && grep -qF 'memory: captured codex cx-1' <<<"$OUT" \
  && [[ "$RC" -eq 0 ]] \
  && report PASS "capture run1 idle top-level + skip subagent/live + claude/codex" \
  || report FAIL "capture run1" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' '|')"

grep -q 'c-recheck subagent' <<<"$OUT" && grep -q 'c-ctxmd subagent' <<<"$OUT" \
  && report PASS "capture subagent Re-check and -context.md" \
  || report FAIL "capture subagent Re-check/context.md" "out=$(printf '%s' "$OUT" | tr '\n' '|')"

grep -q 'c-sub2 subagent' <<<"$OUT" && grep -q 'c-sub3 subagent' <<<"$OUT" \
  && report PASS "capture subagent classifiers sub2/sub3" \
  || report FAIL "capture subagent classifiers"

# ledger: no row for live or out-of-range after run1
if [[ -f "$R/_memory/raw/.captured" ]]; then
  grep -q $'\tc-live\t' "$R/_memory/raw/.captured" && report FAIL "ledger has live session row" \
    || report PASS "ledger no row for live session"
  grep -q $'\tc-old\t' "$R/_memory/raw/.captured" && report FAIL "ledger has out-of-range row" \
    || report PASS "ledger no row for out-of-range session"
else
  report FAIL "ledger missing after run1"
fi

# secrets redacted in raw + claude body tag
if grep -rl 'abcdefgh9\|ghp_' "$R/_memory/raw" 2>/dev/null | grep -q .; then
  report FAIL "capture secrets redacted in raw"
else
  report PASS "capture secrets redacted in raw"
fi
grep -q '\[REDACTED:secret\]' "$R/_memory/raw/claude/cc-1.md" 2>/dev/null \
  && report PASS "capture claude raw contains REDACTED secret" \
  || report FAIL "capture claude redaction in raw"

# out-of-range and post-since capture (before any cursor-only wide capture)
capture_at "$R" --since 2026-01-01 2>&1 | grep -q 'c-old out-of-range' \
  && report PASS "capture out-of-range skip with --since" \
  || report FAIL "capture out-of-range"
capture_at "$R" --harness cursor 2>&1 | grep -qF 'memory: captured cursor c-old' \
  && report PASS "capture c-old after --since lifted" \
  || report FAIL "capture c-old without since filter"

# idempotent second run
before="$(find "$R/_memory/raw" -type f -name '*.md' -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort)"
capture_at "$R" --since 2026-01-01 >/dev/null 2>&1
after="$(find "$R/_memory/raw" -type f -name '*.md' -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort)"
[[ "$before" == "$after" ]] && report PASS "capture second run unchanged" \
  || report FAIL "capture second run changed raw files"

# re-capture after transcript change
printf '{"role":"assistant","message":{"content":[{"type":"text","text":"more"}]}}\n' >> "$CU/c-top/c-top.jsonl"
touch_old "$CU/c-top/c-top.jsonl"
capture_at "$R" --harness cursor >/dev/null 2>&1
n="$(grep -c 'c-top' "$R/_memory/raw/.captured" 2>/dev/null || echo 0)"
[[ "$n" -ge 2 ]] && report PASS "capture re-capture after transcript change (ledger rows >= 2)" \
  || report FAIL "capture re-capture ledger" "rows=$n"

# scope repo (transcript mentions absolute root)
if [[ -f "$R/_memory/raw/cursor/c-top.md" ]] && grep -qE '^scope: repo' "$R/_memory/raw/cursor/c-top.md"; then
  report PASS "capture scope: repo for in-repo session"
else
  report FAIL "capture scope: repo" "head=$(head -8 "$R/_memory/raw/cursor/c-top.md" 2>/dev/null | tr '\n' '|')"
fi

# error paths
capture_at "$R" --from "$CU" 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture --from without single harness exit 2" \
  || report FAIL "capture --from needs single harness"

capture_at "$R" --harness bogus 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture invalid --harness exit 2" || report FAIL "capture invalid harness rc"

capture_at "$R" --idle-hours x 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture bad --idle-hours exit 2" || report FAIL "capture bad idle-hours"

idle7_out="$(capture_at "$R" --idle-hours 1234567 2>&1)"; idle7_rc=$?
grep -qxF 'memory: invalid --idle-hours' <<<"$idle7_out" && [[ "$idle7_rc" -eq 2 ]] \
  && report PASS "capture --idle-hours 7 digits exit 2 + message" \
  || report FAIL "capture idle-hours 7 digits" "rc=$idle7_rc out=$idle7_out"

idle6_out="$(capture_at "$R" --harness cursor --idle-hours 100000 2>&1)"; idle6_rc=$?
[[ "$idle6_rc" -eq 0 && "$idle6_out" != *'invalid --idle-hours'* ]] \
  && report PASS "capture --idle-hours 6 digits accepted" \
  || report FAIL "capture idle-hours 6 digits" "rc=$idle6_rc out=$(printf '%s' "$idle6_out" | tr '\n' '|')"

capture_at "$R" --since 2026-13-45x 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture bad --since exit 2" || report FAIL "capture bad since"

assert_fixture_root "$R" || exit 1
env -u HOME bash "$MEMORY_SH" capture --root "$R" 2>/dev/null; [[ $? -eq 4 ]] \
  && report PASS "capture HOME unset exit 4" || report FAIL "capture HOME unset"

D="$T/bin"; mkdir -p "$D"
for t in bash git awk sed grep find sort mktemp sha256sum touch mkdir cat tr wc date rm cut dirname basename env printf; do
  p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$D/$t"
done
err="$(assert_fixture_root "$R" && HOME="$H" PATH="$D" bash "$MEMORY_SH" capture --root "$R" 2>&1 >/dev/null)"; rc=$?
[[ "$rc" -eq 4 && "$err" == 'memory: capture needs jq' ]] \
  && report PASS "capture jq missing exit 4 exact line" \
  || report FAIL "capture jq missing" "rc=$rc err=$err"

# write fence: only _memory/raw under repo root from capture
extra="$(find "$R" -type f ! -path '*/_memory/raw/*' ! -path '*/.git/*' 2>/dev/null | head -1)"
[[ -z "$extra" ]] && report PASS "capture write fence (_memory/raw only)" \
  || report FAIL "capture write fence" "extra=$extra"

# unreadable session (unparseable jsonl)
mkdir -p "$CU/c-unr"
printf 'garbage\n{{{\n' > "$CU/c-unr/c-unr.jsonl"
touch_old "$CU/c-unr/c-unr.jsonl"
capture_at "$R" --harness cursor 2>&1 | grep -q 'c-unr unreadable' \
  && report PASS "capture unreadable session skipped" || report FAIL "capture unreadable"

# marker spoof (body keeps markers literal)
mkdir -p "$CU/c-spoof"
{ printf '{"role":"user","message":{"content":[{"type":"text","text":"hello\\n---FIRST_USER---\\n---CAPTURE_BODY---\\n---CAPTURE_META---\\nstill user text"}]}}\n'
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"---CAPTURE_META---\\nreply"}]}}\n'
} > "$CU/c-spoof/c-spoof.jsonl"
touch_old "$CU/c-spoof/c-spoof.jsonl"
spoof_out="$(capture_at "$R" --harness cursor 2>&1)"
sf="$R/_memory/raw/cursor/c-spoof.md"
if grep -qF 'memory: captured cursor c-spoof' <<<"$spoof_out" \
  && [[ -f "$sf" ]] && grep -q 'FIRST_USER' "$sf"; then
  report PASS "capture marker spoof not interpreted"
else
  report FAIL "capture marker spoof" "out=$(printf '%s' "$spoof_out" | tr '\n' '|')"
fi

# codex developer role skipped
printf '{"type":"session_meta","payload":{"cwd":"%s"}}\n' "$R" > "$CX/rollout-cx-2.jsonl"
printf '{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"DEV PROMPT"}]}}\n' >> "$CX/rollout-cx-2.jsonl"
printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"q2"}]}}\n' >> "$CX/rollout-cx-2.jsonl"
touch_old "$CX/rollout-cx-2.jsonl"
capture_at "$R" --harness codex >/dev/null 2>&1
grep -q 'DEV PROMPT' "$R/_memory/raw/codex/cx-2.md" 2>/dev/null && report FAIL "codex developer role in body" \
  || report PASS "codex developer role skipped"

# harness processing order: cursor → claude → codex in stdout
ord="$(capture_at "$R" --since 2026-01-01 2>/dev/null | grep -E 'memory: (captured|skipped)' | awk '{print $3}' | tr '\n' ' ')"
case "$ord" in
  cursor*claude*codex*) report PASS "capture harness order cursor→claude→codex" ;;
  *) report FAIL "capture harness order" "order=[$ord]" ;;
esac

# slug: independent root with . and _ ; transcript ONLY at derived path
ROOT_DOT="$T/work/foo_bar.v2"
mkdir -p "$ROOT_DOT"
assert_fixture_root "$ROOT_DOT" || exit 1
git_fixture "$ROOT_DOT" init -q
EXP_S1="$(slug_s1 "$ROOT_DOT")"
EXP_S2="$(slug_s2 "$ROOT_DOT")"
DERIVED_CU="$H/.cursor/projects/$EXP_S1/agent-transcripts"
DERIVED_CC="$H/.claude/projects/$EXP_S2"
mkdir -p "$DERIVED_CU/slug-only"
write_cursor_session "$DERIVED_CU" slug-only "Work only inside $ROOT_DOT please"
touch_old "$DERIVED_CU/slug-only/slug-only.jsonl"
# decoy at wrong slug must not capture
WRONG="$H/.cursor/projects/wrong-slug/agent-transcripts/decoy"
mkdir -p "$WRONG/decoy"
write_cursor_session "$WRONG" decoy "Work only inside $ROOT_DOT please"
touch_old "$WRONG/decoy/decoy.jsonl"
assert_fixture_root "$ROOT_DOT" || exit 1
cap_slug="$(capture_at "$ROOT_DOT" --harness cursor 2>&1)"
grep -qF 'memory: captured cursor slug-only' <<<"$cap_slug" \
  && [[ -f "$ROOT_DOT/_memory/raw/cursor/slug-only.md" ]] \
  && [[ ! -f "$ROOT_DOT/_memory/raw/cursor/decoy.md" ]] \
  && report PASS "capture slug derived path only" \
  || report FAIL "capture slug derived path" "out=$(printf '%s' "$cap_slug" | tr '\n' '|')"

# scope unknown (off-root transcript text)
R2="$T/offroot"; mkdir -p "$R2"
assert_fixture_root "$R2" || exit 1
git_fixture "$R2" init -q
S1b="$(slug_s1 "$R2")"
write_cursor_session "$H/.cursor/projects/$S1b/agent-transcripts" u1 "hello unrelated topic only"
touch_old "$H/.cursor/projects/$S1b/agent-transcripts/u1/u1.jsonl"
capture_at "$R2" --harness cursor >/dev/null 2>&1
grep -qxF 'scope: unknown' "$R2/_memory/raw/cursor/u1.md" 2>/dev/null \
  && report PASS "capture scope unknown off-root" \
  || report FAIL "capture scope unknown" "head=$(head -8 "$R2/_memory/raw/cursor/u1.md" 2>/dev/null | tr '\n' '|')"

# impossible calendar dates → exit 2
cal_ok=1
for d in 2026-02-30 2026-13-01; do
  capture_at "$R" --harness cursor --since "$d" 2>/dev/null; [[ $? -eq 2 ]] || cal_ok=0
done
[[ "$cal_ok" -eq 1 ]] && report PASS "capture impossible calendar dates exit 2" || report FAIL "capture bad calendar dates"

cap_mut_idle() { # sed assert_fn
  local sedscript="$1" name="$2" fn="$3" mutsh canon_ok=0 mut_ok=0
  mutsh="$(mktemp "${TMPDIR:-/tmp}/memcapmut.XXXXXX")"
  sed "$sedscript" "$CANON_MEMORY_SH" > "$mutsh"
  chmod +x "$mutsh"
  if MEMORY_SH="$CANON_MEMORY_SH" "$fn"; then canon_ok=1; fi
  if MEMORY_SH="$mutsh" "$fn"; then mut_ok=1; fi
  rm -f "$mutsh"
  if [[ "$canon_ok" -eq 1 && "$mut_ok" -eq 0 ]]; then
    report PASS "mutation-$name: canonical PASS, mutant FAIL"
  else
    report FAIL "mutation-$name" "canon_ok=$canon_ok mut_ok=$mut_ok"
  fi
}

assert_idle7_reject() {
  local out rc
  out="$(capture_at "$R" --idle-hours 1234567 2>&1)"; rc=$?
  grep -qxF 'memory: invalid --idle-hours' <<<"$out" && [[ "$rc" -eq 2 ]]
}
cap_mut_idle 's/\[ "\${#v}" -le 6 \] || die 2/true # mut-idle-cap/' \
  'drop-idle-hours-digit-cap' assert_idle7_reject

if ( assert_fixture_root "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects repository root"
else
  report PASS "fixture-root guard rejects repository root"
fi
if ( assert_fixture_root "" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects empty root"
else
  report PASS "fixture-root guard rejects empty root"
fi
# Helper-level negatives that can fail. capture_at: MEMORY_SH is an `exit 0` stub that drops a
# marker, so an unguarded capture_at would succeed and leave the marker. git_fixture: git is shadowed
# by a function that drops a marker (so a missing assert can never reach the real git or the cwd).
# Each control run proves the stub/shadow is live for a fixture root.
_cap_stub="$FIXTURE_TMPDIR/memory-stub.sh"
_cap_marker="$FIXTURE_TMPDIR/memory-stub-ran"
printf '%s\n' ': > "$MEMORY_STUB_MARKER"' 'exit 0' > "$_cap_stub"
rm -f "$_cap_marker"
_cap_ctrl_rc=0
( MEMORY_STUB_MARKER="$_cap_marker" MEMORY_SH="$_cap_stub" capture_at "$R" --harness cursor >/dev/null 2>&1 ) || _cap_ctrl_rc=$?
_cap_ctrl_ran=0
[ -e "$_cap_marker" ] && _cap_ctrl_ran=1
rm -f "$_cap_marker"
_cap_empty_rc=0
( MEMORY_STUB_MARKER="$_cap_marker" MEMORY_SH="$_cap_stub" capture_at "" --harness cursor >/dev/null 2>&1 ) || _cap_empty_rc=$?
if [[ "$_cap_ctrl_rc" -eq 0 && "$_cap_ctrl_ran" -eq 1 && "$_cap_empty_rc" -ne 0 && ! -e "$_cap_marker" ]]; then
  report PASS "capture_at refuses empty root before capture"
else
  report FAIL "capture_at refuses empty root before capture" "control_rc=$_cap_ctrl_rc control_ran=$_cap_ctrl_ran empty_rc=$_cap_empty_rc marker=$([[ -e "$_cap_marker" ]] && echo present || echo absent)"
fi
_git_marker="$FIXTURE_TMPDIR/git-ran"
rm -f "$_git_marker"
_git_ctrl_rc=0
( git() { : > "$_git_marker"; return 0; }; git_fixture "$R" rev-parse >/dev/null 2>&1 ) || _git_ctrl_rc=$?
_git_ctrl_ran=0
[[ -e "$_git_marker" ]] && _git_ctrl_ran=1
rm -f "$_git_marker"
_git_empty_rc=0
( git() { : > "$_git_marker"; return 0; }; git_fixture "" rev-parse >/dev/null 2>&1 ) || _git_empty_rc=$?
if [[ "$_git_ctrl_rc" -eq 0 && "$_git_ctrl_ran" -eq 1 && "$_git_empty_rc" -ne 0 && ! -e "$_git_marker" ]]; then
  report PASS "git_fixture refuses empty root before git"
else
  report FAIL "git_fixture refuses empty root before git" "control_rc=$_git_ctrl_rc control_ran=$_git_ctrl_ran empty_rc=$_git_empty_rc marker=$([[ -e "$_git_marker" ]] && echo present || echo absent)"
fi

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
[[ $fail -eq 0 ]]
