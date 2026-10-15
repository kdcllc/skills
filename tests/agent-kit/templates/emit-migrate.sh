#!/usr/bin/env bash
# Guard: skills/agent-kit/bin/emit.sh legacy layout migration (--upgrade path).
# All fixtures under a private TMPDIR; EMIT_SH mutations run on temp copies only.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/emitmigbase.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

CANON_EMIT="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
EMIT_SH="${EMIT_SH:-$CANON_EMIT}"
KIT="$REPO_ROOT/skills/agent-kit"
ANSWERS="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

pass=0; fail=0; skip=0
TMP_BASE=""
CLEANUP=()

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $2${3:+ -- $3}" ;;
    *) fail=$((fail + 1)); echo "FAIL: $2${3:+ -- $3}" >&2 ;;
  esac
}

cleanup() {
  [[ ${#CLEANUP[@]} -gt 0 ]] && rm -rf "${CLEANUP[@]}"
  [[ -n "$TMP_BASE" ]] && rm -rf "$TMP_BASE"
}
trap cleanup EXIT

mktemp_root() {
  local d prefix="${TMP_BASE:-$FIXTURE_TMPDIR}"
  d="$(mktemp -d "$prefix/root.XXXXXX")" || exit 1
  assert_fixture_root "$d" || exit 1
  CLEANUP+=("$d")
  printf '%s' "$d"
}

run_emit() { # root extra-args...
  local root="$1"; shift
  assert_fixture_root "$root" || exit 1
  bash "$EMIT_SH" --root "$root" --kit "$KIT" "$@"
}

git_fixture() {
  assert_fixture_root "$1" || exit 1
  git -C "$1" "${@:2}"
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

git_snap() {
  local root="$1"
  assert_fixture_root "$root" || exit 1
  echo '# ls-files'
  git_fixture "$root" ls-files -s 2>/dev/null | LC_ALL=C sort || true
  echo '# status'
  git_fixture "$root" status --porcelain --ignored 2>/dev/null || true
}

RETIRED_GA_TEST=('_goals/*/orchestration-log.md merge=union' '_goals/LEARNINGS.md merge=union' '_goals/ESCALATIONS.md merge=union')
RETIRED_GI_TEST=('_goals/breaker-state.json')

mk_old_layout() { # root [space_name:0|1] -> 0 ok, 1 fixture setup failed
  local R="$1" sp="${2:-0}" gdir tdir
  assert_fixture_root "$R" || exit 1
  git_fixture "$R" init -q || return 1
  git_fixture "$R" config user.email emit-migrate@test || return 1
  git_fixture "$R" config user.name emit-migrate || return 1
  # .gitattributes: retired lines interleaved with a user line, a blank user line, a CRLF user
  # line and a CRLF copy of the kit's own `_memory/**` line (last line, CRLF-terminated).
  cat > "$R/.gitattributes" <<'EOF'
_goals/*/orchestration-log.md merge=union
_memory/** text eol=lf
user-ga-keep

_goals/LEARNINGS.md merge=union
_goals/ESCALATIONS.md merge=union
*.sh text eol=lf
EOF
  printf 'user-ga-crlf\r\n' >> "$R/.gitattributes"
  printf '_memory/** text eol=lf\r\n' >> "$R/.gitattributes"
  cat > "$R/.gitignore" <<'EOF'
_kit/
_memory/.index/
_memory/raw/
_goals/breaker-state.json

user-gi-keep
EOF
  printf 'user-gi-crlf\r\n' >> "$R/.gitignore"
  # Pre-migration copies (siblings of the root, still under FIXTURE_TMPDIR) for the byte checks.
  cp "$R/.gitattributes" "$R.pre.ga" || return 1
  cp "$R/.gitignore" "$R.pre.gi" || return 1
  if [[ "$sp" -eq 1 ]]; then
    gdir="_goals/my goal"
    tdir="_research/my topic"
  else
    gdir="_goals/g1"
    tdir="_research/t1"
  fi
  # _goals/empty-goal is an empty legacy directory (git cannot track it).
  mkdir -p "$R/$gdir" "$R/$tdir" "$R/_goals/archive" "$R/_goals/empty-goal" || return 1
  printf 'PRIOR_BACKLOG\n' > "$R/_goals/backlog.md"
  printf 'PRIOR_LEARN\n' > "$R/_goals/LEARNINGS.md"
  printf 'goal-one\n' > "$R/$gdir/goal.md"
  printf 'report-one\n' > "$R/$tdir/report.md"
  printf '{"state":"CLOSED"}\n' > "$R/_goals/breaker-state.json"
  printf 'ARCHIVE_KEEP\n' > "$R/_goals/archive/esc.md"
  git_fixture "$R" add .gitattributes .gitignore _goals/backlog.md _goals/LEARNINGS.md "$gdir" "$tdir" _goals/archive/esc.md || return 1
  git_fixture "$R" commit -qm init || return 1
}

user_lines_ga() { grep -E '^user-ga-keep$' "$1/.gitattributes" 2>/dev/null || true; }
user_lines_gi() { grep -E '^user-gi-keep$' "$1/.gitignore" 2>/dev/null || true; }

retired_lines_absent() { # root -> 0 ok
  local R="$1"
  grep -Fq '_goals/*/orchestration-log.md merge=union' "$R/.gitattributes" && return 1
  grep -Fq '_goals/LEARNINGS.md merge=union' "$R/.gitattributes" && return 1
  grep -Fq '_goals/ESCALATIONS.md merge=union' "$R/.gitattributes" && return 1
  grep -Fq '_goals/breaker-state.json' "$R/.gitignore" && return 1
  return 0
}

# Pre-migration file minus whole retired lines, computed here (grep) — independent of emit.sh.
filtered_pre() { # ga|gi root -> stdout
  local kind="$1" R="$2" l f
  local -a args=()
  if [[ "$kind" == ga ]]; then
    f="$R.pre.ga"
    for l in "${RETIRED_GA_TEST[@]}"; do args+=(-e "$l"); done
  else
    f="$R.pre.gi"
    for l in "${RETIRED_GI_TEST[@]}"; do args+=(-e "$l"); done
  fi
  LC_ALL=C grep -v -x -F "${args[@]}" "$f" || true
}

# The filtered pre-migration file must be a byte-for-byte PREFIX of the migrated file
# (original non-retired lines, in original order, with their original bytes and endings).
git_files_byte_prefix_ok() { # root -> 0 ok
  local R="$1" kind exp n file
  for kind in ga gi; do
    exp="$(mktemp "$FIXTURE_TMPDIR/prefix.XXXXXX")" || return 1
    filtered_pre "$kind" "$R" > "$exp"
    [[ -s "$exp" ]] || { rm -f "$exp"; return 1; }
    if [[ "$kind" == ga ]]; then file="$R/.gitattributes"; else file="$R/.gitignore"; fi
    n="$(wc -c < "$exp" | tr -d ' ')"
    if [[ "$(wc -c < "$file" | tr -d ' ')" -lt "$n" ]] || ! head -c "$n" "$file" | cmp -s - "$exp"; then
      rm -f "$exp"
      return 1
    fi
    rm -f "$exp"
  done
  return 0
}

# Exactly one CRLF `_memory/** text eol=lf` line, and each CRLF user line exactly once with its CR.
crlf_exact_ok() { # root -> 0 ok
  local R="$1"
  [[ "$(LC_ALL=C grep -c $'^_memory/\\*\\* text eol=lf\r$' "$R/.gitattributes")" -eq 1 ]] || return 1
  [[ "$(LC_ALL=C grep -c $'^user-ga-crlf\r$' "$R/.gitattributes")" -eq 1 ]] || return 1
  [[ "$(LC_ALL=C grep -c $'^user-gi-crlf\r$' "$R/.gitignore")" -eq 1 ]] || return 1
  return 0
}

# The blank user lines survive in place (one in each file, right after the user line before it).
blank_user_lines_ok() { # root -> 0 ok
  local R="$1"
  [[ "$(grep -c '^$' "$R/.gitattributes")" -eq 1 ]] || return 1
  [[ "$(grep -c '^$' "$R/.gitignore")" -eq 1 ]] || return 1
  [[ "$(awk 'p == "user-ga-keep" { print ($0 == "" ? "blank" : "other"); exit } { p = $0 }' "$R/.gitattributes")" == blank ]] || return 1
  [[ "$(awk 'p == "_memory/raw/" { print ($0 == "" ? "blank" : "other"); exit } { p = $0 }' "$R/.gitignore")" == blank ]] || return 1
  return 0
}

emit_mut_test() { # sed name canon_fn [expect_n] — canon_fn: rc 0 behavior holds, 1 TARGET assertion fails, 2 precondition/emit-rc failure
  local sedscript="$1" name="$2" canon_fn="$3" expect_n="${4:-}"
  local mutsh canon_rc mut_rc changed=""
  mutsh="$(mktemp "${TMPDIR:-/tmp}/emitmut.XXXXXX")"
  sed "$sedscript" "$CANON_EMIT" > "$mutsh"
  chmod +x "$mutsh"
  if [[ -n "$expect_n" ]]; then
    changed="$(diff -u "$CANON_EMIT" "$mutsh" 2>/dev/null | tail -n +3 | grep -c '^-' || true)"
    if [[ "$changed" -ne "$expect_n" ]]; then
      report FAIL "mutation-$name" "sed changed $changed line(s), expected $expect_n"
      rm -f "$mutsh"
      return
    fi
  fi
  if ! bash -n "$mutsh" 2>/dev/null; then
    report FAIL "mutation-$name" "mutant bash -n syntax error"
    rm -f "$mutsh"
    return
  fi
  EMIT_SH="$CANON_EMIT" "$canon_fn"; canon_rc=$?
  EMIT_SH="$mutsh" "$canon_fn"; mut_rc=$?
  rm -f "$mutsh"
  if [[ "$canon_rc" -ne 0 ]]; then
    report FAIL "mutation-$name" "canonical rc=$canon_rc (expected 0; 2 = precondition/unexpected emit rc)"
  elif [[ "$mut_rc" -ne 1 ]]; then
    report FAIL "mutation-$name" "mutant rc=$mut_rc (expected exactly 1 = target assertion failed; 2 = precondition/unexpected emit rc, 0 = mutation not caught)"
  else
    report PASS "mutation-$name: canonical rc=0, mutant rc=1 (target assertion failed; bash -n ok${expect_n:+, sed changed exactly $changed line(s)})"
  fi
}

TMP_BASE="$FIXTURE_TMPDIR"
CLEANUP+=("$FIXTURE_TMPDIR")

# --- fixture-root helper fails closed (negative controls) ---
# Each probe sources the helper in a SUBSHELL (an `exit` inside it ends only the subshell) with a
# hostile REPO_ROOT / FIXTURE_TMPDIR pair. The helper only reads paths; nothing is written.
fixture_root_src_rc() { # REPO_ROOT FIXTURE_TMPDIR -> rc of sourcing the helper
  ( REPO_ROOT="$1"; FIXTURE_TMPDIR="$2"; . "$HERE/../lib/fixture-root.sh" ) >/dev/null 2>&1
}
fr_expect_fail() { # label repo tmpdir
  local rc
  fixture_root_src_rc "$2" "$3"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    report PASS "fixture-root: sourcing fails closed for $1 (rc=$rc)"
  else
    report FAIL "fixture-root: $1 was accepted" "rc=0"
  fi
}
fr_expect_fail 'empty FIXTURE_TMPDIR' "$REPO_ROOT" ""
fr_expect_fail "FIXTURE_TMPDIR='/'" "$REPO_ROOT" "/"
fr_expect_fail 'FIXTURE_TMPDIR = repository root' "$REPO_ROOT" "$REPO_ROOT"
fr_expect_fail 'FIXTURE_TMPDIR under the repository root' "$REPO_ROOT" "$REPO_ROOT/tests"
fr_expect_fail 'relative FIXTURE_TMPDIR' "$REPO_ROOT" "relative/path"
fr_expect_fail 'missing FIXTURE_TMPDIR' "$REPO_ROOT" "$FIXTURE_TMPDIR/does-not-exist"
fr_expect_fail 'empty REPO_ROOT' "" "$FIXTURE_TMPDIR"
fixture_root_src_rc "$REPO_ROOT" "$FIXTURE_TMPDIR"; fr_rc=$?
[[ "$fr_rc" -eq 0 ]] \
  && report PASS "fixture-root: control — private TMPDIR outside the repo sources cleanly (rc=0)" \
  || report FAIL "fixture-root: valid private TMPDIR was rejected" "rc=$fr_rc"
# The resolver never falls back to the cwd; inherited *_ABS values are ignored; repo root refused.
fr_probe="$( ( REPO_ROOT_ABS=/poison; FIXTURE_TMPDIR_ABS=/
    REPO_ROOT="$REPO_ROOT"; FIXTURE_TMPDIR="$FIXTURE_TMPDIR"
    . "$HERE/../lib/fixture-root.sh" || exit 9
    resolved="$(_fixture_root_resolve "")" && echo "resolve-empty-ok:$resolved"
    [[ "$REPO_ROOT_ABS" != /poison && "$FIXTURE_TMPDIR_ABS" == "$(cd "$FIXTURE_TMPDIR" && pwd -P)" ]] || echo "abs-inherited"
    assert_fixture_root "$REPO_ROOT" 2>/dev/null && echo "repo-root-accepted"
    assert_fixture_root "" 2>/dev/null && echo "empty-accepted"
    echo done ) 2>&1 )"
[[ "$fr_probe" == done ]] \
  && report PASS "fixture-root: _fixture_root_resolve '' fails, inherited *_ABS overridden, repo root and empty root refused" \
  || report FAIL "fixture-root: resolver/assert probe" "$fr_probe"

# --- dry-run writes nothing ---
assert_dry_run() {
  local R="$1" before after gs0 gs1
  mk_old_layout "$R" || return 1
  before="$(snap_tree "$R")"
  gs0="$(git_snap "$R")"
  set +e
  out="$(run_emit "$R" --answers "$ANSWERS" --dry-run 2>&1)"
  rc=$?
  after="$(snap_tree "$R")"
  gs1="$(git_snap "$R")"
  grep -q 'migrate _goals/backlog.md -> _memory/loop/backlog.md' <<<"$out" \
    && grep -q 'migrate _goals/g1 -> _memory/work/goals/g1' <<<"$out" \
    && grep -q 'migrate _goals/empty-goal -> _memory/work/goals/empty-goal' <<<"$out" \
    && [[ "$before" == "$after" && "$gs0" == "$gs1" ]]
}
R="$(mktemp_root)"
if assert_dry_run "$R"; then
  report PASS "dry-run: migrate actions listed, tree + git snapshot unchanged"
else
  report FAIL "dry-run snapshot" "rc=$rc"
fi

assert_empty_root() { # rc 0 guard holds, 1 guard missing (target), 2 precondition failed
  local d rc out files_before files_after
  d="$(mktemp -d "$FIXTURE_TMPDIR/emptycwd.XXXXXX")" || return 2
  assert_fixture_root "$d" || return 2
  files_before="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  set +e
  out="$( ( cd "$d" && bash "$EMIT_SH" --root "" --kit "$KIT" --answers "$ANSWERS" 2>&1 ) )"
  rc=$?
  files_after="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$rc" -eq 2 ]] && grep -q 'non-empty directory path' <<<"$out" \
    && [[ "$files_before" -eq "$files_after" ]]; then
    return 0
  fi
  return 1
}
assert_empty_root && report PASS "empty --root: exit 2, usage message, writes nothing under temp cwd" \
  || report FAIL "empty --root guard"

