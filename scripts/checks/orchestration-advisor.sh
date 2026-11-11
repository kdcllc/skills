#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/checks/orchestration-advisor.sh [repo-root]
# Content-contract guards for the orchestration-advisor skill: required files,
# the procedure step headings (real headings, outside fenced blocks), the seven
# report headings (inside a fenced block, in order), the six shape names (in the
# body, not the frontmatter), the 18 signal keys in both the contract and the
# script, and no concrete model IDs in the shipped docs or scripts.
# Run by scripts/validate-skills.sh. Needs only bash, grep and awk.
# Written for bash 3.2 and POSIX grep and awk; it creates no file in the repository.

SELF_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SELF_DIR" != "${BASH_SOURCE[0]}" ]] || SELF_DIR="."
ROOT="${1:-$(cd "${SELF_DIR}/../.." && pwd)}"
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

# Report headings: each is a whole "## <name>" line inside a fenced block. The
# first occurrence of each must come in this order.
REPORT_HEADINGS=(
  "Recommendation"
  "Evidence"
  "Ruled out"
  "Harness notes"
  "Cost note"
  "Next step"
  "How to check this"
)

# Matched case-insensitively, in the body of SKILL.md only.
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

# Prints lines of SKILL.md. One trailing carriage return is removed from every
# line first, so a file with CRLF line endings reads like one with LF endings.
# The frontmatter is line 1 through the next line that is exactly "---"; the
# body is every line after it. With no closing line the body is empty.
# A fence line is a line that has, after optional leading spaces and tabs, three
# or more backticks or three or more tildes. Outside a block, a fence line opens
# one.
# A block opened by a backtick fence is closed only by a backtick fence line,
# and a block opened by a tilde fence only by a tilde fence line; a fence line
# of the other kind inside a block is content. A block that is never closed
# runs to the end of the file.
#   body    — every body line
#   outside — body lines outside fenced blocks (fence lines excluded)
#   inside  — body lines inside fenced blocks (opening and closing fence lines
#             excluded)
skill_lines() {
  awk -v want="$1" '
    { sub(/\r$/, "") }
    !started { if (NR > 1 && $0 == "---") started = 1; next }
    want == "body" { print; next }
    {
      kind = ""
      if ($0 ~ /^[ \t]*```/) kind = "backtick"
      else if ($0 ~ /^[ \t]*~~~/) kind = "tilde"
    }
    kind != "" && opened == "" { opened = kind; next }
    kind != "" && opened == kind { opened = ""; next }
    want == "inside" && opened != "" { print }
    want == "outside" && opened == "" { print }
  ' "${SKILL}/SKILL.md"
}

# Prints the number of the first line on standard input that is exactly the
# given text, trailing spaces, tabs and carriage returns allowed; prints nothing
# when there is none.
first_line_number() {
  awk -v want="$1" '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    line == want { print NR; exit }
  '
}

check_required_paths() {
  local rel
  for rel in "${REQUIRED_PATHS[@]}"; do
    [[ -e "${ROOT}/${rel}" ]] || fail "missing required path: ${rel}"
  done
}

check_headings() {
  local outside inside name at previous
  outside="$(skill_lines outside)"
  inside="$(skill_lines inside)"

  for name in "${STEP_NAMES[@]}"; do
    grep -qE "^#{1,6} Step [0-9]+ .* ${name}[[:space:]]*\$" <<<"$outside" ||
      fail "SKILL.md missing procedure step heading: ${name}"
  done

  # Presence of all seven first, then their order.
  for name in "${REPORT_HEADINGS[@]}"; do
    at="$(first_line_number "## ${name}" <<<"$inside")"
    [[ -n "$at" ]] || fail "SKILL.md missing report heading: ## ${name}"
  done

  previous=0
  for name in "${REPORT_HEADINGS[@]}"; do
    at="$(first_line_number "## ${name}" <<<"$inside")"
    [[ "$at" -gt "$previous" ]] || fail "SKILL.md report headings are out of order"
    previous="$at"
  done
}

check_shapes() {
  local body shape
  body="$(skill_lines body)"
  for shape in "${SHAPES[@]}"; do
    grep -qiF -- "$shape" <<<"$body" ||
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

# Prints "path:line:text" for every line matching the model-ID pattern in every
# regular file under the given directory, hidden files included. Symbolic links
# of every kind are skipped: a link to a file is not read and a link to a
# directory is not entered. /dev/null as a second operand makes grep print the
# path.
model_id_matches_under() {
  local dir="$1" entry
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    if [[ -L "$entry" ]]; then
      continue
    elif [[ -d "$entry" ]]; then
      model_id_matches_under "$entry"
    elif [[ -f "$entry" ]]; then
      grep -En "$MODEL_ID_PATTERN" "$entry" /dev/null || true
    fi
  done
}

check_no_concrete_model_ids() {
  local matches
  matches="$(model_id_matches_under "${SKILL}/references" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "concrete model ID found in references/"
  fi
  matches="$(grep -En "$MODEL_ID_PATTERN" "${SKILL}/SKILL.md" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "concrete model ID found in SKILL.md"
  fi
  matches="$(model_id_matches_under "${SKILL}/scripts" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    fail "concrete model ID found in scripts/"
  fi
}

check_required_paths
check_headings
check_shapes
check_signal_keys
check_no_concrete_model_ids
