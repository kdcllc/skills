#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/terraform-azure-stack-conventions.sh [repo-root]
# Guards the terraform-azure stack-decomposition contract: one domain per
# stack, .tf written once per domain, per-environment tfvars, and cross-stack
# reads through azurerm data blocks only. Run by scripts/validate-skills.sh.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SKILL="${ROOT}/skills/terraform-azure"
TF_SKILL_DIRS=(
  "${ROOT}/skills/terraform-azure"
  "${ROOT}/skills/terraform-azure-modules"
  "${ROOT}/skills/terraform-azure-pipelines"
  "${ROOT}/skills/terraform-azure-upgrade"
)

fail() {
  echo "error: terraform-azure-stack-conventions: $*" >&2
  exit 1
}

CONVENTIONS="${SKILL}/references/ai-conventions.md"
PROCESS="${SKILL}/references/operating-process.md"
RG_LAYOUT="${SKILL}/references/resource-group-layout.md"
MAIN_SKILL="${SKILL}/SKILL.md"
STACK_MAIN="${SKILL}/assets/templates/stack/main.tf.tmpl"
STACK_DATA="${SKILL}/assets/templates/stack/data.tf.tmpl"
STACK_TFVARS="${SKILL}/assets/templates/stack/dev.tfvars.tmpl"
STACK_DECISION="${SKILL}/assets/templates/stack-decision.md"

# 1. The freeze documents must still carry the decomposition rules. If someone
#    edits these headings away, the agent loses the behaviour.
require_string() {
  local file="$1" needle="$2"
  [[ -f "$file" ]] || fail "missing file: ${file#"${ROOT}/"}"
  LC_ALL=C grep -qF -- "$needle" "$file" ||
    fail "${file#"${ROOT}/"} must document: ${needle}"
}

require_string "$CONVENTIONS" 'one domain per stack'
require_string "$CONVENTIONS" 'Domain catalog'
require_string "$CONVENTIONS" 'data blocks only'
require_string "$CONVENTIONS" '../../modules/<name>'
require_string "$CONVENTIONS" 'tfstate.{resource}.{domain}.{environment}'
require_string "$CONVENTIONS" 'envs/'
require_string "$CONVENTIONS" 'Resource group layout'
require_string "$CONVENTIONS" 'per-type'
require_string "$CONVENTIONS" 'rg_segment'

require_string "$PROCESS" 'One domain per stack'
require_string "$PROCESS" 'Cross-stack references'
require_string "$PROCESS" 'tfstate.{resource}.{domain}.{environment}'
require_string "$PROCESS" 'resource_group_layout'

require_string "$MAIN_SKILL" 'Rule 0 — decompose before you write'
require_string "$MAIN_SKILL" 'Domain catalog'
require_string "$MAIN_SKILL" 'Rule 2 — cross-stack reads are data blocks only'
require_string "$MAIN_SKILL" 'Resource group layout'

# 1b. Both resource group layouts stay documented, with the per-type default and
#     the catalog segment that makes per-type RG names reconstructible.
require_string "$RG_LAYOUT" 'per-type'
require_string "$RG_LAYOUT" 'single'
require_string "$RG_LAYOUT" 'rg_segment'
require_string "$RG_LAYOUT" 'resource_group_layout'

require_string "$STACK_MAIN" 'ONE DOMAIN PER STACK'
require_string "$STACK_DATA" 'terraform_remote_state'
require_string "$STACK_DATA" 'upstream_rg'
require_string "$STACK_TFVARS" 'envs/dev.tfvars'
require_string "$STACK_DECISION" 'resource_group_layout'

# 2. No shipped template, asset, or example may contain a live
#    terraform_remote_state block. Prose that forbids it is fine.
if grep -rEn 'data[[:space:]]+"terraform_remote_state"' "${TF_SKILL_DIRS[@]}" 2>/dev/null; then
  fail "terraform_remote_state block found — cross-stack reads are azurerm data blocks only"
fi

# 3. Superseded module source depth. Every stack now sits at resources/<domain>/,
#    so the only correct depth is ../../modules/.
if grep -rEn '\.\./\.\./\.\./modules' "${TF_SKILL_DIRS[@]}" 2>/dev/null; then
  fail "superseded module source depth — stacks at resources/<domain>/ use ../../modules/<name>"
fi

# 3b. Per-environment tfvars live in ONE envs/ folder per stack. The earlier
#     folder-per-environment shape (dev/dev.tfvars) must not reappear.
if grep -rEn '<env>/<env>\.tfvars|[^s]/dev/dev\.tfvars|[[:space:]]dev/dev\.tfvars|"dev/dev\.tfvars"' "${TF_SKILL_DIRS[@]}" 2>/dev/null; then
  fail "folder-per-environment tfvars found — use one envs/<env>.tfvars per stack"
fi

# 3c. The stack data.tf template defaults to the per-type layout, so the
#     single-layout resource-group data block must ship commented out. A live
#     block would silently make every generated stack single-RG.
if grep -En '^data "azurerm_resource_group"' "$STACK_DATA" 2>/dev/null; then
  fail "live azurerm_resource_group data block in stack/data.tf.tmpl — per-type is the default; keep the single-layout block commented"
fi

# 4. The superseded resources/environments/ layout may only appear where it is
#    being rejected. Anywhere else it would read as guidance.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! grep -qE 'superseded|Rejected|Do not use|do not use' <<<"$line"; then
    fail "resources/environments/ referenced outside a rejection: ${line}"
  fi
done < <(grep -rn 'resources/environments/' "${TF_SKILL_DIRS[@]}" 2>/dev/null || true)