# --- real migration ---
assert_migrate_run() {
  local R="$1" sp="${2:-0}" gname tname out rc
  mk_old_layout "$R" "$sp" || return 1
  if [[ "$sp" -eq 1 ]]; then gname="my goal"; tname="my topic"; else gname="g1"; tname="t1"; fi
  set +e
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"
  rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  grep -q 'migrated [1-9]' <<<"$out" || return 1
  grep -q 'emit: moved legacy _goals/ and _research/ into _memory/' <<<"$out" || return 1
  [[ -f "$R/_memory/loop/backlog.md" ]] && grep -qxF 'PRIOR_BACKLOG' "$R/_memory/loop/backlog.md" || return 1
  [[ -f "$R/_memory/work/goals/$gname/goal.md" ]] || return 1
  [[ -f "$R/_memory/work/research/$tname/report.md" ]] || return 1
  [[ -f "$R/_memory/loop/breaker-state.json" ]] || return 1
  [[ ! -d "$R/_goals" && ! -d "$R/_research" ]] || return 1
  grep -qxF 'user-ga-keep' "$R/.gitattributes" || return 1
  grep -qxF 'user-gi-keep' "$R/.gitignore" || return 1
  grep -q '_goals/LEARNINGS.md merge=union' "$R/.gitattributes" && return 1
  grep -q '_goals/breaker-state.json' "$R/.gitignore" && return 1
  git_fixture "$R" ls-files --error-unmatch "_memory/loop/backlog.md" >/dev/null 2>&1 || return 1
  git_fixture "$R" ls-files --error-unmatch "_memory/loop/archive/esc.md" >/dev/null 2>&1 || return 1
  git_fixture "$R" ls-files -- "_memory/work/goals/$gname" 2>/dev/null | grep -q . && return 1
  git_fixture "$R" ls-files -- "_memory/work/research/$tname" 2>/dev/null | grep -q . && return 1
  cmp -s <(user_lines_ga "$R") <(printf '%s\n' 'user-ga-keep') || return 1
  cmp -s <(user_lines_gi "$R") <(printf '%s\n' 'user-gi-keep') || return 1
  retired_lines_absent "$R" || return 1
  crlf_exact_ok "$R" || return 1
  blank_user_lines_ok "$R" || return 1
  git_files_byte_prefix_ok "$R" || return 1
  # empty legacy dir: moved (not dropped), untracked (git cannot hold it), legacy root gone
  [[ -d "$R/_memory/work/goals/empty-goal" ]] || return 1
  [[ -z "$(ls -A "$R/_memory/work/goals/empty-goal")" ]] || return 1
  [[ ! -e "$R/_goals" ]] || return 1
  [[ "$(tail -c 1 "$R/.gitattributes" | od -An -tu1 | tr -d ' ')" == "10" ]] || return 1
  grep -q '^user-ga-keep$' "$R/.gitattributes" || return 1
  return 0
}
R="$(mktemp_root)"
if assert_migrate_run "$R" 0; then
  report PASS "migrate: paths, untrack goals/research, archive tracked, hint on stderr"
  retired_lines_absent "$R" && report PASS "migrate: all four retired git lines absent" || report FAIL "retired lines absent"
  cmp -s <(user_lines_ga "$R") <(printf '%s\n' 'user-ga-keep') \
    && cmp -s <(user_lines_gi "$R") <(printf '%s\n' 'user-gi-keep') \
    && report PASS "migrate: user lines present once" || report FAIL "user git lines cmp"
  git_files_byte_prefix_ok "$R" \
    && report PASS "migrate: pre-migration files minus retired lines (grep-filtered) cmp equal to the migrated .gitattributes/.gitignore prefix" \
    || report FAIL "non-circular byte prefix check"
  crlf_exact_ok "$R" \
    && report PASS "migrate: exactly one CRLF '_memory/** text eol=lf' line; CRLF user lines (gitattributes + gitignore) kept once, byte-identical" \
    || report FAIL "exact CRLF lines"
  blank_user_lines_ok "$R" \
    && report PASS "migrate: blank user lines kept in place (.gitattributes + .gitignore)" \
    || report FAIL "blank user lines kept"
  [[ -d "$R/_memory/work/goals/empty-goal" && ! -e "$R/_goals" && ! -e "$R/_research" ]] \
    && [[ -z "$(git_fixture "$R" ls-files -- _memory/work/goals/empty-goal)" ]] \
    && report PASS "migrate: empty legacy dir _goals/empty-goal moved to _memory/work/goals/empty-goal (untracked), _goals and _research gone" \
    || report FAIL "empty legacy dir handling"
