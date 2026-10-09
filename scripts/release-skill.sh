#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/release-skill.sh <skill-name> <MAJOR.MINOR.PATCH>
# Releases one skill. Promotes '## [Unreleased]' in skills/<name>/CHANGELOG.md
# to '## [X.Y.Z] - <today>', bumps metadata.version in its SKILL.md, re-runs
# the validator, commits, and creates the annotated tag <name>/vX.Y.Z.
# When X.Y.Z already is the skill's recorded version (for example a skill's
# first release), it only validates and tags. Never pushes.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || { echo "usage: $0 <skill-name> <MAJOR.MINOR.PATCH>" >&2; exit 2; }

name="$1"
version="$2"
skill_dir="${REPO_ROOT}/skills/${name}"
skill_md="${skill_dir}/SKILL.md"
changelog="${skill_dir}/CHANGELOG.md"
tag="${name}/v${version}"

[[ "$version" =~ $SEMVER_RE ]] || fail "not MAJOR.MINOR.PATCH: ${version}"
[[ -f "$skill_md" ]] || fail "no such skill: skills/${name}/SKILL.md"
[[ -f "$changelog" ]] || fail "missing skills/${name}/CHANGELOG.md"

git_() { git -C "$REPO_ROOT" "$@"; }

branch="$(git_ rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "master" ]] || fail "releases are tagged on master (currently on: ${branch})"
[[ -z "$(git_ status --porcelain)" ]] || fail "working tree not clean; commit the changelog notes first"
if git_ rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  fail "tag already exists: ${tag}"
fi

current="$(awk '
  NR == 1 { next }
  /^---$/ { exit }
  /^metadata:/ { in_meta = 1; next }
  in_meta && /^[^ \t]/ { exit }
  in_meta && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
' "$skill_md")"
[[ -n "$current" ]] || fail "skills/${name}/SKILL.md has no metadata.version"

if [[ "$version" == "$current" ]]; then
  grep -qE "^## \[${version//./\\.}\]" "$changelog" ||
    fail "metadata.version is ${version} but CHANGELOG.md has no '## [${version}]' entry"
else
  newest="$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n 1)"
  [[ "$newest" == "$version" ]] || fail "${version} is not newer than the current version ${current}"
  grep -qE "^## \[${version//./\\.}\]" "$changelog" && fail "CHANGELOG.md already has a '## [${version}]' entry"

  notes="$(awk '
    /^## \[Unreleased\]/ { on = 1; next }
    on && /^## \[/ { exit }
    on && NF { print }
  ' "$changelog")"
  [[ -n "$notes" ]] || fail "nothing under '## [Unreleased]' in skills/${name}/CHANGELOG.md; write the release notes first"

  today="$(date +%Y-%m-%d)"
  awk -v ver="$version" -v day="$today" '
    !done && /^## \[Unreleased\]/ { print; print ""; print "## [" ver "] - " day; done = 1; next }
    { print }
  ' "$changelog" >"${changelog}.tmp"
  mv "${changelog}.tmp" "$changelog"

  awk -v ver="$version" '
    /^---$/ && fence < 2 { fence++; print; next }
    fence == 1 && /^metadata:/ { in_meta = 1; print; next }
    fence == 1 && in_meta && /^[^ \t]/ { in_meta = 0 }
    fence == 1 && in_meta && $1 == "version:" && !replaced {
      sub(/version:.*/, "version: \"" ver "\"")
      replaced = 1
    }
    { print }
  ' "$skill_md" >"${skill_md}.tmp"
  mv "${skill_md}.tmp" "$skill_md"
fi

if ! bash "${REPO_ROOT}/scripts/validate-skills.sh" "$REPO_ROOT"; then
  [[ "$version" == "$current" ]] || git_ checkout -- "skills/${name}/SKILL.md" "skills/${name}/CHANGELOG.md"
  fail "validation failed; release aborted"
fi

if [[ "$version" != "$current" ]]; then
  git_ add "skills/${name}/SKILL.md" "skills/${name}/CHANGELOG.md"
  git_ commit -q -m "release: ${name} v${version}"
fi
git_ tag -a "$tag" -m "${name} v${version}"

echo "created ${tag}. inspect with: git show ${tag}"
echo "publish with:"
echo "  git push origin master ${tag}"
