#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/azure-rbac-least-privilege.sh [repo-root]
# Content-contract guards for the azure-rbac-least-privilege skill: required files,
# snapshot shape, and no leftover references to the pre-import name. The full
# corpus check (node scripts/validate.js) takes ~40s, so it is not run here.
# Run by scripts/validate-skills.sh.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SKILL_DIR="skills/azure-rbac-least-privilege"

fail() {
  echo "error: azure-rbac-least-privilege: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  "${SKILL_DIR}/SKILL.md"
  "${SKILL_DIR}/README.md"
  "${SKILL_DIR}/package.json"
  "${SKILL_DIR}/references/ALGORITHM.md"
  "${SKILL_DIR}/references/DATA-REFRESH.md"
  "${SKILL_DIR}/references/OPERATOR-GUIDE.md"
  "${SKILL_DIR}/references/data/permissions.json"
  "${SKILL_DIR}/references/data/roles.json"
  "${SKILL_DIR}/references/data/roles-extended.json"
  "${SKILL_DIR}/scripts/lib/rbac.js"
  "${SKILL_DIR}/scripts/match-roles.js"
  "${SKILL_DIR}/scripts/validate.js"
  "${SKILL_DIR}/scripts/extend-roles-data.js"
  "${SKILL_DIR}/scripts/generate-json.sh"
)

# The pre-import skill name and its npm bin. Only the changelog may mention them.
OLD_NAME_PATTERN='azure-rbac-role-match'

check_required_paths() {
  local rel
  for rel in "${REQUIRED_PATHS[@]}"; do
    [[ -e "${ROOT}/${rel}" ]] || fail "missing required path: ${rel}"
  done
}

check_snapshot_shape() {
  local data="${ROOT}/${SKILL_DIR}/references/data"

  jq -e '(.lastUpdated | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and (.roles | type == "array" and length > 0)' \
    "${data}/roles-extended.json" >/dev/null ||
    fail "roles-extended.json needs an ISO lastUpdated and a non-empty roles array"
  jq -e '.roles | all(has("matchingPermissionsTotal") and has("privileged"))' \
    "${data}/roles-extended.json" >/dev/null ||
    fail "roles-extended.json roles must carry matchingPermissionsTotal and privileged; rerun npm run extend-data"
  jq -e 'type == "array" and length > 0' "${data}/roles.json" >/dev/null ||
    fail "roles.json must be a non-empty array"
  jq -e 'type == "array" and length > 0' "${data}/permissions.json" >/dev/null ||
    fail "permissions.json must be a non-empty array"
}

check_old_name() {
  local matches
  matches="$(grep -rEn "$OLD_NAME_PATTERN" "${ROOT}/${SKILL_DIR}" \
    --exclude=CHANGELOG.md --exclude-dir=data 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "old skill name found; use azure-rbac-least-privilege"
  fi
}

check_required_paths
check_snapshot_shape
check_old_name