else
  report FAIL "migrate run"
fi

# --- rerun no-op ---
RERUN_SNAP="$(snap_tree "$R")"
out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"; rc=$?
[[ "$(snap_tree "$R")" == "$RERUN_SNAP" ]] \
  && grep -q 'migrated 0' <<<"$out" && [[ "$rc" -eq 0 ]] \
  && report PASS "rerun: migrated 0, tree snapshot unchanged" \
  || report FAIL "rerun no-op" "rc=$rc out=$out"

# --- conflict exit 4, nothing moved ---
assert_conflict() {
  local R="$1"
  mk_old_layout "$R" || return 1
  mkdir -p "$R/_memory/work/goals/g1"
  printf 'blocker\n' > "$R/_memory/work/goals/g1/goal.md"
  set +e
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"
  rc=$?
  [[ "$rc" -eq 4 ]] && grep -q 'blocked _memory/work/goals/g1' <<<"$out" \
    && [[ -d "$R/_goals/g1" ]] && [[ -f "$R/_goals/g1/goal.md" ]] \
    && [[ -f "$R/_goals/backlog.md" ]] && [[ ! -f "$R/_memory/loop/backlog.md" ]] \
    && ! grep -q 'backfill --plan' <<<"$out" \
    && ! grep -q 'legacy _goals/g1 left in place' <<<"$out"
}
R="$(mktemp_root)"
assert_conflict "$R" && report PASS "conflict: exit 4, all legacy sources unmoved, no loop backlog, hint matrix (blocked only)" \
  || report FAIL "conflict blocked"

