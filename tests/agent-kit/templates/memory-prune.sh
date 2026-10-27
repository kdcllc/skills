#!/usr/bin/env bash
# Guard: memory.sh prune — synthetic git fixtures only; MEMORY_SH override for ad-hoc runs.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mempr.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
export GIT_CEILING_DIRECTORIES="$FIXTURE_TMPDIR_ABS"

git_fixture() {
  assert_fixture_root "$1" || exit 1
  git -C "$1" "${@:2}"
}

CANON_MEMORY_SH="$REPO_ROOT/skills/agent-kit/templates/tools/memory.sh"
MEMORY_SH="${MEMORY_SH:-$CANON_MEMORY_SH}"
case "$MEMORY_SH" in /*) ;; *) MEMORY_SH="$REPO_ROOT/$MEMORY_SH" ;; esac

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
FEATURE_TPL="$TEMPLATES/skills/feature/SKILL.template.md"
MEM_PROTO="$TEMPLATES/skills/feature/reference/memory-protocol.md"
ORCH_TPL="$TEMPLATES/ORCHESTRATION.md"
MEM_README_TPL="$TEMPLATES/memory/README.md"

pass=0; fail=0; skip=0
CLEANUP=()
TMP_BASE=""

report() {
  local st="$1" name="$2" det="${3:-}"
  case "$st" in
    PASS) pass=$((pass + 1)); echo "PASS: $name" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${det:+ -- $det}" ;;
    *) fail=$((fail + 1)); echo "FAIL: $name${det:+ -- $det}" >&2 ;;
  esac
}

cleanup() {
  [[ -n "$TMP_BASE" ]] && chmod -R u+w "$TMP_BASE" 2>/dev/null
  [[ ${#CLEANUP[@]} -gt 0 ]] && rm -rf "${CLEANUP[@]}"
  [[ -n "$TMP_BASE" ]] && rm -rf "$TMP_BASE"
}
trap cleanup EXIT

mktemp_dir() {
  local v="$1" d
  d="$(mktemp -d "$TMP_BASE/XXXXXX")" || return 1
  assert_fixture_root "$d" || exit 1
  CLEANUP+=("$d")
  printf -v "$v" '%s' "$d"
}

pr_run() { # root args... -> sets PR_OUT PR_RC
  set +e
  PR_OUT="$(bash "$MEMORY_SH" prune --root "$1" "${@:2}" 2>&1)"
  PR_RC=$?
  set -u
}

snap_tree() {
  (
    cd "$1" || exit 1
    echo '# paths'
    find . -path ./.git -prune -o -print 2>/dev/null | LC_ALL=C sort
    echo '# sha256'
    find . -path ./.git -prune -o -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      sha256sum < "$p" | awk -v rp="$p" '{print $1, rp}'
    done
  )
}

records_snap() { # root
  local R="$1" p
  find "$R/_memory/records" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
    sha256sum < "$p" | awk -v rp="${p#"$R"/}" '{print $1, rp}'
  done
}

git_refs_snap() { # root
  git -C "$1" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null | LC_ALL=C sort
}

git_init_fixture() { # root
  local R="$1"
  git_fixture "$R" init -q
  git_fixture "$R" config user.email 'mempr@test.local'
  git_fixture "$R" config user.name 'mempr'
  printf '_memory/work/\n' > "$R/.gitignore"
  git_fixture "$R" add -- .gitignore
  git_fixture "$R" commit -qm 'init'
}

write_record() { # root id kind title source body
  local R="$1" id="$2" kind="$3" title="$4" source="$5" body="$6" store path yyyy mm
  store="$R/_memory"
  yyyy="${id:0:4}"
  mm="${id:4:2}"
  path="$store/records/$yyyy/$mm/$id.md"
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '---'
    printf 'id: %s\nkind: %s\ntitle: %s\n' "$id" "$kind" "$title"
    printf 'date: 2026-01-01\n'
    printf 'source: "%s"\n' "$source"
    printf 'commit: deadbeef0000\nharness: ""\ntags: []\nsupersedes: []\n'
    printf 'sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf '%s\n' '---'
    printf '%s\n' "$body"
  } > "$path"
}

write_quarantine() { # root id kind title source body
  local R="$1" id="$2" kind="$3" title="$4" source="$5" body="$6" path
  path="$R/_memory/quarantine/$id.md"
  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '---'
    printf 'id: %s\nkind: %s\ntitle: %s\n' "$id" "$kind" "$title"
    printf 'date: 2026-01-01\n'
    printf 'source: "%s"\n' "$source"
    printf 'commit: deadbeef0000\nharness: ""\ntags: []\nsupersedes: []\n'
    printf 'sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf '%s\n' '---'
    printf '%s\n' "$body"
  } > "$path"
}

commit_path() { # root relpath msg
  git_fixture "$1" add -- "$2"
  git_fixture "$1" commit -qm "${3:-commit}"
}

add_record_commit() { # root id
  local R="$1" id="$2" rel
  rel="_memory/records/${id:0:4}/${id:4:2}/$id.md"
  commit_path "$R" "$rel" "add $id"
}

repo_memory_snapshot() {
  local d p
  for d in records quarantine .index; do
    [[ -e "$REPO_ROOT/_memory/$d" ]] || continue
    find "$REPO_ROOT/_memory/$d" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      sha256sum < "$p" | awk -v rp="${p#"$REPO_ROOT"/}" '{print $1, rp}'
    done
  done
}

repo_work_listing() {
  if [[ ! -d "$REPO_ROOT/_memory/work" ]]; then
    return 0
  fi
  find "$REPO_ROOT/_memory/work" -mindepth 1 -maxdepth 2 2>/dev/null | LC_ALL=C sort
}

REPO_MEM_BEFORE="$(repo_memory_snapshot)"
REPO_WORK_BEFORE="$(repo_work_listing)"

finish() {
  local after work_after
  after="$(repo_memory_snapshot)"
  if [[ "$after" == "$REPO_MEM_BEFORE" ]]; then
    report PASS "(w) real-repo _memory/{records,quarantine,.index} unchanged"
  else
    report FAIL "(w) real-repo _memory changed"
  fi
  work_after="$(repo_work_listing)"
  if [[ "$work_after" == "$REPO_WORK_BEFORE" ]]; then
    report PASS "(w) real-repo _memory/work listing unchanged"
  else
    report FAIL "(w) real-repo _memory/work listing changed"
  fi
  case "$FIXTURE_TMPDIR" in
    "$REPO_ROOT"|"$REPO_ROOT"/*)
      report FAIL "(leak) FIXTURE_TMPDIR under REPO_ROOT"
      ;;
    *)
      report PASS "(leak) FIXTURE_TMPDIR private"
      ;;
  esac
  echo
  echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
  if [[ $fail -eq 0 ]]; then exit 0; else exit 1; fi
}

TMP_BASE="$FIXTURE_TMPDIR"
CLEANUP+=("$TMP_BASE")
mktemp_dir B

# --- case 1: mixed --plan, tree unchanged ---
mk_mixed_fixture() { # root
  local R="$1" MIX_ID1 MIX_ID2
  MIX_ID1="20260101T120000Z-11111111"
  MIX_ID2="20260102T120000Z-22222222"
  git_init_fixture "$R"
  write_record "$R" "$MIX_ID1" fact t1 "" 'body1'
  write_record "$R" "$MIX_ID2" fact t2 "" 'body2'
  add_record_commit "$R" "$MIX_ID1"
  add_record_commit "$R" "$MIX_ID2"
  mkdir -p "$R/_memory/work/goals/goal-del" "$R/_memory/work/goals/goal-open"
  mkdir -p "$R/_memory/work/research/topic-del" "$R/_memory/work/research/topic-open"
  printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$MIX_ID1" \
    > "$R/_memory/work/goals/goal-del/orchestration-log.md"
  printf '# log\n\n### 2026-01-01T10:00-04:00 — work\n' > "$R/_memory/work/goals/goal-open/orchestration-log.md"
  printf '2026-01-01T12:00:00Z\n%s\n' "$MIX_ID2" > "$R/_memory/work/research/topic-del/ingested"
  printf '# report\n' > "$R/_memory/work/research/topic-open/report.md"
}

mktemp_dir R1
mk_mixed_fixture "$R1"
before="$(snap_tree "$R1")"
pr_run "$R1" --plan
after="$(snap_tree "$R1")"
ok=1
grep -qxF 'memory: prune goal goal-del would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal goal-open keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research topic-del would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research topic-open keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune plan 2 would-delete, 2 kept' <<<"$PR_OUT" || ok=0
[[ "$PR_RC" -eq 0 && "$before" == "$after" && "$ok" -eq 1 ]] \
  && report PASS "case-01: mixed --plan lines + tree unchanged" \
  || report FAIL "case-01" "rc=$PR_RC ok=$ok"

# --- case 2: --apply deletes durable only ---
mktemp_dir R2
mk_mixed_fixture "$R2"
rec_before="$(records_snap "$R2")"
pr_run "$R2" --apply
ok=1
grep -qxF 'memory: prune goal goal-del deleted' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research topic-del deleted' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal goal-open keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research topic-open keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune 2 deleted, 2 kept, 0 failed' <<<"$PR_OUT" || ok=0
[[ -d "$R2/_memory/work/goals/goal-open" && -d "$R2/_memory/work/research/topic-open" ]] || ok=0
[[ ! -d "$R2/_memory/work/goals/goal-del" && ! -d "$R2/_memory/work/research/topic-del" ]] || ok=0
rec_after="$(records_snap "$R2")"
[[ "$rec_before" == "$rec_after" && "$PR_RC" -eq 0 && "$ok" -eq 1 ]] \
  && report PASS "case-02: --apply deletes durable goal+research only" \
  || report FAIL "case-02" "rc=$PR_RC ok=$ok"

# --- case 3: latest archive line wins + body ARCHIVED ignored ---
mktemp_dir R3
git_init_fixture "$R3"
CID3="20260301T120000Z-33333333"
write_record "$R3" "$CID3" fact t "" 'b'
add_record_commit "$R3" "$CID3"
mkdir -p "$R3/_memory/work/goals/g-win" "$R3/_memory/work/goals/g-miss" "$R3/_memory/work/goals/g-body"
cat > "$R3/_memory/work/goals/g-win/orchestration-log.md" <<EOF
# log
### 2026-01-01T10:00-04:00 — ARCHIVED: 19990101T000000Z-deadbeef
### 2026-01-02T10:00-04:00 — Archive correction: ARCHIVED: $CID3
EOF
cat > "$R3/_memory/work/goals/g-miss/orchestration-log.md" <<EOF
# log
### 2026-01-01T10:00-04:00 — ARCHIVED: $CID3
### 2026-01-02T10:00-04:00 — ARCHIVED: 19990101T000000Z-deadbeef
EOF
cat > "$R3/_memory/work/goals/g-body/orchestration-log.md" <<'EOF'
# log
### 2026-01-01T10:00-04:00 — note
Body line ARCHIVED: 20260301T120000Z-33333333 without heading
EOF
pr_run "$R3" --plan --goals
ok=1
grep -qxF 'memory: prune goal g-win would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-miss keep:missing:19990101T000000Z-deadbeef' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-body keep:not-archived' <<<"$PR_OUT" || ok=0
[[ "$PR_RC" -eq 0 && "$ok" -eq 1 ]] && report PASS "case-03: latest ARCHIVED wins; body ignored" \
  || report FAIL "case-03" "rc=$PR_RC"

# --- case 4: free-form ARCHIVED parsing ---
mktemp_dir R4
git_init_fixture "$R4"
FID4="20260401T120000Z-44444444"
write_record "$R4" "$FID4" fact t "" 'b'
add_record_commit "$R4" "$FID4"
mkdir -p "$R4/_memory/work/goals/g-free" "$R4/_memory/work/goals/g-semi"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: goal-summary %s; decision %s (note)\n' "$FID4" "$FID4" \
  > "$R4/_memory/work/goals/g-free/orchestration-log.md"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: goal-summary 19990101T000000Z-deadbeef; decision %s (note)\n' "$FID4" \
  > "$R4/_memory/work/goals/g-semi/orchestration-log.md"
pr_run "$R4" --plan --goals
ok=1
grep -qxF 'memory: prune goal g-free would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-semi keep:missing:19990101T000000Z-deadbeef' <<<"$PR_OUT" || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-04: free-form ARCHIVED ids" || report FAIL "case-04"

# --- case 5: staged / untracked / missing ---
mktemp_dir R5
git_init_fixture "$R5"
SID5="20260501T120000Z-55555555"
UID5="20260502T120000Z-66666666"
write_record "$R5" "$SID5" fact t "" 'staged-only'
write_record "$R5" "$UID5" fact t "" 'untracked-only'
git_fixture "$R5" add -- "_memory/records/2026/05/$SID5.md"
mkdir -p "$R5/_memory/work/goals/g-staged" "$R5/_memory/work/goals/g-untr" "$R5/_memory/work/goals/g-miss"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$SID5" > "$R5/_memory/work/goals/g-staged/orchestration-log.md"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$UID5" > "$R5/_memory/work/goals/g-untr/orchestration-log.md"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 19990101T000000Z-deadbeef\n' > "$R5/_memory/work/goals/g-miss/orchestration-log.md"
pr_run "$R5" --plan --goals
ok=1
grep -qxF 'memory: prune goal g-staged keep:uncommitted:'"$SID5" <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-untr keep:uncommitted:'"$UID5" <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-miss keep:missing:19990101T000000Z-deadbeef' <<<"$PR_OUT" || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-05: staged/untracked/missing ids" || report FAIL "case-05"

# --- case 6: quarantine-only committed ---
mktemp_dir R6
git_init_fixture "$R6"
QID6="20260601T120000Z-77777777"
write_quarantine "$R6" "$QID6" fact t "" 'qbody'
commit_path "$R6" "_memory/quarantine/$QID6.md" 'q'
mkdir -p "$R6/_memory/work/goals/g-q"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$QID6" > "$R6/_memory/work/goals/g-q/orchestration-log.md"
pr_run "$R6" --plan --goals
grep -qxF 'memory: prune goal g-q would-delete' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-06: quarantine id durable" || report FAIL "case-06"

# --- case 7: keep:no-ids + keep:no-log ---
mktemp_dir R7
git_init_fixture "$R7"
mkdir -p "$R7/_memory/work/goals/g-noids" "$R7/_memory/work/goals/g-nolog"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: (no ids here)\n' > "$R7/_memory/work/goals/g-noids/orchestration-log.md"
printf '# goal only\n' > "$R7/_memory/work/goals/g-nolog/goal.md"
pr_run "$R7" --plan --goals
grep -qxF 'memory: prune goal g-noids keep:no-ids' <<<"$PR_OUT" \
  && grep -qxF 'memory: prune goal g-nolog keep:no-log' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-07: no-ids and no-log" || report FAIL "case-07"

# --- case 8: source fallback ---
mktemp_dir R8
git_init_fixture "$R8"
S8A="20260701T120000Z-88888888"
S8B="20260702T120000Z-99999999"
write_record "$R8" "$S8A" goal-summary t 'goal g-src (goal.md)' 'a'
add_record_commit "$R8" "$S8A"
write_record "$R8" "20260703T120000Z-aaaaaaaa" goal-summary t '_memory/work/goals/g-legacy/goal.md' 'legacy'
add_record_commit "$R8" "20260703T120000Z-aaaaaaaa"
write_record "$R8" "$S8B" goal-summary t 'goal g-uncom (goal.md)' 'b-wt'
git_fixture "$R8" add -- "_memory/records/2026/07/$S8B.md"
mkdir -p "$R8/_memory/work/goals/g-src" "$R8/_memory/work/goals/g-uncom" "$R8/_memory/work/goals/g-none" "$R8/_memory/work/goals/g-legacy"
for g in g-src g-uncom g-none g-legacy; do
  printf '# log\n\n### 2026-01-01T10:00-04:00 — open\n' > "$R8/_memory/work/goals/$g/orchestration-log.md"
done
pr_run "$R8" --plan --goals
ok=1
grep -qxF 'memory: prune goal g-src would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-uncom keep:uncommitted:'"$S8B" <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-none keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-legacy keep:not-archived' <<<"$PR_OUT" || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-08: source fallback variants" || report FAIL "case-08"

# --- case 9: research ---
mktemp_dir R9
git_init_fixture "$R9"
R9A="20260801T120000Z-bbbbbbbb"
R9B="20260802T120000Z-cccccccc"
write_record "$R9" "$R9A" research-ingest t "" 'a'
write_record "$R9" "$R9B" research-ingest t "" 'b'
add_record_commit "$R9" "$R9A"
write_record "$R9" "$R9B" research-ingest t "" 'b-wt'
git_fixture "$R9" add -- "_memory/records/2026/08/$R9B.md"
mkdir -p "$R9/_memory/work/research/r-ok" "$R9/_memory/work/research/r-noing" "$R9/_memory/work/research/r-uncom" \
  "$R9/_memory/work/research/r-miss" "$R9/_memory/work/research/r-noids"
printf '2026-01-01T00:00:00Z\n%s\n' "$R9A" > "$R9/_memory/work/research/r-ok/ingested"
printf '# r\n' > "$R9/_memory/work/research/r-noing/report.md"
printf '2026-01-01T00:00:00Z\n%s\n' "$R9B" > "$R9/_memory/work/research/r-uncom/ingested"
printf '2026-01-01T00:00:00Z\n19990101T000000Z-deadbeef\n' > "$R9/_memory/work/research/r-miss/ingested"
printf '2026-01-01T00:00:00Z\nno-id-tokens\n' > "$R9/_memory/work/research/r-noids/ingested"
mkdir -p "$R9/_memory/work/research/r-crlf"
printf '2026-01-01T00:00:00Z\r\n%s\r\n' "$R9A" > "$R9/_memory/work/research/r-crlf/ingested"
mkdir -p "$R9/_memory/work/real-research/r-slink"
printf '2026-01-01T00:00:00Z\n%s\n' "$R9A" > "$R9/_memory/work/real-research/r-slink/ingested"
ln -s "$R9/_memory/work/real-research/r-slink" "$R9/_memory/work/research/r-slink"
pr_run "$R9" --plan --research
ok=1
grep -qxF 'memory: prune research r-ok would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-noing keep:not-archived' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-uncom keep:uncommitted:'"$R9B" <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-miss keep:missing:19990101T000000Z-deadbeef' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-noids keep:no-ids' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-crlf would-delete' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune research r-slink keep:symlink' <<<"$PR_OUT" || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-09: research paths" || report FAIL "case-09"

# --- case 10: symlink goals + apply ---
mktemp_dir R10
git_init_fixture "$R10"
T10="20260901T120000Z-dddddddd"
write_record "$R10" "$T10" fact t "" 'b'
add_record_commit "$R10" "$T10"
mkdir -p "$R10/_memory/work/real-goals/g-link" "$R10/_memory/work/goals.real/g-nested"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$T10" > "$R10/_memory/work/real-goals/g-link/orchestration-log.md"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$T10" > "$R10/_memory/work/goals.real/g-nested/orchestration-log.md"
ln -s "$R10/_memory/work/real-goals/g-link" "$R10/_memory/work/goals.real/g-link"
ln -s "$R10/_memory/work/goals.real" "$R10/_memory/work/goals"
pr_run "$R10" --apply --goals
ok=1
grep -qxF 'memory: prune goal g-link keep:symlink' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-nested keep:symlink' <<<"$PR_OUT" || ok=0
[[ -L "$R10/_memory/work/goals.real/g-link" && -d "$R10/_memory/work/real-goals/g-link" ]] || ok=0
[[ -d "$R10/_memory/work/goals.real/g-nested" ]] || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-10: symlinked goals/ parent survive --apply" \
  || report FAIL "case-10 symlinked goals dir"

mktemp_dir R10b
git_init_fixture "$R10b"
T10b="20260902T120000Z-12121212"
write_record "$R10b" "$T10b" fact t "" 'b'
add_record_commit "$R10b" "$T10b"
mkdir -p "$R10b/_memory/work/goals" "$R10b/_memory/work/real-goals/g-slink"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$T10b" > "$R10b/_memory/work/real-goals/g-slink/orchestration-log.md"
ln -s "$R10b/_memory/work/real-goals/g-slink" "$R10b/_memory/work/goals/g-slink"
snap10b_before="$(snap_tree "$R10b/_memory/work/real-goals/g-slink")"
pr_run "$R10b" --apply --goals
snap10b_after="$(snap_tree "$R10b/_memory/work/real-goals/g-slink")"
ok=1
grep -qxF 'memory: prune goal g-slink keep:symlink' <<<"$PR_OUT" || ok=0
[[ -L "$R10b/_memory/work/goals/g-slink" && -d "$R10b/_memory/work/real-goals/g-slink" ]] || ok=0
[[ "$snap10b_before" == "$snap10b_after" ]] || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-10: symlink candidate under real goals/" \
  || report FAIL "case-10 symlink candidate"

# --- case 11: no-git / no commits / missing dirs ---
mktemp_dir R11a
mkdir -p "$R11a/_memory/work/goals/x"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 19990101T000000Z-deadbeef\n' > "$R11a/_memory/work/goals/x/orchestration-log.md"
pr_run "$R11a" --plan
grep -qxF 'memory: prune goal x keep:no-git' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-11a: no-git keep:no-git" || report FAIL "case-11a"
pr_run "$R11a" --apply
grep -qxF 'memory: prune goal x keep:no-git' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] && [[ -d "$R11a/_memory/work/goals/x" ]] \
  && report PASS "case-11b: no-git --apply nothing deleted" || report FAIL "case-11b"

mktemp_dir R11c
git_fixture "$R11c" init -q
git_fixture "$R11c" config user.email t@t
git_fixture "$R11c" config user.name t
printf '_memory/work/\n' > "$R11c/.gitignore"
mkdir -p "$R11c/_memory/work/goals/y"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 19990101T000000Z-deadbeef\n' > "$R11c/_memory/work/goals/y/orchestration-log.md"
pr_run "$R11c" --plan
grep -qxF 'memory: prune goal y keep:no-git' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-11c: no commits keep:no-git" || report FAIL "case-11c"
pr_run "$R11c" --apply
grep -qxF 'memory: prune goal y keep:no-git' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] && [[ -d "$R11c/_memory/work/goals/y" ]] \
  && report PASS "case-11c: no commits --apply nothing deleted" || report FAIL "case-11c apply"

mktemp_dir R11d
git_init_fixture "$R11d"
mkdir -p "$R11d/_memory/work/goals/onlyg"
printf '# log\n\n### 2026-01-01T10:00-04:00 — open\n' > "$R11d/_memory/work/goals/onlyg/orchestration-log.md"
pr_run "$R11d" --plan
grep -qxF 'memory: prune goal onlyg keep:not-archived' <<<"$PR_OUT" \
  && grep -qxF 'memory: prune plan 0 would-delete, 1 kept' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-11d: goals only, no research dir" || report FAIL "case-11d"

mktemp_dir R11e
git_init_fixture "$R11e"
rm -rf "$R11e/_memory/work"
pr_run "$R11e" --plan
grep -qxF 'memory: prune plan 0 would-delete, 0 kept' <<<"$PR_OUT" && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-11e: no _memory/work/" || report FAIL "case-11e"

# --- case 12: filters ---
mktemp_dir R12
mk_mixed_fixture "$R12"
mkdir -p "$R12/_memory/work/goals/.hidden"
HID12="20261201T120000Z-eeeeeeee"
write_record "$R12" "$HID12" fact t "" 'h'
add_record_commit "$R12" "$HID12"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$HID12" > "$R12/_memory/work/goals/.hidden/orchestration-log.md"
pr_run "$R12" --plan --goals
grep -qxF 'memory: prune goal goal-del would-delete' <<<"$PR_OUT" \
  && ! grep -q 'memory: prune research' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: --goals only goals" || report FAIL "case-12 --goals"
pr_run "$R12" --plan --research
grep -qxF 'memory: prune research topic-del would-delete' <<<"$PR_OUT" \
  && ! grep -q 'memory: prune goal' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: --research only research" || report FAIL "case-12 --research"
pr_run "$R12" --plan --only goal-del
grep -qxF 'memory: prune goal goal-del would-delete' <<<"$PR_OUT" \
  && ! grep -qxF 'memory: prune goal goal-open keep:not-archived' <<<"$PR_OUT" \
  && ! grep -q '^memory: prune research ' <<<"$PR_OUT" \
  && grep -qxF 'memory: prune plan 1 would-delete, 0 kept' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: --only single goal" || report FAIL "case-12 --only"
pr_run "$R12" --plan --only goal-del --research
grep -qxF 'memory: prune only goal-del keep:excluded-kind' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: --only goal --research excluded-kind" || report FAIL "case-12 excluded-kind"
pr_run "$R12" --plan --only nope
grep -qxF 'memory: prune only nope keep:not-found' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: --only nope not-found" || report FAIL "case-12 nope"
snap12_before="$(snap_tree "$R12")"
pr_run "$R12" --apply --only .. --only a/b --only .hidden
snap12_after="$(snap_tree "$R12")"
ok=1
grep -qxF 'memory: prune only .. keep:not-found' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune only a/b keep:not-found' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune only .hidden keep:not-found' <<<"$PR_OUT" || ok=0
! grep -q 'memory: prune goal .hidden' <<<"$PR_OUT" || ok=0
[[ -d "$R12/_memory/work/goals/.hidden" ]] || ok=0
[[ "$snap12_before" == "$snap12_after" ]] || ok=0
[[ "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-12: invalid only names + dot dirs untouched on --apply" || report FAIL "case-12 dot"

pr_run "$R12" --plan --only '' --only goal-open
grep -qxF 'memory: prune only  keep:not-found' <<<"$PR_OUT" \
  && grep -qxF 'memory: prune goal goal-open keep:not-archived' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12: empty --only two spaces" || report FAIL "case-12 empty only"

# --- case 12a: base ref ---
mktemp_dir R12a
git_init_fixture "$R12a"
B12A="20261001T120000Z-12121212"
write_record "$R12a" "$B12A" fact t "" 'base'
add_record_commit "$R12a" "$B12A"
COMM_A="$(git_fixture "$R12a" rev-parse HEAD)"
write_record "$R12a" "20261002T120000Z-23232323" fact t "" 'head-only'
add_record_commit "$R12a" "20261002T120000Z-23232323"
COMM_B="$(git_fixture "$R12a" rev-parse HEAD)"
git_fixture "$R12a" update-ref refs/remotes/origin/main "$COMM_A"
git_fixture "$R12a" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
mkdir -p "$R12a/_memory/work/goals/g-unmerged" "$R12a/_memory/work/goals/g-merged"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 20261002T120000Z-23232323\n' > "$R12a/_memory/work/goals/g-unmerged/orchestration-log.md"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$B12A" > "$R12a/_memory/work/goals/g-merged/orchestration-log.md"
refs_before="$(git_refs_snap "$R12a")"
pr_run "$R12a" --plan --goals
ok=1
grep -qxF 'memory: prune goal g-unmerged keep:unmerged:20261002T120000Z-23232323' <<<"$PR_OUT" || ok=0
grep -qxF 'memory: prune goal g-merged would-delete' <<<"$PR_OUT" || ok=0
refs_after="$(git_refs_snap "$R12a")"
[[ "$refs_before" == "$refs_after" && "$ok" -eq 1 && "$PR_RC" -eq 0 ]] && report PASS "case-12a: unmerged vs merged base" \
  || report FAIL "case-12a part1"
git_fixture "$R12a" update-ref refs/remotes/origin/main "$COMM_B"
pr_run "$R12a" --plan --only g-unmerged
grep -qxF 'memory: prune goal g-unmerged would-delete' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12a: after origin/main advance would-delete" || report FAIL "case-12a part2"

mktemp_dir R12a2
git_init_fixture "$R12a2"
U12="20261003T120000Z-34343434"
write_record "$R12a2" "$U12" fact t "" 'u'
add_record_commit "$R12a2" "$U12"
COMM_12A2_OLD="$(git_fixture "$R12a2" rev-parse HEAD~0)"
write_record "$R12a2" "20261004T120000Z-45454545" fact t "" 'newer'
add_record_commit "$R12a2" "20261004T120000Z-45454545"
git_fixture "$R12a2" update-ref refs/remotes/origin/master "$COMM_12A2_OLD"
mkdir -p "$R12a2/_memory/work/goals/g-mast"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 20261004T120000Z-45454545\n' > "$R12a2/_memory/work/goals/g-mast/orchestration-log.md"
pr_run "$R12a2" --plan --only g-mast
grep -qxF 'memory: prune goal g-mast keep:unmerged:20261004T120000Z-45454545' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12a: origin/master lacks record" || report FAIL "case-12a master"

mktemp_dir R12a3
git_init_fixture "$R12a3"
write_record "$R12a3" "$U12" fact t "" 'u'
add_record_commit "$R12a3" "$U12"
COMM_12A3_OLD="$(git_fixture "$R12a3" rev-parse HEAD)"
write_record "$R12a3" "20261005T120000Z-56565656" fact t "" 'head'
add_record_commit "$R12a3" "20261005T120000Z-56565656"
git_fixture "$R12a3" update-ref refs/remotes/origin/main "$(git_fixture "$R12a3" rev-parse HEAD)"
git_fixture "$R12a3" update-ref refs/remotes/origin/master "$COMM_12A3_OLD"
mkdir -p "$R12a3/_memory/work/goals/g-mainwins"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: 20261005T120000Z-56565656\n' > "$R12a3/_memory/work/goals/g-mainwins/orchestration-log.md"
pr_run "$R12a3" --plan --only g-mainwins
grep -qxF 'memory: prune goal g-mainwins would-delete' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12a: origin/main wins over master" || report FAIL "case-12a main wins"

mktemp_dir R12a4
git_init_fixture "$R12a4"
write_record "$R12a4" "$U12" fact t "" 'u'
add_record_commit "$R12a4" "$U12"
mkdir -p "$R12a4/_memory/work/goals/g-head"
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$U12" > "$R12a4/_memory/work/goals/g-head/orchestration-log.md"
pr_run "$R12a4" --plan --only g-head
grep -qxF 'memory: prune goal g-head would-delete' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-12a: no remote refs HEAD decides" || report FAIL "case-12a head only"

# --- case 12b: tracked scratch ---
mktemp_dir R12b
git_init_fixture "$R12b"
TR12="20261101T120000Z-56565656"
write_record "$R12b" "$TR12" fact t "" 't'
add_record_commit "$R12b" "$TR12"
mkdir -p "$R12b/_memory/work/goals/g-tracked"
printf 'scratch\n' > "$R12b/_memory/work/goals/g-tracked/scratch.txt"
git_fixture "$R12b" add -f -- "_memory/work/goals/g-tracked/scratch.txt"
git_fixture "$R12b" commit -qm 'force track work'
printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$TR12" > "$R12b/_memory/work/goals/g-tracked/orchestration-log.md"
pr_run "$R12b" --apply --only g-tracked
grep -qxF 'memory: prune goal g-tracked keep:tracked' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && [[ -d "$R12b/_memory/work/goals/g-tracked" ]] \
  && report PASS "case-12b: keep:tracked survives --apply" || report FAIL "case-12b"

# --- case 13: usage errors ---
mktemp_dir R13
git_init_fixture "$R13"
pr_run "$R13" --plan --apply
[[ "$PR_RC" -eq 2 ]] && grep -qxF 'memory: prune takes --plan or --apply, not both' <<<"$PR_OUT" \
  && report PASS "case-13: plan+apply" || report FAIL "case-13 plan+apply"
pr_run "$R13" --bogus
[[ "$PR_RC" -eq 2 ]] && grep -qxF "memory: unknown flag '--bogus'" <<<"$PR_OUT" \
  && report PASS "case-13: bogus flag" || report FAIL "case-13 bogus"
pr_run "$R13" --goals --goals
[[ "$PR_RC" -eq 2 ]] && grep -qxF "memory: repeated flag '--goals'" <<<"$PR_OUT" \
  && report PASS "case-13: repeated --goals" || report FAIL "case-13 repeat"
set +e
PR_OUT="$(bash "$MEMORY_SH" prune --root "$R13" --only 2>&1)"
PR_RC=$?
set -u
[[ "$PR_RC" -eq 2 ]] && report PASS "case-13: --only without value exit 2" || report FAIL "case-13 only val"

# --- case 14: deletion failure ---
if [[ "$(id -u)" -eq 0 ]]; then
  report SKIP "case-14: deletion failure chmod" "running as root"
else
  mktemp_dir R14
  git_init_fixture "$R14"
  F14A="20261201T120000Z-77777777"
  F14B="20261202T120000Z-88888888"
  write_record "$R14" "$F14A" fact t "" 'a'
  write_record "$R14" "$F14B" fact t "" 'b'
  add_record_commit "$R14" "$F14A"
  add_record_commit "$R14" "$F14B"
  mkdir -p "$R14/_memory/work/goals/g-fail" "$R14/_memory/work/goals/g-ok"
  mkdir -p "$R14/_memory/work/goals/g-fail/locked"
  printf 'x\n' > "$R14/_memory/work/goals/g-fail/locked/x"
  chmod 555 "$R14/_memory/work/goals/g-fail/locked"
  printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$F14A" > "$R14/_memory/work/goals/g-fail/orchestration-log.md"
  printf '# log\n\n### 2026-01-01T10:00-04:00 — ARCHIVED: %s\n' "$F14B" > "$R14/_memory/work/goals/g-ok/orchestration-log.md"
  pr_run "$R14" --apply --goals
  ok=1
grep -q '^memory: prune goal g-fail failed ' <<<"$PR_OUT" || ok=0
  grep -qxF 'memory: prune goal g-ok deleted' <<<"$PR_OUT" || ok=0
  grep -qxF 'memory: prune 1 deleted, 0 kept, 1 failed' <<<"$PR_OUT" || ok=0
  [[ "$PR_RC" -eq 4 && "$ok" -eq 1 ]] && report PASS "case-14: deletion failure exit 4" || report FAIL "case-14"
  chmod -R u+w "$R14/_memory/work/goals/g-fail" 2>/dev/null || true
fi

# --- case 15: idempotence ---
mktemp_dir R15
mk_mixed_fixture "$R15"
pr_run "$R15" --apply
pr_run "$R15" --apply
grep -qxF 'memory: prune 0 deleted, 2 kept, 0 failed' <<<"$PR_OUT" \
  && [[ "$PR_RC" -eq 0 ]] \
  && report PASS "case-15: second --apply idempotent keeps" || report FAIL "case-15"

# --- case 16: usage text ---
help_out="$(bash "$MEMORY_SH" --help 2>&1)"
grep -qxF '  prune  [--plan|--apply] [--goals] [--research] [--only <name>] [--root <dir>]' <<<"$help_out" \
  && grep -q 'backfill|prune' <<<"$help_out" \
  && report PASS "case-16: --help prune line" || report FAIL "case-16"

# --- case 17: wiring ---
ok=1
p2_ln="$(grep -n '^## Phase 2 ' "$FEATURE_TPL" | head -1 | cut -d: -f1)"
p3_ln="$(grep -n '^## Phase 3 ' "$FEATURE_TPL" | head -1 | cut -d: -f1)"
recall_ln="$(grep -n '^\*\*Recall\*\* (once)' "$FEATURE_TPL" | head -1 | cut -d: -f1)"
prune_ln="$(awk -v s="$p2_ln" 'NR>s && /prune --apply/{print NR; exit}' "$FEATURE_TPL")"
[[ -n "$p2_ln" && -n "$prune_ln" && -n "$recall_ln" && -n "$p3_ln" && "$p2_ln" -lt "$prune_ln" && "$prune_ln" -lt "$recall_ln" && "$recall_ln" -lt "$p3_ln" ]] || ok=0
[[ "$(grep -c '^## Prune$' "$MEM_PROTO")" -eq 1 ]] || ok=0
[[ "$(grep -c 'capture / backfill / prune)' "$ORCH_TPL")" -eq 4 ]] || ok=0
[[ "$(grep -c '| \*\*Prune\*\* |' "$ORCH_TPL")" -eq 1 ]] || ok=0
[[ "$(grep -c '^### prune$' "$MEM_README_TPL")" -eq 1 ]] || ok=0
[[ "$ok" -eq 1 ]] && report PASS "case-17: feature/protocol/ORCHESTRATION/README wiring" || report FAIL "case-17"

finish
