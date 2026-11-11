#!/usr/bin/env bash
# Tests for scripts/tag-released-skills.sh.
#
# Every case builds a scratch git repository with a skills/ tree, and a bare
# repository as its remote, under one `mktemp -d` directory that is removed on
# exit. This folder ships no fixture files on purpose: a committed file named
# SKILL.md under tests/ would be published by the Skills CLI.
#
# Offline: the only remotes are local bare repositories. The committer identity
# is set inside the scratch repositories only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$REPO/scripts/tag-released-skills.sh"

PASS=0
FAIL=0
SKIP=0
SUMMARY_PRINTED=0

SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-tagging.XXXXXX")"
SCRATCH_ROOT="$(cd "$SCRATCH_ROOT" && pwd -P)"
cleanup() {
  chmod -R u+rwx "$SCRATCH_ROOT" 2>/dev/null || true
  rm -rf "$SCRATCH_ROOT"
}

print_summary() {
  echo "PASS: $PASS FAIL: $FAIL SKIP: $SKIP"
  SUMMARY_PRINTED=1
}

# Exit trap. When the suite stops before the summary was printed (a set-up
# command failed under `set -e`), say so on stderr, still print the summary
# line, and never exit 0.
on_exit() {
  local rc=$?
  if [ "$SUMMARY_PRINTED" -eq 0 ]; then
    echo "ABORTED: suite stopped before all cases ran" >&2
    print_summary
    if [ "$rc" -eq 0 ]; then
      rc=1
    fi
  fi
  cleanup
  exit "$rc"
}
trap on_exit EXIT

# --- ambient conditions, pinned ------------------------------------------------

export LC_ALL=C
# No user or system git configuration: the scratch repositories carry their own
# identity, and no signing or hook setting of the machine can change a result.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# --- helpers -------------------------------------------------------------------

CASE=""
CASE_OK=1
WORK=""
REMOTE=""
OUT=""
ERR=""
RC=0

begin() {
  CASE="$1"
  CASE_OK=1
}

# flunk <reason>: record the first failure of the current case.
flunk() {
  if [ "$CASE_OK" -eq 1 ]; then
    echo "FAIL $CASE: $1"
    FAIL=$((FAIL + 1))
    CASE_OK=0
  fi
}

finish() {
  if [ "$CASE_OK" -eq 1 ]; then
    echo "PASS $CASE"
    PASS=$((PASS + 1))
  fi
}

skip() {
  echo "SKIP $CASE: $1"
  SKIP=$((SKIP + 1))
  CASE_OK=0
}

# new_repo: a scratch work repository (WORK) with one commit on `main`, and a
# bare repository (REMOTE) registered as `origin` that already has `main`.
REPO_SEQ=0
new_repo() {
  REPO_SEQ=$((REPO_SEQ + 1))
  local base="$SCRATCH_ROOT/case-$REPO_SEQ"
  WORK="$base/work"
  REMOTE="$base/remote.git"
  mkdir -p "$WORK/skills"
  git init -q --bare "$REMOTE"
  git -C "$REMOTE" config user.name "Release Suite"
  git -C "$REMOTE" config user.email "release-suite@example.invalid"
  git init -q "$WORK"
  git -C "$WORK" symbolic-ref HEAD refs/heads/main
  git -C "$WORK" config user.name "Release Suite"
  git -C "$WORK" config user.email "release-suite@example.invalid"
  git -C "$WORK" remote add origin "$REMOTE"
  echo "scratch" >"$WORK/README.md"
  commit_all "initial"
}

commit_all() {
  git -C "$WORK" add -A
  git -C "$WORK" commit -q -m "$1"
}

push_main() {
  git -C "$WORK" push -q origin main
}

# add_skill <name> <version|-> [<changelog-heading-version|->]
# `-` as the version writes a SKILL.md with no metadata.version; `-` as the
# heading version writes a changelog with no released heading. The heading
# version defaults to the version.
add_skill() {
  local name="$1" version="$2" heading="${3:-$2}"
  local dir="$WORK/skills/$name"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $name"
    echo "description: Scratch skill for the release tagging suite."
    echo "metadata:"
    echo "  author: suite"
    if [ "$version" != "-" ]; then
      echo "  version: \"$version\""
    fi
    echo "---"
    echo
    echo "# $name"
  } >"$dir/SKILL.md"
  {
    echo "# Changelog"
    echo
    echo "## [Unreleased]"
    if [ "$heading" != "-" ]; then
      echo
      echo "## [$heading] - 2026-01-01"
      echo
      echo "- Scratch entry."
    fi
  } >"$dir/CHANGELOG.md"
}

# run_script [args...]: runs the script against WORK; sets OUT, ERR, RC.
run_script() {
  local out_file="$SCRATCH_ROOT/stdout" err_file="$SCRATCH_ROOT/stderr"
  RC=0
  SKILLS_REPO_ROOT="$WORK" bash "$SCRIPT" "$@" >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
}