# --- force keeps both ---
assert_force() {
  local R="$1" out rc
  mk_old_layout "$R" || return 1
  mkdir -p "$R/_memory/work/goals/g1"
  printf 'existing-target\n' > "$R/_memory/work/goals/g1/goal.md"
  set +e
  out="$(run_emit "$R" --answers "$ANSWERS" --force --upgrade 2>&1)"
  rc=$?
  [[ "$rc" -eq 0 ]] \
    && grep -qxF 'existing-target' "$R/_memory/work/goals/g1/goal.md" \
    && grep -qxF 'goal-one' "$R/_goals/g1/goal.md" \
    && [[ -f "$R/_memory/loop/backlog.md" ]] \
    && grep -q 'backfill --plan' <<<"$out" \
    && grep -q 'legacy _goals/g1 left in place' <<<"$out"
}
R="$(mktemp_root)"
assert_force "$R" && report PASS "--force: hint matrix (backfill hint + left-in-place warning), both copies kept" \
  || report FAIL "--force conflict"

R="$(mktemp_root)"; mk_old_layout "$R" || report FAIL "hint matrix fixture setup"
out_clean="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)" || true
grep -q 'backfill --plan' <<<"$out_clean" \
  && ! grep -q 'legacy _goals/g1 left in place' <<<"$out_clean" \
  && report PASS "hint matrix: clean migrate emits backfill hint only" \
  || report FAIL "hint matrix clean migrate"

