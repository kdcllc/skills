#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/new-skill.sh <skill-name>
# Creates skills/<skill-name>/SKILL.md and CHANGELOG.md from templates/.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${REPO_ROOT}/templates/SKILL.md.tmpl"
CHANGELOG_TEMPLATE="${REPO_ROOT}/templates/CHANGELOG.md.tmpl"
NAME_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'

fail() {
  echo "error: $*" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <skill-name>" >&2
  exit 2
fi

name="$1"
skill_dir="${REPO_ROOT}/skills/${name}"

if (( ${#name} > 64 )) || [[ ! "$name" =~ $NAME_PATTERN ]]; then
  fail "'${name}' must be 1-64 characters of lowercase letters, digits, and single hyphens"
fi

[[ -f "$TEMPLATE" ]] || fail "missing template: templates/SKILL.md.tmpl"
[[ -f "$CHANGELOG_TEMPLATE" ]] || fail "missing template: templates/CHANGELOG.md.tmpl"
[[ ! -e "$skill_dir" ]] || fail "skills/${name} already exists"

title="$(awk -F- -v OFS=' ' '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1' <<<"$name")"
today="$(date +%Y-%m-%d)"

mkdir -p "$skill_dir"
sed -e "s/{{name}}/${name}/g" -e "s/{{title}}/${title}/g" "$TEMPLATE" >"${skill_dir}/SKILL.md"
sed -e "s/{{name}}/${name}/g" -e "s/{{date}}/${today}/g" "$CHANGELOG_TEMPLATE" >"${skill_dir}/CHANGELOG.md"

cat <<EOF
Created skills/${name}/SKILL.md and skills/${name}/CHANGELOG.md (version 0.1.0)

Next steps:
  1. Replace every TODO in skills/${name}/SKILL.md (the validator rejects a TODO description).
  2. Add this row to the Skills table in README.md:

| [${name}](skills/${name}/SKILL.md) | TODO | TODO | \`npx skills add kdcllc/skills --skill ${name}\` |

  3. Run: bash scripts/validate-skills.sh
  4. After it merges, tag the first release: bash scripts/release-skill.sh ${name} 0.1.0
EOF
