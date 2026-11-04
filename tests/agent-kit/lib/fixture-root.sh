# shellcheck shell=bash
# assert_fixture_root — refuse empty, missing, repo-root, or out-of-TMPDIR fixture paths.
# Source after REPO_ROOT and FIXTURE_TMPDIR are set (both absolute, existing directories).
#
# Fail-closed: REPO_ROOT_ABS / FIXTURE_TMPDIR_ABS are ALWAYS recomputed from REPO_ROOT /
# FIXTURE_TMPDIR (never inherited from the environment), and sourcing this file EXITS the
# sourcing shell non-zero unless
#   - both inputs are non-empty absolute paths of existing directories, and
#   - FIXTURE_TMPDIR is not "/", is not the repository root, is not under it, and is not an
#     ancestor of it.
#
# Git isolation (applied on source, unconditional, nothing inherited or opt-out): the repo-locating
# and config-redirecting variables (GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
# GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT)
# are unset, and system/global config is disabled (GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=/dev/null).
# Why: an exported repo-locating variable, or a linked worktree's shared config, lets fixture git
# write the caller's repository. Fixture identity comes from the environment (GIT_AUTHOR_* /
# GIT_COMMITTER_*); fixtures never write user.name or user.email into a repository.
#
# assert_fixture_repo <root> — after `git init <root>` and before any other git write, require that
# <root> passes assert_fixture_root AND that git resolves its top level to <root> itself and its
# git dir to <root>/.git (rejects nested/failed-init, subdirectories, and linked worktrees).
# Returns 1 with one `assert_fixture_repo: ...` stderr line otherwise.

# Resolve an existing directory to its physical absolute path. Empty/missing input fails
# (it must never fall back to the current directory).
_fixture_root_resolve() {
  local p="${1-}"
  [[ -n "$p" ]] || return 1
  [[ -d "$p" ]] || return 1
  (CDPATH='' cd -- "$p" >/dev/null 2>&1 && pwd -P)
}

_fixture_root_init() {
  local name val
  for name in REPO_ROOT FIXTURE_TMPDIR; do
    eval "val=\"\${$name-}\""
    if [[ -z "$val" ]]; then
      echo "fixture-root: $name is empty or unset" >&2
      return 1
    fi
    case "$val" in
      /*) ;;
      *)
        echo "fixture-root: $name is not an absolute path: $val" >&2
        return 1
        ;;
    esac
    if [[ ! -d "$val" ]]; then
      echo "fixture-root: $name is not an existing directory: $val" >&2
      return 1
    fi
  done
  REPO_ROOT_ABS="$(_fixture_root_resolve "$REPO_ROOT")" && [[ -n "$REPO_ROOT_ABS" ]] || {
    echo "fixture-root: cannot resolve REPO_ROOT: $REPO_ROOT" >&2
    return 1
  }
  FIXTURE_TMPDIR_ABS="$(_fixture_root_resolve "$FIXTURE_TMPDIR")" && [[ -n "$FIXTURE_TMPDIR_ABS" ]] || {
    echo "fixture-root: cannot resolve FIXTURE_TMPDIR: $FIXTURE_TMPDIR" >&2
    return 1
  }
  if [[ "$FIXTURE_TMPDIR_ABS" == "/" ]]; then
    echo "fixture-root: FIXTURE_TMPDIR must not be the filesystem root" >&2
    return 1
  fi
  case "$FIXTURE_TMPDIR_ABS" in
    "$REPO_ROOT_ABS" | "$REPO_ROOT_ABS"/*)
      echo "fixture-root: FIXTURE_TMPDIR is the repository root or under it: $FIXTURE_TMPDIR_ABS" >&2
      return 1
      ;;
  esac
  case "$REPO_ROOT_ABS" in
    "$FIXTURE_TMPDIR_ABS"/*)
      echo "fixture-root: FIXTURE_TMPDIR contains the repository root: $FIXTURE_TMPDIR_ABS" >&2
      return 1
      ;;
  esac
  return 0
}

REPO_ROOT_ABS=""
FIXTURE_TMPDIR_ABS=""
_fixture_root_init || exit 1

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=agent-kit-fixture
export GIT_AUTHOR_EMAIL=fixture@agent-kit.invalid
export GIT_COMMITTER_NAME=agent-kit-fixture
export GIT_COMMITTER_EMAIL=fixture@agent-kit.invalid

assert_fixture_root() {
  local root="${1-}" abs
  if [[ -z "$root" ]]; then
    echo "assert_fixture_root: empty root" >&2
    return 1
  fi
  if [[ ! -d "$root" ]]; then
    echo "assert_fixture_root: not a directory: $root" >&2
    return 1
  fi
  abs="$(_fixture_root_resolve "$root")" && [[ -n "$abs" ]] || {
    echo "assert_fixture_root: cannot resolve: $root" >&2
    return 1
  }
  case "$abs" in
    "$REPO_ROOT_ABS" | "$REPO_ROOT_ABS"/*)
      echo "assert_fixture_root: refused repository root: $abs" >&2
      return 1
      ;;
  esac
  case "$abs" in
    "$FIXTURE_TMPDIR_ABS" | "$FIXTURE_TMPDIR_ABS"/*) return 0 ;;
  esac
  echo "assert_fixture_root: outside FIXTURE_TMPDIR ($FIXTURE_TMPDIR_ABS): $abs" >&2
  return 1
}

assert_fixture_repo() {
  local root="${1-}" abs top gitdir rtop rgd
  assert_fixture_root "$root" || return 1
  abs="$(_fixture_root_resolve "$root")"
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || top=""
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  if [[ -z "$top" || -z "$gitdir" ]]; then
    echo "assert_fixture_repo: no git repository resolves for root $abs (top='${top}' gitdir='${gitdir}')" >&2
    return 1
  fi
  rtop="$(_fixture_root_resolve "$top")" || rtop=""
  rgd="$(_fixture_root_resolve "$gitdir")" || rgd=""
  if [[ "$rtop" != "$abs" ]]; then
    echo "assert_fixture_repo: root $abs resolves to top level '${rtop:-$top}', not itself" >&2
    return 1
  fi
  if [[ "$rgd" != "$abs/.git" ]]; then
    echo "assert_fixture_repo: root $abs resolves to git dir '${rgd:-$gitdir}', not $abs/.git" >&2
    return 1
  fi
  return 0
}