# --- spaces in names ---
R="$(mktemp_root)"
assert_migrate_run "$R" 1 && report PASS "paths with spaces in goal/research names" || report FAIL "space paths"

# --- non-git root (plain mv) ---
assert_nogit() {
  local R out rc
  R="$(mktemp_root)"
  mkdir -p "$R/_goals/g1" "$R/_research/t1"
  printf 'b\n' > "$R/_goals/backlog.md"
  printf 'g\n' > "$R/_goals/g1/goal.md"
  printf 't\n' > "$R/_research/t1/report.md"
  set +e
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"
  rc=$?
  [[ "$rc" -eq 0 ]] && [[ -f "$R/_memory/loop/backlog.md" ]] && grep -qxF 'b' "$R/_memory/loop/backlog.md" \
    && [[ -f "$R/_memory/work/goals/g1/goal.md" ]] \
    && [[ -f "$R/_memory/work/research/t1/report.md" ]] && grep -qxF 't' "$R/_memory/work/research/t1/report.md" \
    && [[ ! -e "$R/_goals" ]] && [[ ! -e "$R/_research" ]]
}
assert_nogit && report PASS "non-git root: plain mv migration" || report FAIL "non-git root"

# --- backlog seed preserved on upgrade emit ---
assert_seed() {
  local R="$1" out rc h
  mk_old_layout "$R" || return 1
  printf '\nSEED_EDIT\n' >> "$R/_goals/backlog.md"
  h="$(sha256sum "$R/_goals/backlog.md" | awk '{print $1}')"
  run_emit "$R" --answers "$ANSWERS" --force --upgrade >/dev/null 2>&1 || return 1
  [[ "$(sha256sum "$R/_memory/loop/backlog.md" | awk '{print $1}')" == "$h" ]]
}
R="$(mktemp_root)"
assert_seed "$R" && report PASS "backlog seed content preserved across migration emit" || report FAIL "seed preserved"

