#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/check-skill-versions.sh <base-ref>
# Checks that a pull request carries the release of every skill it changes
# (AGENTS.md, Versioning rules). The comparison base is the merge base of
# <base-ref> and HEAD; only committed changes count. A skill is changed when
# a path under skills/<name>/ differs (renames count as delete + add, so both
# skills of a moved file are changed). For each changed skill the script checks:
#   - metadata.version at HEAD exists and is MAJOR.MINOR.PATCH;
#   - when the skill exists at the merge base with a valid version, the HEAD
#     version is strictly greater (numeric comparison of each part);
#   - CHANGELOG.md exists, and its first "## [" heading after
#     "## [Unreleased]" is "## [<version>] - YYYY-MM-DD";
#   - the "## [Unreleased]" section holds no list entry.
# A changed skill whose SKILL.md is gone at HEAD (removed) is skipped.
# Every changed skill is checked; each violation prints "error: <name>: ...".
# Standard output: "ok: <name> <base|new> -> <version>" per passing skill,
# "skip: <name> removed", or "no skill folder changed".
# Exit codes: 0 no violation, 1 violation or unusable repository/ref,
# 2 bad usage. Never writes to the repository and never contacts a remote.
# The repository root comes from this script's path; SKILLS_REPO_ROOT
# overrides it (same convention as scripts/tag-released-skills.sh).

REPO_ROOT="${SKILLS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# Skills are visited in byte order on every machine.
export LC_ALL=C

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 <base-ref>" >&2
  exit 2
}

[[ $# -eq 1 && -n "$1" ]] || usage
base_ref="$1"

git_() { git -C "$REPO_ROOT" "$@"; }

git_ rev-parse --git-dir >/dev/null 2>&1 || fail "not a git repository: ${REPO_ROOT}"
git_ rev-parse -q --verify "${base_ref}^{commit}" >/dev/null 2>&1 ||
  fail "base ref does not resolve to a commit: ${base_ref}"
merge_base="$(git_ merge-base "$base_ref" HEAD 2>/dev/null)" ||
  fail "no merge base between ${base_ref} and HEAD"

# Print metadata.version of a skill's SKILL.md at a revision (empty if none).
version_at() {
  git_ show "$1:skills/$2/SKILL.md" 2>/dev/null | awk '
    NR == 1 { next }
    /^---$/ { exit }
    /^metadata:/ { in_meta = 1; next }
    in_meta && /^[^ \t]/ { exit }
    in_meta && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
  ' || true
}

# Is $1 strictly greater than $2 (both MAJOR.MINOR.PATCH)?
version_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"
  IFS=. read -r b1 b2 b3 <<<"$2"
  a1=$((10#$a1)); a2=$((10#$a2)); a3=$((10#$a3))
  b1=$((10#$b1)); b2=$((10#$b2)); b3=$((10#$b3))
  [[ $a1 -ne $b1 ]] && { [[ $a1 -gt $b1 ]]; return; }
  [[ $a2 -ne $b2 ]] && { [[ $a2 -gt $b2 ]]; return; }
  [[ $a3 -gt $b3 ]]
}

changed="$(git_ -c core.quotePath=off diff --no-renames --name-only "$merge_base" HEAD -- skills/ |
  awk -F/ 'NF >= 3 { print $2 }' | sort -u)"

if [[ -z "$changed" ]]; then
  echo "no skill folder changed"
  exit 0
fi

errors=0
skill_errors=0
err() {
  echo "error: $1: $2" >&2
  errors=1
  skill_errors=1
}

while IFS= read -r name; do
  if ! git_ cat-file -e "HEAD:skills/${name}/SKILL.md" 2>/dev/null; then
    echo "skip: ${name} removed"
    continue
  fi

  skill_errors=0
  head_v="$(version_at HEAD "$name")"
  head_ok=0
  if [[ -z "$head_v" ]]; then
    err "$name" "skills/${name}/SKILL.md has no metadata.version"
  elif ! [[ "$head_v" =~ $SEMVER_RE ]]; then
    err "$name" "metadata.version is not MAJOR.MINOR.PATCH: ${head_v}"
  else
    head_ok=1
  fi

  base_label="new"
  if [[ "$head_ok" -eq 1 ]] && git_ cat-file -e "${merge_base}:skills/${name}/SKILL.md" 2>/dev/null; then
    base_v="$(version_at "$merge_base" "$name")"
    if [[ "$base_v" =~ $SEMVER_RE ]]; then
      base_label="$base_v"
      if ! version_gt "$head_v" "$base_v"; then
        err "$name" "metadata.version ${head_v} is not greater than ${base_v} at the merge base"
      fi
    fi
  fi

  if ! changelog="$(git_ show "HEAD:skills/${name}/CHANGELOG.md" 2>/dev/null)"; then
    err "$name" "CHANGELOG.md is missing"
  else
    info="$(awk '
      /^## \[/ {
        if (seen && first == "") first = $0
        if ($0 ~ /^## \[Unreleased\]/) { seen = 1; in_unrel = 1 } else { in_unrel = 0 }
        next
      }
      in_unrel && /^[ \t]*[-*] / { entries++ }
      END { print seen + 0; print entries + 0; print first }
    ' <<<"$changelog")"
    seen="$(sed -n 1p <<<"$info")"
    entries="$(sed -n 2p <<<"$info")"
    first="$(sed -n 3p <<<"$info")"
    if [[ "$seen" -eq 0 ]]; then
      err "$name" "CHANGELOG.md has no ## [Unreleased] section"
    else
      if [[ "$head_ok" -eq 1 ]]; then
        prefix="## [${head_v}] - "
        date_part="${first#"$prefix"}"
        if [[ "$first" != "$prefix"* ]] || ! [[ "$date_part" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          err "$name" "CHANGELOG.md first release heading after Unreleased is not '## [${head_v}] - YYYY-MM-DD'"
        fi
      fi
      if [[ "$entries" -gt 0 ]]; then
        err "$name" "CHANGELOG.md has ${entries} entry line(s) under ## [Unreleased]; move them under the release heading"
      fi
    fi
  fi

  if [[ "$skill_errors" -eq 0 ]]; then
    echo "ok: ${name} ${base_label} -> ${head_v}"
  fi
done <<<"$changed"

exit "$errors"
