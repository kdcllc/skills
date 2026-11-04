#!/usr/bin/env bash
# Guard: fixture git can never write a caller's repository.
#
# Proves that tests/agent-kit/lib/fixture-root.sh (scrub of repo-locating and config-redirecting
# git variables, global/system config isolation, fixture identity from the environment, and
# assert_fixture_repo) keeps fixture git away from a caller's repository. Every git variable this
# suite exports points at a throwaway "caller" repo under its own mktemp dir; it never touches the
# real checkout (no git variable, linked worktree or config write ever targets it).
#
# Cases (GIT_ISOLATION_ONLY=<id> runs one; unset runs all):
#   a  the shared helpers under each of six variable sets (GIT_DIR; GIT_DIR+GIT_WORK_TREE;
#      GIT_INDEX_FILE; GIT_CONFIG; GIT_COMMON_DIR; GIT_OBJECT_DIRECTORY): caller snapshot unchanged,
#      fixture has one commit with the fixture identity, and the old `config user.email` write lands
#      in the fixture.                                                              (6 PASS)
#   b  memory-prune end to end (incl. case 11c) with GIT_DIR, then GIT_CONFIG exported. (2 PASS)
#   c  failed fixture init in a read-only dir inside an enclosing repo (cd-style helper), its
#      positive control, and a linked-worktree root (shared config).                (3 PASS)
#   d  one progress-line driver case end to end with GIT_DIR exported. Case "g" (failed verdict)
#      is used because it builds a make_sandbox fixture, runs one loop iteration and its stub
#      makes a commit, in about a second.                                           (1 PASS)
#   e  HOME / XDG_CONFIG_HOME global config is neither read nor written.            (1 PASS)
#   f  static scan: no `config user.` line, and every file with a non-comment git init site (git, or a
#      git-named wrapper such as git_fixture/rc_git_at) asserts the repo.         (2 PASS)
#
# Overrides (defaults in parentheses):
#   GIT_ISOLATION_LIB             library to source ($REPO_ROOT/tests/agent-kit/lib/fixture-root.sh)
#   GIT_ISOLATION_PRUNE_SUITE     case b suite ($REPO_ROOT/tests/agent-kit/templates/memory-prune.sh)
#   GIT_ISOLATION_PROGRESS_SUITE  case d suite ($REPO_ROOT/tests/agent-kit/templates/progress-line.sh)
#   GIT_ISOLATION_SCAN_ROOT       case f scan root ($REPO_ROOT/tests/agent-kit)
#   GIT_ISOLATION_ONLY            a|b|c|d|e|f (unset = all)
#
# Prerequisites: git; a timeout or gtimeout binary for case d (case d reports SKIP without one).
# Output: PASS: <name> / FAIL: <name> -- <detail> (stderr) / SKIP: <name> -- <reason>, then
# PASS: <p>   FAIL: <f>   SKIP: <s>. Exit 1 when any check fails. bash 3.2 safe.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akgitiso.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"

pass=0
fail=0
skip=0

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); printf 'PASS: %s\n' "$2" ;;
    SKIP) skip=$((skip + 1)); printf 'SKIP: %s%s\n' "$2" "${3:+ -- $3}" ;;
    *) fail=$((fail + 1)); printf 'FAIL: %s -- %s\n' "$2" "${3:-}" >&2 ;;
  esac
}

cleanup() {
  chmod -R u+w "$FIXTURE_TMPDIR" 2>/dev/null
  rm -rf "$FIXTURE_TMPDIR"
}
trap cleanup EXIT

summary() {
  printf 'PASS: %s   FAIL: %s   SKIP: %s\n' "$pass" "$fail" "$skip"
}

# The suite's own environment must be clean before it reads any snapshot: an inherited variable
# must never redirect the suite's git, independent of what the library under test does.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

LIB="${GIT_ISOLATION_LIB:-$REPO_ROOT/tests/agent-kit/lib/fixture-root.sh}"
PRUNE_SUITE="${GIT_ISOLATION_PRUNE_SUITE:-$REPO_ROOT/tests/agent-kit/templates/memory-prune.sh}"
PROGRESS_SUITE="${GIT_ISOLATION_PROGRESS_SUITE:-$REPO_ROOT/tests/agent-kit/templates/progress-line.sh}"
SCAN_ROOT="${GIT_ISOLATION_SCAN_ROOT:-$REPO_ROOT/tests/agent-kit}"
ONLY="${GIT_ISOLATION_ONLY:-}"

