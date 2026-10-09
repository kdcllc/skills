#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/terraform-azure-pack.sh [repo-root]
# Content-contract guards for the terraform-azure* skills: required files,
# version pins shipped to consumers, destroy gates, the fail-closed fmt check,
# retired action majors, and banned strings. Run by scripts/validate-skills.sh.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

fail() {
  echo "error: terraform-azure-pack: $*" >&2
  exit 1
}

TF_SKILL_DIRS=(
  skills/terraform-azure
  skills/terraform-azure-modules
  skills/terraform-azure-pipelines
  skills/terraform-azure-upgrade
)

REQUIRED_PATHS=(
  skills/terraform-azure/SKILL.md
  skills/terraform-azure/references/operating-process.md
  skills/terraform-azure/references/ai-conventions.md
  skills/terraform-azure/references/azure-connections.md
  skills/terraform-azure/references/resource-group-layout.md
  skills/terraform-azure/references/using-the-pack.md
  skills/terraform-azure/references/deep-dive.md
  skills/terraform-azure/assets/templates/module/providers.tf.tmpl
  skills/terraform-azure/assets/templates/stack/backend.tf.tmpl
  skills/terraform-azure/assets/templates/stack/main.tf.tmpl
  skills/terraform-azure/assets/templates/stack/data.tf.tmpl
  skills/terraform-azure/assets/templates/stack-decision.md
  skills/terraform-azure/scripts/bootstrap-tfstate.sh
  skills/terraform-azure/scripts/bootstrap-tfstate.ps1
  skills/terraform-azure/scripts/create-azure-oidc.sh
  skills/terraform-azure/scripts/create-azure-oidc.ps1
  skills/terraform-azure-modules/SKILL.md
  skills/terraform-azure-modules/references/reference.md
  skills/terraform-azure-pipelines/SKILL.md
  skills/terraform-azure-upgrade/SKILL.md
  skills/terraform-azure-upgrade/references/reference.md
  skills/terraform-azure-pipelines/assets/tf-deploy-base.yaml
  skills/terraform-azure-pipelines/assets/terraform-stack.yaml
  skills/terraform-azure-pipelines/assets/examples/terraform-domain.yaml
  skills/terraform-azure-pipelines/assets/azure-pipelines.yaml
  skills/terraform-azure-pipelines/assets/gitlab-ci-terraform-template.yml
)

# Destroy is offered on every host, and every host requires a confirmation input the
# operator sets on top of choosing destroy. Losing that input is a regression.
DESTROY_GATE_CHECKS=(
  "skills/terraform-azure-pipelines/assets/tf-deploy-base.yaml|confirm_destroy"
  "skills/terraform-azure-pipelines/assets/examples/terraform-domain.yaml|confirm_destroy"
  "skills/terraform-azure-pipelines/assets/terraform-stack.yaml|confirm_destroy"
  "skills/terraform-azure-pipelines/assets/azure-pipelines.yaml|confirmDestroy"
  "skills/terraform-azure-pipelines/assets/gitlab-ci-terraform-template.yml|CONFIRM_DESTROY"
)

# terraform fmt -check must run on every host and must fail the job. Assets carrying a
# runner-level soft-fail switch alongside it would silently downgrade the policy.
FMT_CHECK_FILES=(
  skills/terraform-azure-pipelines/assets/tf-deploy-base.yaml
  skills/terraform-azure-pipelines/assets/azure-pipelines.yaml
  skills/terraform-azure-pipelines/assets/gitlab-ci-terraform-template.yml
)
FMT_SOFT_FAIL_PATTERN='continue-on-error: true|allow_failure: true'

# GitHub-hosted runners warn when an action's major still targets Node 20, and will
# eventually stop running them. Assets must not reintroduce a retired major. Add a
# line here when a major goes Node 20-only; drop nothing, majors do not un-deprecate.
DEPRECATED_ACTION_MAJORS='actions/checkout@v[1-4]|azure/login@v[12]|hashicorp/setup-terraform@v[1-3]|actions/upload-artifact@v[1-4]'

BANNED_PATTERN='vscode/|chrisdias\.|SugarBreeze|SB Corporate'

# Canonical pins shipped to consumers; every duplicate below must agree.
# Bumping one is a release decision for every skill that carries it — change the
# constant and the check forces every copy to follow.
AZURERM_PIN='>= 5.0.0, < 6.0.0'
TF_REQ_PIN='>= 1.9.0, < 2.0.0'
TF_CLI_PIN='1.15.8'