local_tags() { git -C "$WORK" tag --list | sort | tr '\n' ' ' | sed 's/ $//'; }
remote_tags() { git -C "$REMOTE" tag --list | sort | tr '\n' ' ' | sed 's/ $//'; }
head_commit() { git -C "$WORK" rev-parse HEAD; }

expect_rc() {
  [ "$RC" -eq "$1" ] || flunk "exit code $RC, expected $1 (stderr: $ERR)"
}
expect_out() {
  [ "$OUT" = "$1" ] || flunk "standard output is '$OUT', expected '$1'"
}
expect_err_has() {
  case "$ERR" in
    *"$1"*) ;;
    *) flunk "standard error lacks '$1' (got: $ERR)" ;;
  esac
}
expect_local_tags() {
  local got
  got="$(local_tags)"
  [ "$got" = "$1" ] || flunk "local tags are '$got', expected '$1'"
}
expect_remote_tags() {
  local got
  got="$(remote_tags)"
  [ "$got" = "$1" ] || flunk "remote tags are '$got', expected '$1'"
}

# --- cases ---------------------------------------------------------------------

begin "tag/untagged-version-is-tagged"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
run_script
expect_rc 0
expect_out "demo/v0.2.0"
expect_local_tags "demo/v0.2.0"
if [ "$CASE_OK" -eq 1 ]; then
  [ "$(git -C "$WORK" cat-file -t refs/tags/demo/v0.2.0)" = "tag" ] ||
    flunk "demo/v0.2.0 is not an annotated tag"
  [ "$(git -C "$WORK" rev-parse 'refs/tags/demo/v0.2.0^{commit}')" = "$(head_commit)" ] ||
    flunk "demo/v0.2.0 does not point at HEAD"
  [ "$(git -C "$WORK" tag --list --format='%(contents:subject)' demo/v0.2.0)" = "demo v0.2.0" ] ||
    flunk "tag message is not 'demo v0.2.0'"
fi
expect_remote_tags ""
finish

begin "tag/already-tagged-is-skipped"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
git -C "$WORK" tag -a demo/v0.2.0 -m "demo v0.2.0"
tag_object="$(git -C "$WORK" rev-parse refs/tags/demo/v0.2.0)"
tagged_commit="$(head_commit)"
echo "more" >>"$WORK/README.md"
commit_all "a later commit"
[ "$(head_commit)" != "$tagged_commit" ] || flunk "precondition: HEAD did not move"
run_script
expect_rc 0
expect_out ""
expect_err_has "nothing to tag"
[ "$(git -C "$WORK" rev-parse refs/tags/demo/v0.2.0)" = "$tag_object" ] || flunk "the existing tag object changed"
[ "$(git -C "$WORK" rev-parse 'refs/tags/demo/v0.2.0^{commit}')" = "$tagged_commit" ] || flunk "the existing tag moved"
expect_local_tags "demo/v0.2.0"
finish

begin "tag/two-skills-one-due"
new_repo
add_skill alpha 1.0.0
add_skill beta 0.3.0
commit_all "alpha and beta"
push_main
git -C "$WORK" tag -a alpha/v1.0.0 -m "alpha v1.0.0"
alpha_object="$(git -C "$WORK" rev-parse refs/tags/alpha/v1.0.0)"
run_script
expect_rc 0
expect_out "beta/v0.3.0"
expect_local_tags "alpha/v1.0.0 beta/v0.3.0"
[ "$(git -C "$WORK" rev-parse refs/tags/alpha/v1.0.0)" = "$alpha_object" ] || flunk "the alpha tag changed"
finish

begin "tag/missing-changelog-heading-fails-and-tags-nothing"
new_repo
# `aaa` sorts first and is complete; `bbb` lacks its heading. Both are due.
add_skill aaa 1.0.0
add_skill bbb 0.4.0 -
commit_all "aaa and bbb"
push_main
grep -q '^## \[1\.0\.0\]' "$WORK/skills/aaa/CHANGELOG.md" || flunk "precondition: aaa has no heading"
if grep -q '^## \[0\.4\.0\]' "$WORK/skills/bbb/CHANGELOG.md"; then flunk "precondition: bbb has its heading"; fi
run_script
expect_rc 1
expect_err_has "error: bbb: metadata.version is 0.4.0 but CHANGELOG.md has no '## [0.4.0]' entry"
expect_out ""
expect_local_tags ""
finish

begin "tag/push-creates-remote-tag"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
# A local tag the script must not push (a push with --tags would send it).
git -C "$WORK" tag -a local-only -m "local only"
run_script --push
expect_rc 0
expect_out "demo/v0.2.0"
expect_local_tags "demo/v0.2.0 local-only"
expect_remote_tags "demo/v0.2.0"
if [ "$CASE_OK" -eq 1 ]; then
  [ "$(git -C "$REMOTE" rev-parse refs/tags/demo/v0.2.0)" = "$(git -C "$WORK" rev-parse refs/tags/demo/v0.2.0)" ] ||
    flunk "the remote tag is not the local annotated tag"
  [ "$(git -C "$REMOTE" rev-parse 'refs/tags/demo/v0.2.0^{commit}')" = "$(head_commit)" ] ||
    flunk "the remote tag does not point at HEAD"