if [[ ! -f "$LIB" ]]; then
  report FAIL "setup: library" "missing $LIB"
  summary
  exit 1
fi
# shellcheck source=../lib/fixture-root.sh
. "$LIB"

# Parent git never climbs out of the temp tree.
export GIT_CEILING_DIRECTORIES="$FIXTURE_TMPDIR_ABS"

# sha256 of a file (empty output when missing).
sha() {
  [[ -f "$1" ]] || { printf 'missing'; return 0; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# snap <repo>: config sha, HEAD, index sha, refs, commit count and object counts of a repository.
snap() {
  local d="$1"
  printf 'config=%s\n' "$(sha "$d/.git/config")"
  printf 'headfile=%s\n' "$(cat "$d/.git/HEAD" 2>/dev/null)"
  printf 'head=%s\n' "$(git -C "$d" rev-parse HEAD 2>&1)"
  printf 'index=%s\n' "$(sha "$d/.git/index")"
  printf 'refs=%s\n' "$(git -C "$d" for-each-ref 2>&1 | paste -sd'|' -)"
  printf 'commits=%s\n' "$(git -C "$d" rev-list --all --count 2>&1)"
  printf 'objects=%s\n' "$(git -C "$d" count-objects -v 2>&1 | grep -E '^(count|in-pack):' | paste -sd'|' -)"
}

# snap_diff <before> <after> -> first differing lines (empty when equal)
snap_diff() {
  [[ "$1" == "$2" ]] && return 0
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep -E '^[<>]' | head -4 | paste -sd';' -
}

# cenv: run a command with the fixture-identity / config-isolation variables removed, so the
# library under test (not this suite's own environment) is what provides them.
cenv() {
  env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_GLOBAL -u GIT_CEILING_DIRECTORIES "$@"
}

FIXTURE_IDENT='agent-kit-fixture <fixture@agent-kit.invalid>'
SUMMARY_RE='^PASS: [0-9]+   FAIL: [0-9]+   SKIP: [0-9]+$'

# --- caller repos (throwaway; every git variable set below points at one of these) -----------
# One fresh caller per variable set / run, so a write leaked by one run cannot hide a leak in the next.
new_caller() { # name -> sets CALLER
  CALLER="$FIXTURE_TMPDIR_ABS/callers/$1"
  case "$CALLER" in
    "$FIXTURE_TMPDIR_ABS"/*) ;;
    *)
      report FAIL "setup: caller repo" "caller path $CALLER is not under $FIXTURE_TMPDIR_ABS"
      summary
      exit 1
      ;;
  esac
  mkdir -p "$CALLER" || exit 1
  git -C "$CALLER" init -q || { report FAIL "setup: caller repo" "git init failed"; summary; exit 1; }
  printf 'caller\n' > "$CALLER/README"
  git -C "$CALLER" add README
  git -C "$CALLER" -c user.email=caller@example.invalid -c user.name=caller commit -qm caller-initial \
    || { report FAIL "setup: caller repo" "initial commit failed"; summary; exit 1; }
  if [[ "$(git -C "$CALLER" rev-parse --absolute-git-dir)" != "$CALLER/.git" ]]; then
    report FAIL "setup: caller repo" "caller git dir does not resolve to $CALLER/.git"
    summary
    exit 1
  fi
}

want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

# --- case a ---------------------------------------------------------------------------------
CHILD_A="$FIXTURE_TMPDIR_ABS/child-a.sh"
cat > "$CHILD_A" <<'CHILD'
set -u
REPO_ROOT="$GI_REPO_ROOT"
FIXTURE_TMPDIR="$GI_FT"
. "$GI_LIB" || exit 9
fx="$FIXTURE_TMPDIR/fx"
mkdir -p "$fx"
git -C "$fx" init -q
assert_fixture_repo "$fx"
printf 'assert_rc=%s\n' "$?"
printf 'x\n' > "$fx/f"
git -C "$fx" add f
git -C "$fx" commit -qm c
git -C "$fx" config user.email t@t
CHILD

case_a() {
  local ids="GIT_DIR GIT_DIR+GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG GIT_COMMON_DIR GIT_OBJECT_DIRECTORY"
  local id n=0 ft fx before after d detail count ident local_email
  local assign
  for id in $ids; do
    n=$((n + 1))
    new_caller "a$n"
    case "$id" in
      GIT_DIR) assign=("GIT_DIR=$CALLER/.git") ;;
      GIT_DIR+GIT_WORK_TREE) assign=("GIT_DIR=$CALLER/.git" "GIT_WORK_TREE=$CALLER") ;;
      GIT_INDEX_FILE) assign=("GIT_INDEX_FILE=$CALLER/.git/index") ;;
      GIT_CONFIG) assign=("GIT_CONFIG=$CALLER/.git/config") ;;
      GIT_COMMON_DIR) assign=("GIT_COMMON_DIR=$CALLER/.git") ;;
      *) assign=("GIT_OBJECT_DIRECTORY=$CALLER/.git/objects") ;;
    esac
    ft="$FIXTURE_TMPDIR_ABS/a$n"
    mkdir -p "$ft"
    fx="$ft/fx"
    before="$(snap "$CALLER")"
    cenv "${assign[@]}" GI_REPO_ROOT="$REPO_ROOT" GI_FT="$ft" GI_LIB="$LIB" \
      bash "$CHILD_A" > "$ft/out" 2> "$ft/err"
    after="$(snap "$CALLER")"
    detail=""
    d="$(snap_diff "$before" "$after")"
    [[ -z "$d" ]] || detail="$detail caller changed ($d);"
    count="$(git -C "$fx" rev-list --all --count 2>/dev/null)"
    [[ "$count" == "1" ]] || detail="$detail fixture commit count '${count}' != 1;"
    ident="$(git -C "$fx" log -1 --format='%an <%ae>|%cn <%ce>' 2>/dev/null)"
    [[ "$ident" == "$FIXTURE_IDENT|$FIXTURE_IDENT" ]] || detail="$detail fixture author/committer '${ident}';"
    local_email="$(git -C "$fx" config --local user.email 2>/dev/null)"
    [[ "$local_email" == "t@t" ]] || detail="$detail fixture local config user.email '${local_email}' != t@t (write did not land in fixture);"
    if [[ -z "$detail" ]]; then
      report PASS "a: helpers under $id leave the caller untouched"
    else
      report FAIL "a: helpers under $id" "${detail# }"
    fi
  done
}

# --- case b ---------------------------------------------------------------------------------
case_b() {
  local n=0 spec label assign before after d rc out detail tmp
  for spec in GIT_DIR GIT_CONFIG; do
    n=$((n + 1))
    new_caller "b$n"
    case "$spec" in
      GIT_DIR) spec="GIT_DIR=$CALLER/.git" ;;
      *) spec="GIT_CONFIG=$CALLER/.git/config" ;;
    esac
    label="b: memory-prune with ${spec%%=*} exported"
    if [[ ! -f "$PRUNE_SUITE" ]]; then
      report FAIL "$label" "missing suite $PRUNE_SUITE"
      continue
    fi
    tmp="$FIXTURE_TMPDIR_ABS/b$n"
    mkdir -p "$tmp"
    before="$(snap "$CALLER")"
    cenv "$spec" TMPDIR="$tmp" bash "$PRUNE_SUITE" > "$tmp/out" 2> "$tmp/err"
    rc=$?
    after="$(snap "$CALLER")"
    detail=""
    [[ "$rc" -eq 0 ]] || detail="$detail suite exit $rc;"
    out="$(grep -E "$SUMMARY_RE" "$tmp/out" | tail -1)"
    case "$out" in
      *"   FAIL: 0   "*) ;;
      *) detail="$detail summary '${out:-none}' lacks FAIL: 0 ($(grep -c '^FAIL' "$tmp/err") FAIL lines);" ;;
    esac
    d="$(snap_diff "$before" "$after")"
    [[ -z "$d" ]] || detail="$detail caller changed ($d);"
    if [[ -z "$detail" ]]; then
      report PASS "$label (exit 0, FAIL: 0, caller unchanged)"
    else
      report FAIL "$label" "${detail# }"
    fi
  done
}

# --- case c ---------------------------------------------------------------------------------
CHILD_C="$FIXTURE_TMPDIR_ABS/child-c.sh"
cat > "$CHILD_C" <<'CHILD'
set -u
REPO_ROOT="$GI_REPO_ROOT"
FIXTURE_TMPDIR="$GI_FT"
. "$GI_LIB" || exit 9
cd "$GI_DIR" || exit 4
git init -q 2>/dev/null
assert_fixture_repo "$GI_DIR" || exit 3
git add -A
git commit -qm init
CHILD

CHILD_C_WT="$FIXTURE_TMPDIR_ABS/child-c-wt.sh"
cat > "$CHILD_C_WT" <<'CHILD'
set -u
REPO_ROOT="$GI_REPO_ROOT"
FIXTURE_TMPDIR="$GI_FT"
. "$GI_LIB" || exit 9
assert_fixture_repo "$GI_DIR" || exit 3
git -C "$GI_DIR" config user.email t@t
CHILD

case_c() {
  local ft="$FIXTURE_TMPDIR_ABS/c" e d d2 m w before after dd detail rc nerr first count
  mkdir -p "$ft" || return
  # -- failed init in a read-only dir inside an enclosing repo
  e="$ft/E"; d="$e/D"; d2="$e/D2"
  mkdir -p "$e" "$d" "$d2"
  git -C "$e" init -q
  printf 'enclosing\n' > "$e/README"
  git -C "$e" add README
  git -C "$e" commit -qm enclosing
  printf 'x\n' > "$d2/f"
  chmod 555 "$d"
  if ( : > "$d/probe" ) 2>/dev/null; then
    rm -f "$d/probe"
    report SKIP "c: failed fixture init" "cannot make a read-only directory here (running as a user that ignores chmod)"
    report SKIP "c: positive control" "same reason"
  else
    before="$(snap "$e")"
    cenv GI_REPO_ROOT="$REPO_ROOT" GI_FT="$FIXTURE_TMPDIR_ABS" GI_LIB="$LIB" GI_DIR="$d" \
      bash "$CHILD_C" > "$ft/d.out" 2> "$ft/d.err"
    rc=$?
    after="$(snap "$e")"
    detail=""
    [[ "$rc" -eq 3 ]] || detail="$detail exit $rc != 3;"
    nerr="$(wc -l < "$ft/d.err" | tr -d ' ')"
    first="$(head -1 "$ft/d.err")"
    [[ "$nerr" == "1" && "$first" == "assert_fixture_repo: "* ]] \
      || detail="$detail stderr not exactly one 'assert_fixture_repo: ' line ($nerr lines, first '${first}');"
    dd="$(snap_diff "$before" "$after")"
    [[ -z "$dd" ]] || detail="$detail enclosing repo changed ($dd);"
    if [[ -z "$detail" ]]; then
      report PASS "c: failed fixture init is refused (exit 3) and the enclosing repo is untouched"
    else
      report FAIL "c: failed fixture init" "${detail# }"
    fi

    before="$(snap "$e")"
    cenv GI_REPO_ROOT="$REPO_ROOT" GI_FT="$FIXTURE_TMPDIR_ABS" GI_LIB="$LIB" GI_DIR="$d2" \
      bash "$CHILD_C" > "$ft/d2.out" 2> "$ft/d2.err"
    rc=$?
    after="$(snap "$e")"
    detail=""
    [[ "$rc" -eq 0 ]] || detail="$detail exit $rc != 0 ($(head -1 "$ft/d2.err"));"
    count="$(git -C "$d2" rev-list --all --count 2>/dev/null)"
    [[ -d "$d2/.git" && "$count" == "1" ]] || detail="$detail writable dir has no own one-commit repo (count '${count}');"
    dd="$(snap_diff "$before" "$after")"
    [[ -z "$dd" ]] || detail="$detail enclosing repo changed ($dd);"
    if [[ -z "$detail" ]]; then
      report PASS "c: positive control, writable dir gets its own one-commit repo"
    else
      report FAIL "c: positive control" "${detail# }"
    fi
  fi
  chmod -R u+w "$d" 2>/dev/null

  # -- linked-worktree root (shared config)
  m="$ft/M"; w="$ft/W"
  mkdir -p "$m"
  git -C "$m" init -q
  printf 'm\n' > "$m/f"
  git -C "$m" add f
  git -C "$m" commit -qm m
  if ! git -C "$m" worktree add -q --detach "$w" HEAD >/dev/null 2>&1 || [[ ! -f "$w/.git" ]]; then
    report FAIL "c: linked-worktree root" "precondition: could not create linked worktree $w"
    return
  fi
  before="$(snap "$m")"
  cenv GI_REPO_ROOT="$REPO_ROOT" GI_FT="$FIXTURE_TMPDIR_ABS" GI_LIB="$LIB" GI_DIR="$w" \
    bash "$CHILD_C_WT" > "$ft/w.out" 2> "$ft/w.err"
  rc=$?
  after="$(snap "$m")"
  detail=""
  [[ "$rc" -eq 3 ]] || detail="$detail exit $rc != 3;"
  nerr="$(wc -l < "$ft/w.err" | tr -d ' ')"
  first="$(head -1 "$ft/w.err")"
  [[ "$nerr" == "1" && "$first" == "assert_fixture_repo: "* ]] \
    || detail="$detail stderr not exactly one 'assert_fixture_repo: ' line ($nerr lines, first '${first}');"
  dd="$(snap_diff "$before" "$after")"
  [[ -z "$dd" ]] || detail="$detail shared config/repo changed ($dd);"
  if [[ -z "$detail" ]]; then
    report PASS "c: linked-worktree root is refused (exit 3), main repo config unchanged"
  else
    report FAIL "c: linked-worktree root" "${detail# }"
  fi
}

# --- case d ---------------------------------------------------------------------------------
case_d() {
  local label="d: progress-line case g with GIT_DIR exported" tmp="$FIXTURE_TMPDIR_ABS/d" before after dd detail rc sum p reason
  if [[ ! -f "$PROGRESS_SUITE" ]]; then
    report FAIL "$label" "missing suite $PROGRESS_SUITE"
    return
  fi
  mkdir -p "$tmp"
  new_caller d1
  before="$(snap "$CALLER")"
  cenv GIT_DIR="$CALLER/.git" TMPDIR="$tmp" PROGRESS_LINE_ONLY=g bash "$PROGRESS_SUITE" > "$tmp/out" 2> "$tmp/err"
  rc=$?
  after="$(snap "$CALLER")"
  sum="$(grep -E "$SUMMARY_RE" "$tmp/out" | tail -1)"
  p="$(printf '%s' "$sum" | sed -E 's/^PASS: ([0-9]+) .*/\1/')"
  if [[ "$rc" -eq 0 && "$p" == "0" ]] && grep -q '^SKIP: g: ' "$tmp/out"; then
    reason="$(grep -m1 '^SKIP: g: ' "$tmp/out" | sed 's/^[^-]*-- //')"
    report SKIP "$label" "$reason"
    return
  fi
  detail=""
  [[ "$rc" -eq 0 ]] || detail="$detail suite exit $rc;"
  case "$sum" in
    *"   FAIL: 0   "*) [[ "${p:-0}" -ge 1 ]] || detail="$detail no PASS in '$sum';" ;;
    *) detail="$detail summary '${sum:-none}' lacks FAIL: 0;" ;;
  esac
  dd="$(snap_diff "$before" "$after")"
  [[ -z "$dd" ]] || detail="$detail caller changed ($dd);"
  if [[ -z "$detail" ]]; then
    report PASS "$label (exit 0, FAIL: 0, caller unchanged)"
  else
    report FAIL "$label" "${detail# }"
  fi
}