# --- mutations ---
# Each mut_* function (the canonical assertion for one behavior) returns:
#   0  the behavior holds
#   1  ONLY when the TARGET assertion fails (the behavior is broken)
#   2  a precondition or an unexpected emit rc failed (never counts as "caught")
# emit_mut_test requires canonical rc 0 and mutant rc exactly 1.
mut_fixture() { # outvar -> 0 ok, 2 fixture setup failed
  local _mr
  _mr="$(mktemp_root)" || return 2
  mk_old_layout "$_mr" || return 2
  printf -v "$1" '%s' "$_mr"
}

mut_dry_run() {
  local R before rc
  mut_fixture R || return 2
  before="$(snap_tree "$R")"
  run_emit "$R" --answers "$ANSWERS" --dry-run >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  [[ "$(snap_tree "$R")" == "$before" ]] && return 0
  return 1
}
emit_mut_test '/^  if \[ "\$DRY_RUN" -eq 1 \]; then$/,/^  apply_upgrade_migrations$/ s/^    exit 0$/    : # mut-dry-fallthrough/' \
  'dry-run-no-op' mut_dry_run 1

mut_conflict_block() {
  local R rc
  mut_fixture R || return 2
  mkdir -p "$R/_memory/work/goals/g1" || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  case "$rc" in 0 | 4) ;; *) return 2 ;; esac
  [[ "$rc" -eq 4 ]] && [[ -d "$R/_goals/g1" ]] && [[ -f "$R/_goals/backlog.md" ]] && return 0
  return 1
}
emit_mut_test '/^plan_upgrade_migrations() {/,/^}/ s/&& \[ "\$FORCE" -eq 0 \]/\&\& [ 1 -eq 0 ]/' \
  'conflict-exit-4' mut_conflict_block 1

