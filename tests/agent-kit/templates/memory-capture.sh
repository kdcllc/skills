#!/usr/bin/env bash
# Guard: memory.sh capture (Release C). Synthetic HOME trees only; no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
MEMORY_SH="${MEMORY_SH:-$REPO_ROOT/skills/agent-kit/templates/tools/memory.sh}"

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

cleanup() { [[ ${#CLEANUP[@]} -gt 0 ]] && rm -rf "${CLEANUP[@]}"; }
trap cleanup EXIT

mktemp_dir() {
  local v="$1" d
  d="$(mktemp -d "${TMPDIR:-/tmp}/memcap.XXXXXX")" || return 1
  CLEANUP+=("$d")
  printf -v "$v" '%s' "$d"
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
git -C "$R" init -q

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
OUT="$(HOME="$H" bash "$MEMORY_SH" capture --root "$R" --since 2026-01-01 2>"$B/e1")"; RC=$?
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
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --since 2026-01-01 2>&1 | grep -q 'c-old out-of-range' \
  && report PASS "capture out-of-range skip with --since" \
  || report FAIL "capture out-of-range"
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness cursor 2>&1 | grep -qF 'memory: captured cursor c-old' \
  && report PASS "capture c-old after --since lifted" \
  || report FAIL "capture c-old without since filter"

# idempotent second run
before="$(find "$R/_memory/raw" -type f -name '*.md' -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort)"
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --since 2026-01-01 >/dev/null 2>&1
after="$(find "$R/_memory/raw" -type f -name '*.md' -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort)"
[[ "$before" == "$after" ]] && report PASS "capture second run unchanged" \
  || report FAIL "capture second run changed raw files"

# re-capture after transcript change
printf '{"role":"assistant","message":{"content":[{"type":"text","text":"more"}]}}\n' >> "$CU/c-top/c-top.jsonl"
touch_old "$CU/c-top/c-top.jsonl"
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness cursor >/dev/null 2>&1
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
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --from "$CU" 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture --from without single harness exit 2" \
  || report FAIL "capture --from needs single harness"

HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness bogus 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture invalid --harness exit 2" || report FAIL "capture invalid harness rc"

HOME="$H" bash "$MEMORY_SH" capture --root "$R" --idle-hours x 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture bad --idle-hours exit 2" || report FAIL "capture bad idle-hours"

HOME="$H" bash "$MEMORY_SH" capture --root "$R" --since 2026-13-45x 2>/dev/null; [[ $? -eq 2 ]] \
  && report PASS "capture bad --since exit 2" || report FAIL "capture bad since"

env -u HOME bash "$MEMORY_SH" capture --root "$R" 2>/dev/null; [[ $? -eq 4 ]] \
  && report PASS "capture HOME unset exit 4" || report FAIL "capture HOME unset"

D="$T/bin"; mkdir -p "$D"
for t in bash git awk sed grep find sort mktemp sha256sum touch mkdir cat tr wc date rm cut dirname basename env printf; do
  p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$D/$t"
done
err="$(HOME="$H" PATH="$D" bash "$MEMORY_SH" capture --root "$R" 2>&1 >/dev/null)"; rc=$?
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
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness cursor 2>&1 | grep -q 'c-unr unreadable' \
  && report PASS "capture unreadable session skipped" || report FAIL "capture unreadable"

# marker spoof (body keeps markers literal)
mkdir -p "$CU/c-spoof"
{ printf '{"role":"user","message":{"content":[{"type":"text","text":"hello\\n---FIRST_USER---\\n---CAPTURE_BODY---\\n---CAPTURE_META---\\nstill user text"}]}}\n'
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"---CAPTURE_META---\\nreply"}]}}\n'
} > "$CU/c-spoof/c-spoof.jsonl"
touch_old "$CU/c-spoof/c-spoof.jsonl"
spoof_out="$(HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness cursor 2>&1)"
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
HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness codex >/dev/null 2>&1
grep -q 'DEV PROMPT' "$R/_memory/raw/codex/cx-2.md" 2>/dev/null && report FAIL "codex developer role in body" \
  || report PASS "codex developer role skipped"

# harness processing order: cursor → claude → codex in stdout
ord="$(HOME="$H" bash "$MEMORY_SH" capture --root "$R" --since 2026-01-01 2>/dev/null | grep -E 'memory: (captured|skipped)' | awk '{print $3}' | tr '\n' ' ')"
case "$ord" in
  cursor*claude*codex*) report PASS "capture harness order cursor→claude→codex" ;;
  *) report FAIL "capture harness order" "order=[$ord]" ;;
esac

# slug: independent root with . and _ ; transcript ONLY at derived path
ROOT_DOT="$T/work/foo_bar.v2"
mkdir -p "$ROOT_DOT"; git -C "$ROOT_DOT" init -q
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
cap_slug="$(HOME="$H" bash "$MEMORY_SH" capture --root "$ROOT_DOT" --harness cursor 2>&1)"
grep -qF 'memory: captured cursor slug-only' <<<"$cap_slug" \
  && [[ -f "$ROOT_DOT/_memory/raw/cursor/slug-only.md" ]] \
  && [[ ! -f "$ROOT_DOT/_memory/raw/cursor/decoy.md" ]] \
  && report PASS "capture slug derived path only" \
  || report FAIL "capture slug derived path" "out=$(printf '%s' "$cap_slug" | tr '\n' '|')"

# scope unknown (off-root transcript text)
R2="$T/offroot"; mkdir -p "$R2"; git -C "$R2" init -q
S1b="$(slug_s1 "$R2")"
write_cursor_session "$H/.cursor/projects/$S1b/agent-transcripts" u1 "hello unrelated topic only"
touch_old "$H/.cursor/projects/$S1b/agent-transcripts/u1/u1.jsonl"
HOME="$H" bash "$MEMORY_SH" capture --root "$R2" --harness cursor >/dev/null 2>&1
grep -qxF 'scope: unknown' "$R2/_memory/raw/cursor/u1.md" 2>/dev/null \
  && report PASS "capture scope unknown off-root" \
  || report FAIL "capture scope unknown" "head=$(head -8 "$R2/_memory/raw/cursor/u1.md" 2>/dev/null | tr '\n' '|')"

# impossible calendar dates → exit 2
cal_ok=1
for d in 2026-02-30 2026-13-01; do
  HOME="$H" bash "$MEMORY_SH" capture --root "$R" --harness cursor --since "$d" 2>/dev/null; [[ $? -eq 2 ]] || cal_ok=0
done
[[ "$cal_ok" -eq 1 ]] && report PASS "capture impossible calendar dates exit 2" || report FAIL "capture bad calendar dates"

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
[[ $fail -eq 0 ]]