# --- case e ---------------------------------------------------------------------------------
CHILD_E="$FIXTURE_TMPDIR_ABS/child-e.sh"
cat > "$CHILD_E" <<'CHILD'
set -u
REPO_ROOT="$GI_REPO_ROOT"
FIXTURE_TMPDIR="$GI_FT"
. "$GI_LIB" || exit 9
git config --global user.email g@g >/dev/null 2>&1
printf 'global_rc=%s\n' "$?" > "$GI_FT/global-rc"
fx="$FIXTURE_TMPDIR/fx"
mkdir -p "$fx"
git -C "$fx" init -q
printf 'x\n' > "$fx/f"
git -C "$fx" add f
git -C "$fx" commit -qm c
git -C "$fx" config user.email > "$GI_FT/email-out" 2>/dev/null
CHILD

case_e() {
  local ft="$FIXTURE_TMPDIR_ABS/e" home="$FIXTURE_TMPDIR_ABS/e/home" b a detail ident email
  mkdir -p "$home/xdg" || return
  printf '[user]\n\temail = home@example.invalid\n' > "$home/.gitconfig"
  b="$(sha "$home/.gitconfig")"
  cenv HOME="$home" XDG_CONFIG_HOME="$home/xdg" GI_REPO_ROOT="$REPO_ROOT" GI_FT="$ft" GI_LIB="$LIB" \
    bash "$CHILD_E" > "$ft/out" 2> "$ft/err"
  a="$(sha "$home/.gitconfig")"
  detail=""
  [[ "$a" == "$b" ]] || detail="$detail HOME/.gitconfig was modified;"
  [[ ! -e "$home/xdg/git/config" ]] || detail="$detail XDG config was created;"
  ident="$(git -C "$ft/fx" log -1 --format='%an <%ae>|%cn <%ce>' 2>/dev/null)"
  [[ "$ident" == "$FIXTURE_IDENT|$FIXTURE_IDENT" ]] || detail="$detail fixture author/committer '${ident}' (want $FIXTURE_IDENT);"
  email="$(cat "$ft/email-out" 2>/dev/null)"
  [[ -z "$email" ]] || detail="$detail 'git config user.email' printed '${email}';"
  if [[ -z "$detail" ]]; then
    report PASS "e: HOME/XDG global config is not read or written ($(cat "$ft/global-rc" 2>/dev/null))"
  else
    report FAIL "e: global config isolation" "${detail# }"
  fi
}

