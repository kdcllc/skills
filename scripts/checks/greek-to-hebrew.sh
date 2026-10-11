#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/greek-to-hebrew.sh [repo-root]
# Content-contract guards for the greek-to-hebrew skill: required files and no
# leftover references to the pre-import name. Run by scripts/validate-skills.sh.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SKILL_DIR="skills/greek-to-hebrew"

fail() {
  echo "error: greek-to-hebrew: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  "${SKILL_DIR}/SKILL.md"
  "${SKILL_DIR}/LICENSE.txt"
  "${SKILL_DIR}/references/tools.md"
  "${SKILL_DIR}/references/methodology.md"
)

# The pre-import skill name. Only the changelog may mention it.
OLD_NAME_PATTERN='bible-study-nt-hebrew-trace'

check_required_paths() {
  local rel
  for rel in "${REQUIRED_PATHS[@]}"; do
    [[ -e "${ROOT}/${rel}" ]] || fail "missing required path: ${rel}"
  done
}

check_old_name() {
  local matches
  matches="$(grep -rEn "$OLD_NAME_PATTERN" "${ROOT}/${SKILL_DIR}" \
    --exclude=CHANGELOG.md 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "old skill name found; use greek-to-hebrew"
  fi
}

check_required_paths
check_old_name