mut_hint() {
  local R out rc
  mut_fixture R || return 2
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  grep -q 'backfill --plan' <<<"$out" && return 0
  return 1
}
emit_mut_test 's/run _kit\/memory.sh backfill --plan to archive/MUTATED/' \
  'stderr-hint' mut_hint 1

mut_retired() {
  local R rc
  mut_fixture R || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  retired_lines_absent "$R" && return 0
  return 1
}
emit_mut_test '/^strip_retired_git_lines_bytes() {/,/^}/ s/if is_retired_git_line/if false \&\& is_retired_git_line/' \
  'retired-lines-removed' mut_retired 1

mut_migrated_count() {
  local R out rc
  mut_fixture R || return 2
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  grep -q 'migrated [1-9]' <<<"$out" && return 0
  return 1
}
emit_mut_test 's/MIGRATED_N=\$((MIGRATED_N + 1))/:/' \
  'summary-migrated-n' mut_migrated_count 1

mut_git_mv_tracked() {
  local R rc
  mut_fixture R || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  git_fixture "$R" ls-files --error-unmatch "_memory/loop/backlog.md" >/dev/null 2>&1 && return 0
  return 1
}
emit_mut_test 's/git -C "\$ROOT" mv -- "\$src" "\$dst"/mv -- "$ROOT\/$src" "$ROOT\/$dst"/' \
  'git-mv-tracked' mut_git_mv_tracked 1

