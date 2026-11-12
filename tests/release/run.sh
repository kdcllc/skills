#!/usr/bin/env bash
# Tests for scripts/tag-released-skills.sh, scripts/check-skill-versions.sh and
# skills/skill-versioning/scripts/skill-status.sh.
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
CHECK="$REPO/scripts/check-skill-versions.sh"
STATUS="$REPO/skills/skill-versioning/scripts/skill-status.sh"

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

# run_check [args...]: runs check-skill-versions.sh against WORK; sets OUT, ERR, RC.
run_check() {
  local out_file="$SCRATCH_ROOT/stdout" err_file="$SCRATCH_ROOT/stderr"
  RC=0
  SKILLS_REPO_ROOT="$WORK" bash "$CHECK" "$@" >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
}

# mark_base: records the current commit as the comparison base (branch `base`).
mark_base() { git -C "$WORK" branch -q -f base; }

# write_changelog <name> <unreleased-entry|-> <heading line|->
write_changelog() {
  {
    echo "# Changelog"
    echo
    echo "## [Unreleased]"
    if [ "$2" != "-" ]; then echo; echo "- $2"; fi
    if [ "$3" != "-" ]; then echo; echo "$3"; echo; echo "- Scratch entry."; fi
  } >"$WORK/skills/$1/CHANGELOG.md"
}

expect_out_has() {
  case "$OUT" in
    *"$1"*) ;;
    *) flunk "standard output lacks '$1' (got: $OUT)" ;;
  esac
}
expect_error_lines() {
  local n
  n="$(printf '%s\n' "$ERR" | grep -c '^error:' || true)"
  [ "$n" -eq "$1" ] || flunk "$n error lines, expected $1 (stderr: $ERR)"
}

# run_status <name> <root>: runs skill-status.sh; sets RC and NEXT (the NEXT
# column of the skill's row).
NEXT=""
run_status() {
  local out_file="$SCRATCH_ROOT/stdout" err_file="$SCRATCH_ROOT/stderr"
  RC=0
  bash "$STATUS" --root "$WORK" "$1" >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
  NEXT="$(awk -v n="$1" '$1 == n' "$out_file" | sed -E 's/^([^ ]+ +){6}//')"
}
expect_next() {
  [ "$NEXT" = "$1" ] || flunk "NEXT is '$NEXT', expected '$1'"
}
expect_next_starts() {
  case "$NEXT" in
    "$1"*) ;;
    *) flunk "NEXT is '$NEXT', expected it to start with '$1'" ;;
  esac
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

# --- check-skill-versions.sh ----------------------------------------------------

begin "check/no-argument-exits-2"
new_repo
add_skill demo 1.0.0
commit_all "demo"
run_check
expect_rc 2
expect_out ""
expect_err_has "usage:"
finish

begin "check/unknown-base-ref-exits-1"
new_repo
add_skill demo 1.0.0
commit_all "demo"
run_check no-such-ref
expect_rc 1
expect_out ""
expect_err_has "error: base ref does not resolve"
finish

begin "check/no-skill-folder-changed"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
run_check base
expect_rc 0
expect_out "no skill folder changed"
[ -z "$ERR" ] || flunk "standard error is not empty: $ERR"
finish

begin "check/version-not-raised-fails"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
echo "more" >>"$WORK/skills/demo/SKILL.md"
commit_all "change without bump"
run_check base
expect_rc 1
expect_err_has "error: demo: metadata.version 1.0.0 is not greater than 1.0.0"
expect_error_lines 1
finish

begin "check/missing-dated-heading-fails"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
add_skill demo 1.0.1 -
commit_all "bump without heading"
run_check base
expect_rc 1
expect_err_has "error: demo: CHANGELOG.md first release heading"
expect_out ""
finish

begin "check/entry-under-unreleased-fails"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
add_skill demo 1.0.1
write_changelog demo "left behind" "## [1.0.1] - 2026-02-02"
commit_all "bump with open entry"
run_check base
expect_rc 1
expect_err_has "error: demo: CHANGELOG.md has 1 entry line(s) under ## [Unreleased]"
expect_out ""
finish

begin "check/numeric-bump-1.0.9-to-1.0.10-passes"
new_repo
add_skill demo 1.0.9
commit_all "demo"
mark_base
add_skill demo 1.0.10
commit_all "bump"
run_check base
expect_rc 0
expect_out "ok: demo 1.0.9 -> 1.0.10"
expect_error_lines 0
finish

begin "check/lowered-version-fails"
new_repo
add_skill demo 1.2.0
commit_all "demo"
mark_base
add_skill demo 1.1.0
commit_all "lower"
run_check base
expect_rc 1
expect_err_has "error: demo: metadata.version 1.1.0 is not greater than 1.2.0"
expect_out ""
finish