fi
finish

begin "tag/remote-tag-without-local-is-skipped"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
# The tag is created in the remote only.
git -C "$REMOTE" tag -a demo/v0.2.0 -m "demo v0.2.0" main
remote_object="$(git -C "$REMOTE" rev-parse refs/tags/demo/v0.2.0)"
[ -z "$(local_tags)" ] || flunk "precondition: a local tag exists"
git -C "$WORK" ls-remote --tags origin refs/tags/demo/v0.2.0 | grep -q 'refs/tags/demo/v0.2.0' ||
  flunk "precondition: the remote does not list the tag"
run_script --push
expect_rc 0
expect_out ""
expect_err_has "nothing to tag"
expect_local_tags ""
[ "$(git -C "$REMOTE" rev-parse refs/tags/demo/v0.2.0)" = "$remote_object" ] || flunk "the remote tag changed"
finish

begin "tag/dry-run-changes-nothing"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
run_script --dry-run
expect_rc 0
expect_out "demo/v0.2.0"
expect_local_tags ""
expect_remote_tags ""
run_script --dry-run --push
expect_rc 0
expect_out "demo/v0.2.0"
expect_local_tags ""
expect_remote_tags ""
finish

begin "tag/unknown-argument-exits-2"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
run_script --bogus
expect_rc 2
expect_out ""
expect_err_has "usage:"
expect_local_tags ""
finish

begin "tag/invalid-version-fails"
new_repo
add_skill demo 1.2
commit_all "demo 1.2"
push_main
grep -q '^  version: "1.2"$' "$WORK/skills/demo/SKILL.md" || flunk "precondition: version is not \"1.2\""
run_script
expect_rc 1
expect_out ""
expect_err_has "error: demo:"
expect_local_tags ""
finish

begin "tag/missing-version-fails"
new_repo
# `aaa` sorts first, is complete and due; `demo` has no metadata.version.
add_skill aaa 1.0.0
add_skill demo -
commit_all "aaa and demo"
push_main
if grep -q 'version:' "$WORK/skills/demo/SKILL.md"; then flunk "precondition: demo has a version"; fi
run_script
expect_rc 1
expect_out ""
expect_err_has "error: demo:"
expect_local_tags ""
finish

begin "tag/unreachable-remote-fails"
new_repo
add_skill demo 0.2.0
commit_all "demo 0.2.0"
push_main
if git -C "$WORK" remote | grep -qx nowhere; then flunk "precondition: remote 'nowhere' exists"; fi
run_script --push --remote nowhere
expect_rc 1
expect_out ""
expect_err_has "nowhere"
expect_local_tags ""
expect_remote_tags ""
finish

begin "tag/partial-push-failure-lists-only-pushed"
new_repo
add_skill aaa 1.0.0
add_skill bbb 2.0.0
add_skill ccc 3.0.0
commit_all "aaa, bbb and ccc"
push_main
# The remote rejects the second tag; the hook lives in the scratch remote.
{
  echo '#!/bin/sh'
  echo 'case "$1" in'
  echo '  refs/tags/bbb/*) echo "rejected by the suite hook: $1" >&2; exit 1 ;;'
  echo 'esac'
  echo 'exit 0'
} >"$REMOTE/hooks/update"
chmod +x "$REMOTE/hooks/update"
[ -x "$REMOTE/hooks/update" ] || flunk "precondition: the remote hook is not executable"
run_script --push
[ "$RC" -ne 0 ] || flunk "exit code 0, expected non-zero"
expect_out "aaa/v1.0.0"
expect_err_has "rejected by the suite hook: refs/tags/bbb/v2.0.0"
expect_remote_tags "aaa/v1.0.0"
finish

begin "tag/real-repository-dry-run"
# Read-only run against the repository this suite lives in. A copy of the tree
# without its .git directory has nothing to read, so the case is skipped there.
if [ "$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)" != "$REPO" ]; then
  skip "$REPO is not the root of a git work tree"
else
  tags_before="$(git -C "$REPO" for-each-ref refs/tags)"
  out_file="$SCRATCH_ROOT/stdout"
  err_file="$SCRATCH_ROOT/stderr"
  RC=0
  env -u SKILLS_REPO_ROOT bash "$SCRIPT" --dry-run >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
  expect_rc 0
  if [ -n "$OUT" ]; then
    bad="$(grep -Ev '^[a-z0-9-]+/v[0-9]+\.[0-9]+\.[0-9]+$' "$out_file" || true)"
    [ -z "$bad" ] || flunk "standard output has a line that is not a tag name: $bad"
  fi
  [ "$(git -C "$REPO" for-each-ref refs/tags)" = "$tags_before" ] || flunk "the repository's tags changed"
  finish
fi

print_summary
[ "$FAIL" -eq 0 ]