mut_untrack_work() {
  local R rc
  mut_fixture R || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  git_fixture "$R" ls-files -- "_memory/work/goals/g1" 2>/dev/null | grep -q . && return 1
  return 0
}
emit_mut_test '/apply_upgrade_migrations() {/,/^}/ s/git -C "\$ROOT" rm -r --cached --quiet -- "\$dst"/:# git rm cached/' \
  'untrack-work-goals' mut_untrack_work 1

mut_crlf_bytes() {
  local R rc
  mut_fixture R || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  crlf_exact_ok "$R" && return 0
  return 1
}
emit_mut_test 's@      printf '"'"'%s\\n'"'"' "\$line"@      printf "%s\\n" "${line//\$'"'"'\\r'"'"'/}"@' \
  'crlf-line-endings' mut_crlf_bytes 1

mut_rerun_snap() {
  local R s1 s2 rc
  mut_fixture R || return 2
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  s1="$(snap_tree "$R")"
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  s2="$(snap_tree "$R")"
  [[ "$s1" == "$s2" ]] && return 0
  return 1
}
emit_mut_test '/git_bytes_append_eol_into "\$out" eol/,/printf '"'"'%s'"'"' "\$out"/ s/printf '"'"'%s'"'"' "\$out"/printf "%s# rerun-mut-tag\\n" "$out"/' \
  'rerun-no-op-snapshot' mut_rerun_snap 1

mut_force_keep_both() {
  local R out rc
  mut_fixture R || return 2
  mkdir -p "$R/_memory/work/goals/g1" || return 2
  printf 'existing-target\n' > "$R/_memory/work/goals/g1/goal.md" || return 2
  out="$(run_emit "$R" --answers "$ANSWERS" --force --upgrade 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  grep -q 'legacy _goals/g1 left in place' <<<"$out" && [[ -f "$R/_goals/g1/goal.md" ]] && return 0
  return 1
}
emit_mut_test 's/record_warn_line "legacy \$src left in place/# record_warn_line "legacy \$src left in place/' \
  'force-keep-both-warn' mut_force_keep_both 1

mut_empty_pairs_guard() {
  local R out rc
  mut_fixture R || return 2
  out="$(run_emit "$R" --answers "$ANSWERS" --upgrade 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  grep -q 'migrated [1-9]' <<<"$out" && return 0
  return 1
}
emit_mut_test '/^collect_upgrade_migrate_pairs() {/,/^}/ s/UPGRADE_MIGRATE_PAIRS=\(\)/UPGRADE_MIGRATE_PAIRS=() ; return 0 # mut/' \
  'empty-pairs-guard' mut_empty_pairs_guard 1

# write_seed's existing-file branch must keep the migrated backlog (the mutant overwrites it).
mut_seed_keeps_existing_backlog() {
  local R h rc
  mut_fixture R || return 2
  printf '\nSEED_TAIL\n' >> "$R/_goals/backlog.md" || return 2
  h="$(sha256sum "$R/_goals/backlog.md" | awk '{print $1}')"
  run_emit "$R" --answers "$ANSWERS" --upgrade >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || return 2
  [[ -f "$R/_memory/loop/backlog.md" ]] || return 2
  [[ "$(sha256sum "$R/_memory/loop/backlog.md" | awk '{print $1}')" == "$h" ]] && return 0
  return 1
}
emit_mut_test '/write_seed() {/,/^}/ s/SEEDS_KEPT=\$((SEEDS_KEPT + 1))/printf "%s" "CORRUPT" > "$dest"; return 0 # mut/' \
  'seed-keeps-existing-backlog' mut_seed_keeps_existing_backlog 1

mut_empty_root_check() { assert_empty_root; }
emit_mut_test '/die 2 "--root requires a non-empty directory path"/d' \
  'empty-root-exit-2' mut_empty_root_check 1

case "$FIXTURE_TMPDIR" in
  "$REPO_ROOT"|"$REPO_ROOT"/*)
    report FAIL "(leak) FIXTURE_TMPDIR must not be under REPO_ROOT"
    ;;
  *)
    report PASS "(leak) FIXTURE_TMPDIR under private TMPDIR (not repo root)"
    ;;
esac

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
[[ "$fail" -eq 0 ]]