# --- case f ---------------------------------------------------------------------------------
case_f() {
  local scan="$SCAN_ROOT" self="$SCAN_ROOT/templates/git-isolation.sh" hits offenders f sub list sites=0
  if [[ ! -d "$scan" ]]; then
    report FAIL "f: scan root" "missing $scan"
    return
  fi
  hits="$(find "$scan" -path "$scan/fixtures" -prune -o -type f ! -path "$self" -print 2>/dev/null \
    | while IFS= read -r f; do grep -nI 'config user\.' "$f" 2>/dev/null | sed "s|^|$f:|"; done)"
  if [[ -z "$hits" ]]; then
    report PASS "f: no 'config user.' line under the scan root"
  else
    report FAIL "f: 'config user.' lines" "$(printf '%s\n' "$hits" | head -5 | paste -sd';' -)"
  fi

  offenders=""
  for sub in templates lib loop-harness; do
    [[ -d "$scan/$sub" ]] || continue
    list="$(find "$scan/$sub" -type f ! -path "$self" 2>/dev/null)"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if grep -vE '^[[:space:]]*#' "$f" 2>/dev/null \
        | grep -qE '(^|[^[:alnum:]_.-])[[:alnum:]_]*git[[:alnum:]_]*[[:space:]]+([^|;&#]*[[:space:]])?init([[:space:]]|$|;|\))'; then
        sites=$((sites + 1))
        grep -q 'assert_fixture_repo' "$f" || offenders="$offenders ${f#"$scan"/}"
      fi
    done <<EOF
$list
EOF
  done
  if [[ -z "$offenders" ]]; then
    report PASS "f: all $sites files with a git init site (git, git_fixture, rc_git_at, ...) also contain assert_fixture_repo"
  else
    report FAIL "f: init sites without assert_fixture_repo" "${offenders# }"
  fi
}

for id in a b c d e f; do
  want "$id" && "case_$id"
done

summary
(( fail == 0 ))