begin "check/new-skill-passes"
new_repo
add_skill old 1.0.0
commit_all "old"
mark_base
add_skill fresh 0.1.0
commit_all "fresh"
run_check base
expect_rc 0
expect_out "ok: fresh new -> 0.1.0"
expect_error_lines 0
finish

begin "check/two-violations-two-error-lines"
new_repo
add_skill aaa 1.0.0
add_skill bbb 2.0.0
commit_all "aaa, bbb"
mark_base
echo "more" >>"$WORK/skills/aaa/SKILL.md"
add_skill bbb 2.0.1 -
commit_all "aaa unbumped, bbb without heading"
run_check base
expect_rc 1
expect_error_lines 2
expect_err_has "error: aaa:"
expect_err_has "error: bbb:"
finish

begin "check/removed-skill-is-skipped"
new_repo
add_skill gone 1.0.0
add_skill kept 1.0.0
commit_all "gone, kept"
mark_base
git -C "$WORK" rm -q -r skills/gone
commit_all "remove gone"
run_check base
expect_rc 0
expect_out "skip: gone removed"
expect_error_lines 0
finish

begin "check/change-outside-skills-only"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
echo "more" >>"$WORK/README.md"
commit_all "readme"
run_check base
expect_rc 0
expect_out "no skill folder changed"
expect_error_lines 0
finish

begin "check/moved-file-flags-source-skill"
new_repo
add_skill a 1.0.0
add_skill b 1.0.0
echo "shared" >"$WORK/skills/a/extra.md"
commit_all "a with extra, b"
mark_base
git -C "$WORK" mv skills/a/extra.md skills/b/extra.md
add_skill b 1.0.1
commit_all "move extra to b, bump b only"
run_check base
expect_rc 1
expect_err_has "error: a:"
expect_out_has "ok: b 1.0.0 -> 1.0.1"
expect_error_lines 1
finish

begin "check/undated-heading-fails"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
add_skill demo 1.0.1
write_changelog demo - "## [1.0.1]"
commit_all "bump with undated heading"
run_check base
expect_rc 1
expect_err_has "error: demo: CHANGELOG.md first release heading"
expect_out ""
finish

begin "check/malformed-date-heading-fails"
new_repo
add_skill demo 1.0.0
commit_all "demo"
mark_base
add_skill demo 1.0.1
write_changelog demo - "## [1.0.1] - soon"
commit_all "bump with malformed date"
run_check base
expect_rc 1
expect_err_has "error: demo: CHANGELOG.md first release heading"
expect_out ""
finish

# --- skill-status.sh ------------------------------------------------------------

begin "status/release-prepared"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
add_skill demo 1.1.0
commit_all "prepare 1.1.0"
run_status demo
expect_rc 0
expect_next "release prepared (tag demo/v1.1.0 pending)"
finish

begin "status/changed-after-tag-records-under-unreleased"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
echo "more" >>"$WORK/skills/demo/SKILL.md"
commit_all "change after tag"
run_status demo
expect_rc 0
expect_next "record changes under Unreleased"
finish

begin "status/entries-under-unreleased-ready-to-release"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
write_changelog demo "new work" "## [1.0.0] - 2026-01-01"
commit_all "entry"
run_status demo
expect_rc 0
expect_next "ready to release (pick the bump from Unreleased)"
finish

begin "status/no-tag-first-release"
new_repo
add_skill demo 0.1.0
commit_all "demo"
run_status demo
expect_rc 0
expect_next "tag first release demo/v0.1.0"
finish

begin "status/tag-equal-nothing-changed-up-to-date"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
run_status demo
expect_rc 0
expect_next "up to date"
finish

begin "status/version-below-tag-mismatch"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
add_skill demo 0.9.0
commit_all "lower"
run_status demo
expect_rc 0
expect_next_starts "mismatch:"
finish

begin "status/version-above-tag-old-heading-mismatch"
new_repo
add_skill demo 1.0.0
commit_all "demo"
git -C "$WORK" tag demo/v1.0.0
add_skill demo 1.1.0 1.0.0
commit_all "version raised, heading not"
run_status demo
expect_rc 0
expect_next_starts "mismatch:"
finish

begin "status/no-version-adopt-versioning"
new_repo
add_skill demo -
commit_all "demo without version"
run_status demo
expect_rc 0
expect_next "adopt versioning (add metadata.version and CHANGELOG.md)"
finish

begin "status/no-changelog-adopt-versioning"
new_repo
add_skill demo 1.0.0
rm "$WORK/skills/demo/CHANGELOG.md"
commit_all "demo without changelog"
run_status demo
expect_rc 0
expect_next "adopt versioning (add metadata.version and CHANGELOG.md)"
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
