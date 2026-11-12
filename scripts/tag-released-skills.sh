#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/tag-released-skills.sh [--push] [--remote <name>] [--dry-run]
# Tags every skill whose recorded version has no tag yet. For each
# skills/<name>/SKILL.md it reads metadata.version and, when the tag
# <name>/vX.Y.Z does not exist, creates it as an annotated tag on HEAD.
# With --push the tag must also be absent from the remote (default: origin),
# and each created tag is pushed by its full ref. --dry-run only lists.
# Standard output is one line per tag, exactly <name>/vX.Y.Z, printed after
# the tag is created (and pushed). Every skill is checked before any tag is
# created. A failed push is retried (TAG_PUSH_ATTEMPTS tries in all, default 3,
# waiting TAG_PUSH_RETRY_DELAY seconds times the try number, default 5). When
# every try fails, the tag this run created is deleted again so the next run
# retries it, the remaining tags are still tagged and pushed, and the script
# exits 1. Never moves an existing tag or deletes one it did not just create,
# never commits, never changes files.
# The repository root comes from this script's path; SKILLS_REPO_ROOT
# overrides it (used by tests/release/run.sh).

REPO_ROOT="${SKILLS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
PUSH_ATTEMPTS="${TAG_PUSH_ATTEMPTS:-3}"
PUSH_RETRY_DELAY="${TAG_PUSH_RETRY_DELAY:-5}"

# Skills are visited in byte order on every machine.
export LC_ALL=C

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 [--push] [--remote <name>] [--dry-run]" >&2
  exit 2
}

push=0
dry_run=0
remote="origin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) push=1 ;;
    --dry-run) dry_run=1 ;;
    --remote)
      [[ $# -ge 2 && -n "$2" ]] || usage
      remote="$2"
      shift
      ;;
    *) usage ;;
  esac
  shift
done

git_() { git -C "$REPO_ROOT" "$@"; }

git_ rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: ${REPO_ROOT}"

# --- check every skill; nothing is tagged in this part ------------------------

due=()
errors=0

shopt -s nullglob
for skill_md in "${REPO_ROOT}"/skills/*/SKILL.md; do
  skill_dir="$(dirname "$skill_md")"
  name="$(basename "$skill_dir")"
  changelog="${skill_dir}/CHANGELOG.md"

  version="$(awk '
    NR == 1 { next }
    /^---$/ { exit }
    /^metadata:/ { in_meta = 1; next }
    in_meta && /^[^ \t]/ { exit }
    in_meta && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
  ' "$skill_md")"

  if [[ -z "$version" ]]; then
    echo "error: ${name}: skills/${name}/SKILL.md has no metadata.version" >&2
    errors=1
    continue
  fi
  if ! [[ "$version" =~ $SEMVER_RE ]]; then
    echo "error: ${name}: metadata.version is not MAJOR.MINOR.PATCH: ${version}" >&2
    errors=1
    continue
  fi

  tag="${name}/v${version}"

  if git_ rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    continue
  fi

  if [[ "$push" -eq 1 ]]; then
    # A failing ls-remote is an error, never "tag absent".
    if ! remote_refs="$(git_ ls-remote --tags "$remote" "refs/tags/${tag}")"; then
      fail "cannot read tags from remote '${remote}'; nothing tagged"
    fi
    if awk -v ref="refs/tags/${tag}" '$2 == ref || $2 == ref "^{}" { found = 1 } END { exit !found }' <<<"$remote_refs"; then
      continue
    fi
  fi

  if [[ ! -f "$changelog" ]] || ! grep -qE "^## \[${version//./\\.}\]" "$changelog"; then
    echo "error: ${name}: metadata.version is ${version} but CHANGELOG.md has no '## [${version}]' entry" >&2
    errors=1
    continue
  fi

  due+=("${name} ${version}")
done

[[ "$errors" -eq 0 ]] || exit 1

if [[ ${#due[@]} -eq 0 ]]; then
  echo "nothing to tag" >&2
  exit 0
fi

# --- tag (and push) each due skill ---------------------------------------------

[[ "$PUSH_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "TAG_PUSH_ATTEMPTS must be a positive integer: ${PUSH_ATTEMPTS}"
[[ "$PUSH_RETRY_DELAY" =~ ^[0-9]+$ ]] || fail "TAG_PUSH_RETRY_DELAY must be a whole number of seconds: ${PUSH_RETRY_DELAY}"

# push_tag <tag>: push one tag by its full ref, retrying transient rejections.
push_tag() {
  local attempt=1
  while :; do
    git_ push "$remote" "refs/tags/$1" >&2 && return 0
    [[ "$attempt" -lt "$PUSH_ATTEMPTS" ]] || return 1
    echo "warning: push of $1 failed (try ${attempt} of ${PUSH_ATTEMPTS}); retrying" >&2
    sleep $((PUSH_RETRY_DELAY * attempt))
    attempt=$((attempt + 1))
  done
}

failed=()
for entry in "${due[@]}"; do
  name="${entry% *}"
  version="${entry##* }"
  tag="${name}/v${version}"

  if [[ "$dry_run" -eq 0 ]]; then
    git_ tag -a "$tag" -m "${name} v${version}" || fail "could not create tag ${tag}"
    if [[ "$push" -eq 1 ]] && ! push_tag "$tag"; then
      # Drop the unpushed tag so the next run sees it as due again.
      git_ tag -d "$tag" >/dev/null
      echo "error: could not push ${tag} to '${remote}' after ${PUSH_ATTEMPTS} tries; the tag was not created" >&2
      failed+=("$tag")
      continue
    fi
  fi

  echo "$tag"
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "error: not tagged: ${failed[*]}; re-run the tag-on-merge workflow to retry" >&2
  exit 1
fi