AZURERM_PIN_FILES=(
  skills/terraform-azure/SKILL.md
  skills/terraform-azure/references/operating-process.md
  skills/terraform-azure/references/deep-dive.md
  skills/terraform-azure/assets/templates/module/providers.tf.tmpl
  skills/terraform-azure/assets/templates/stack/providers.tf.tmpl
  skills/terraform-azure-modules/SKILL.md
  skills/terraform-azure-modules/references/reference.md
  skills/terraform-azure-upgrade/SKILL.md
  skills/terraform-azure-upgrade/references/reference.md
)

TF_REQ_PIN_FILES=(
  skills/terraform-azure/SKILL.md
  skills/terraform-azure/references/deep-dive.md
  skills/terraform-azure/assets/templates/module/providers.tf.tmpl
  skills/terraform-azure/assets/templates/stack/providers.tf.tmpl
  skills/terraform-azure-modules/SKILL.md
  skills/terraform-azure-modules/references/reference.md
  skills/terraform-azure-upgrade/SKILL.md
  skills/terraform-azure-upgrade/references/reference.md
)

TF_CLI_PIN_FILES=(
  skills/terraform-azure/SKILL.md
  skills/terraform-azure/references/deep-dive.md
  skills/terraform-azure-pipelines/SKILL.md
  skills/terraform-azure-pipelines/assets/tf-deploy-base.yaml
  skills/terraform-azure-pipelines/assets/azure-pipelines.yaml
  skills/terraform-azure-pipelines/assets/gitlab-ci-terraform-template.yml
  skills/terraform-azure-pipelines/assets/examples/dev-azure-pipelines.yaml
  skills/terraform-azure-upgrade/SKILL.md
)

tf_skill_paths() {
  local rel
  for rel in "${TF_SKILL_DIRS[@]}"; do
    printf '%s\n' "${ROOT}/${rel}"
  done
}

check_required_paths() {
  local rel
  for rel in "${REQUIRED_PATHS[@]}"; do
    [[ -e "${ROOT}/${rel}" ]] || fail "missing required path: ${rel}"
  done
}

check_pin() {
  local label="$1" pin="$2" rel
  shift 2
  for rel in "$@"; do
    [[ -f "${ROOT}/${rel}" ]] || fail "missing pin-check path: ${rel}"
    grep -qF -- "$pin" "${ROOT}/${rel}" || fail "${label} pin drift (want '${pin}'): ${rel}"
  done
}

check_pins() {
  check_pin azurerm "$AZURERM_PIN" "${AZURERM_PIN_FILES[@]}"
  check_pin required_version "$TF_REQ_PIN" "${TF_REQ_PIN_FILES[@]}"
  check_pin "terraform CLI" "$TF_CLI_PIN" "${TF_CLI_PIN_FILES[@]}"
}

check_destroy_gates() {
  local entry rel token
  for entry in "${DESTROY_GATE_CHECKS[@]}"; do
    rel="${entry%%|*}"
    token="${entry##*|}"
    [[ -f "${ROOT}/${rel}" ]] || fail "missing destroy-gate path: ${rel}"
    grep -qF -- "$token" "${ROOT}/${rel}" || fail "destroy gate missing '${token}': ${rel}"
  done
}

check_fmt_is_hard() {
  local rel full
  for rel in "${FMT_CHECK_FILES[@]}"; do
    full="${ROOT}/${rel}"
    [[ -f "$full" ]] || fail "missing fmt-check path: ${rel}"
    grep -qF 'fmt -check -recursive' "$full" || fail "no 'terraform fmt -check -recursive' step: ${rel}"
    if grep -qE "$FMT_SOFT_FAIL_PATTERN" "$full"; then
      fail "fmt policy is fail-closed; remove the soft-fail switch: ${rel}"
    fi
  done
}

check_action_majors() {
  local matches dirs
  mapfile -t dirs < <(tf_skill_paths)
  matches="$(grep -rEn "$DEPRECATED_ACTION_MAJORS" "${dirs[@]}" "${ROOT}/.github" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "action major targets Node 20; bump to the current major"
  fi
}

check_banned_strings() {
  local matches dirs
  mapfile -t dirs < <(tf_skill_paths)
  matches="$(grep -rEn "$BANNED_PATTERN" "${dirs[@]}" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "banned string found in a terraform-azure skill"
  fi
}

check_required_paths
check_pins
check_destroy_gates
check_fmt_is_hard
check_action_majors
check_banned_strings
