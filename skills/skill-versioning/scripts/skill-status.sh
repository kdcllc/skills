#!/usr/bin/env bash
set -euo pipefail

# Usage: skill-status.sh [--root <repo-root>] [skill-name ...]
# Reports, for each skills/<name>/ folder in a git repo, its metadata.version,
# its latest <name>/vX.Y.Z tag, whether the folder changed since that tag or
# has uncommitted edits, how many entries sit under ## [Unreleased] in its
# CHANGELOG.md, and what to do next. Read-only; requires bash, git, and awk.

root=""
names=()
while (( $# > 0 )); do
  case "$1" in
    --root) root="${2:?--root needs a path}"; shift 2 ;;
    -h|--help) sed -n '4,8p' "$0"; exit 0 ;;
    *) names+=("$1"); shift ;;
  esac
done

root="${root:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[[ -d "${root}/skills" ]] || { echo "error: no skills/ folder under ${root}" >&2; exit 1; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "error: ${root} is not a git repository" >&2; exit 1; }

if (( ${#names[@]} == 0 )); then
  for dir in "${root}"/skills/*/; do
    [[ -f "${dir}SKILL.md" ]] && names+=("$(basename "$dir")")
  done
fi

skill_version() {
  awk '
    NR == 1 { next }
    /^---$/ { exit }
    /^metadata:/ { in_meta = 1; next }
    in_meta && /^[^ \t]/ { exit }
    in_meta && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
  ' "$1"
}

unreleased_entries() {
  awk '
    /^## \[Unreleased\]/ { on = 1; next }
    on && /^## \[/ { exit }
    on && /^[ \t]*[-*] / { n++ }
    END { print n + 0 }
  ' "$1"
}

latest_tag() {
  git -C "$root" tag --list "$1/v*" --sort=-v:refname | head -n 1
}

printf '%-28s %-9s %-34s %-8s %-6s %-10s %s\n' SKILL VERSION LAST_TAG CHANGED DIRTY UNRELEASED NEXT
for name in "${names[@]}"; do
  rel="skills/${name}"
  skill_md="${root}/${rel}/SKILL.md"
  changelog="${root}/${rel}/CHANGELOG.md"
  if [[ ! -f "$skill_md" ]]; then
    printf '%-28s %s\n' "$name" "no such skill"
    continue
  fi

  version="$(skill_version "$skill_md")"
  tag="$(latest_tag "$name")"
  entries="-"
  [[ -f "$changelog" ]] && entries="$(unreleased_entries "$changelog")"

  if [[ -n "$tag" ]]; then
    changed="$(git -C "$root" rev-list --count "${tag}..HEAD" -- "$rel")"
  else
    changed="$(git -C "$root" rev-list --count HEAD -- "$rel" 2>/dev/null || echo 0)"
  fi
  dirty="no"
  [[ -n "$(git -C "$root" status --porcelain -- "$rel")" ]] && dirty="yes"

  if [[ -z "$version" || ! -f "$changelog" ]]; then
    next="adopt versioning (add metadata.version and CHANGELOG.md)"
  elif [[ "$entries" != "0" ]]; then
    next="ready to release (pick the bump from Unreleased)"
  elif [[ -z "$tag" ]]; then
    next="tag first release ${name}/v${version}"
  elif [[ "$changed" != "0" || "$dirty" == "yes" ]]; then
    next="record changes under Unreleased"
  elif [[ "$tag" != "${name}/v${version}" ]]; then
    next="mismatch: metadata.version ${version} but latest tag is ${tag}"
  else
    next="up to date"
  fi

  printf '%-28s %-9s %-34s %-8s %-6s %-10s %s\n' "$name" "${version:--}" "${tag:--}" "$changed" "$dirty" "$entries" "$next"
done
