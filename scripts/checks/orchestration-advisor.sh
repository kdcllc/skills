#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/orchestration-advisor.sh [repo-root]
# Content-contract guards for the orchestration-advisor skill: required files,
# the procedure and report headings, the six shape names, the 18 signal keys in
# both the contract and the script, and no concrete model IDs in shipped docs.
# Run by scripts/validate-skills.sh. Needs only bash and grep.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SKILL_DIR="skills/orchestration-advisor"
SKILL="${ROOT}/${SKILL_DIR}"

fail() {
  echo "error: orchestration-advisor: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  "${SKILL_DIR}/SKILL.md"
  "${SKILL_DIR}/CHANGELOG.md"
  "${SKILL_DIR}/references/patterns.md"
  "${SKILL_DIR}/references/signals.md"
  "${SKILL_DIR}/scripts/inspect.sh"
)

# Procedure steps: each is the last words of a heading ("## Step 1 — Detect").
STEP_NAMES=(
  "Detect"
  "Inspect"
  "Ask about the workload"
  "Decide"
  "Report"
)

# Report headings: each is a whole "## <name>" line.
REPORT_HEADINGS=(
  "Recommendation"
  "Evidence"
  "Ruled out"
  "Harness notes"
  "Cost note"
  "Next step"
  "How to check this"
)

# Matched case-insensitively.
SHAPES=(
  "single agent plus skills"
  "generator-verifier"
  "orchestrator-subagent"
  "agent teams"
  "message bus"
  "shared state"
)

# The output contract of scripts/inspect.sh, in the order of references/signals.md.
SIGNAL_KEYS=(
  harness_claude
  harness_cursor
  harness_copilot
  harness_codex
  agent_kit_installed
  composer_crews
  agent_files
  claude_agent_files
  claude_agent_description_chars
  claude_agent_description_tokens_est
  skill_files
  mcp_servers
  test_paths
  ci_workflows
  lint_configs
  typecheck_configs
  package_manifests
  tracked_files
)

MODEL_ID_PATTERN='(claude|gpt|gemini|composer|opus|sonnet|haiku)-[0-9]'

check_required_paths() {
  local rel
  for rel in "${REQUIRED_PATHS[@]}"; do
    [[ -e "${ROOT}/${rel}" ]] || fail "missing required path: ${rel}"
  done
}

check_headings() {
  local headings name
  headings="$(grep -E '^#{1,6} ' "${SKILL}/SKILL.md" || true)"

  for name in "${STEP_NAMES[@]}"; do
    grep -qE "^#{1,6} Step [0-9]+ .* ${name}[[:space:]]*\$" <<<"$headings" ||
      fail "SKILL.md missing procedure step heading: ${name}"
  done

  for name in "${REPORT_HEADINGS[@]}"; do
    grep -qE "^## ${name}[[:space:]]*\$" <<<"$headings" ||
      fail "SKILL.md missing report heading: ## ${name}"
  done
}

check_shapes() {
  local shape
  for shape in "${SHAPES[@]}"; do
    grep -qiF -- "$shape" "${SKILL}/SKILL.md" ||
      fail "SKILL.md does not name the shape: ${shape}"
  done
}

# Each key is matched as a whole word, so agent_files is not satisfied by
# claude_agent_files: in signals.md as the backticked first cell of a table row,
# in inspect.sh as the key followed by "=" with no word character before it.
check_signal_keys() {
  local key
  for key in "${SIGNAL_KEYS[@]}"; do
    grep -qE "^\|[[:space:]]*\`${key}\`[[:space:]]*\|" "${SKILL}/references/signals.md" ||
      fail "references/signals.md has no table row for signal key: ${key}"
    grep -qE "(^|[^[:alnum:]_])${key}=" "${SKILL}/scripts/inspect.sh" ||
      fail "scripts/inspect.sh does not print signal key: ${key}"
  done
}

check_no_concrete_model_ids() {
  local matches
  matches="$(grep -rEn "$MODEL_ID_PATTERN" "${SKILL}/references" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "concrete model ID found in references/"
  fi
  matches="$(grep -En "$MODEL_ID_PATTERN" "${SKILL}/SKILL.md" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "concrete model ID found in SKILL.md"
  fi
}

check_required_paths
check_headings
check_shapes
check_signal_keys
check_no_concrete_model_ids
