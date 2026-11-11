#!/usr/bin/env bash
# Usage: inspect.sh [project-root]
#
# Prints the inspection signals of a project as `key=value` lines on standard
# output: 18 keys, always all of them, always in the same order. The output
# contract (every key, how it is computed, the skip list, the symlink rule and
# the `unknown` cases) lives in ../references/signals.md. Change that file and
# this script together.
#
# project-root defaults to `.` (the current directory).
#
# Read-only and offline: this script creates, modifies and deletes nothing, and
# makes no network call. `jq` and `git` are optional; without them `mcp_servers`
# and `tracked_files` print `unknown` as the contract says.
#
# Exit codes:
#   0  success, all 18 lines were printed
#   2  the argument is not an existing directory, or more than one argument
#      was given (a usage line is printed on standard error)
#
# Written for bash 3.2: only features that version has.
set -euo pipefail

usage() {
  echo "Usage: inspect.sh [project-root]" >&2
  exit 2
}

if [ "$#" -gt 1 ]; then
  usage
fi

ROOT="${1-.}"

if [ ! -d "${ROOT}" ]; then
  echo "inspect.sh: not an existing directory: ${ROOT}" >&2
  usage
fi

# Every path below is relative to the project root. Walking from `.` also keeps
# a root that is itself named like a skipped directory (`build`, `dist`) from
# being pruned by its own name.
unset CDPATH
if ! cd -- "${ROOT}" 2>/dev/null; then
  echo "inspect.sh: cannot enter directory: ${ROOT}" >&2
  usage
fi

# --- helpers -----------------------------------------------------------------

# Line count of standard input as a bare integer (BSD wc pads with spaces).
count_lines() {
  wc -l | tr -d '[:space:]'
}

# Number of distinct lines on standard input.
count_distinct() {
  LC_ALL=C sort -u | count_lines
}

# Number of arguments that are existing files. Callers pass shell globs; a glob
# that matches nothing stays literal and is simply not a file.
count_files() {
  local n=0 f
  for f in "$@"; do
    if [ -f "${f}" ]; then
      n=$((n + 1))
    fi
  done
  echo "${n}"
}

# 1 when any argument exists, else 0. A trailing slash asks for a directory.
any_exists() {
  local p
  for p in "$@"; do
    case "${p}" in
      */)
        if [ -d "${p}" ]; then
          echo 1
          return 0
        fi
        ;;
      *)
        if [ -e "${p}" ]; then
          echo 1
          return 0
        fi
        ;;
    esac
  done
  echo 0
}

# Agent definition files directly inside one harness agent folder, following
# symbolic links. A walk error (a link cycle, an unreadable entry) is ignored.
list_agent_files() {
  if [ -d "$1" ]; then
    find -L "$1" -mindepth 1 -maxdepth 1 -type f \
      \( -name '*.md' -o -name '*.toml' \) -print 2>/dev/null || true
  fi
}

# Every SKILL.md under one skill root, following symbolic links and skipping
# the contract's skip list. A SKILL.md directly inside the root is left out: the
# contract counts directories under a root, not the root. No -mindepth here,
# because it would also switch off -prune for the root's direct children.
# A walk error (a link cycle) is ignored.
list_skill_files() {
  if [ -d "$1" ]; then
    find -L "$1" \
      \( -type d \( -name .git -o -name node_modules -o -name vendor \
         -o -name dist -o -name build -o -name .venv \) -prune \) \
      -o \( -type f -name SKILL.md ! -path "$1/SKILL.md" -print \) \
      2>/dev/null || true
  fi
}

# Server count of one MCP configuration file: the number of keys under the
# given top-level member. Prints nothing when the file is not valid JSON.
mcp_count() {
  jq --arg k "$2" \
    'if type == "object" then (.[$k] | if type == "object" then length else 0 end) else 0 end' \
    "$1" 2>/dev/null || true
}

# --- harness and existing orchestration ---------------------------------------

v_harness_claude="$(any_exists .claude/ CLAUDE.md)"
v_harness_cursor="$(any_exists .cursor/)"
v_harness_copilot="$(any_exists .github/copilot-instructions.md .github/agents/)"
v_harness_codex="$(any_exists .codex/ AGENTS.md)"
v_agent_kit_installed="$(any_exists orchestration-kit.manifest.json)"
v_composer_crews="$(count_files .agent-composer/*.crew.yaml)"

# --- agents --------------------------------------------------------------------

# Distinct names: the file name with its longest matching suffix removed.
v_agent_files="$(
  {
    list_agent_files .claude/agents
    list_agent_files .cursor/agents
    list_agent_files .github/agents
    list_agent_files .codex/agents
  } | awk '{
    n = $0
    sub(/.*\//, "", n)
    if (n ~ /\.agent\.md$/) n = substr(n, 1, length(n) - 9)
    else if (n ~ /\.md$/) n = substr(n, 1, length(n) - 3)
    else if (n ~ /\.toml$/) n = substr(n, 1, length(n) - 5)
    print n
  }' | count_distinct
)"

v_claude_agent_files=0
v_description_chars=0
if [ -d .claude/agents ]; then
  v_claude_agent_files="$(
    { find -L .claude/agents -mindepth 1 -maxdepth 1 -type f -name '*.md' \
        -print 2>/dev/null || true; } | count_lines
  )"
  # The single-line `description:` value of each file's frontmatter, trimmed and
  # with surrounding quotes removed, concatenated and counted by `wc -m`.
  v_description_chars="$(
    { find -L .claude/agents -mindepth 1 -maxdepth 1 -type f -name '*.md' \
        -exec awk '
          FNR == 1 { infm = 0; found = 0 }
          {
            line = $0
            sub(/\r$/, "", line)
          }
          FNR == 1 {
            if (line ~ /^---[ \t]*$/) infm = 1
            next
          }
          !infm || found { next }
          line ~ /^(---|\.\.\.)[ \t]*$/ { infm = 0; next }
          line ~ /^description:/ {
            v = line
            sub(/^description:/, "", v)
            sub(/^[ \t]+/, "", v)
            sub(/[ \t]+$/, "", v)
            first = substr(v, 1, 1)
            last = substr(v, length(v), 1)
            if (length(v) != 1 && first == last && (first == "\"" || first == "\047")) {
              v = substr(v, 2, length(v) - 2)
            }
            printf "%s", v
            found = 1
          }
        ' {} + 2>/dev/null || true; } | wc -m | tr -d '[:space:]'
  )"
fi
v_description_tokens=$((v_description_chars / 4))

# --- skills --------------------------------------------------------------------

# Distinct names of the directories that directly contain a SKILL.md.
v_skill_files="$(
  {
    list_skill_files .claude/skills
    list_skill_files .cursor/skills
    list_skill_files .github/skills
    list_skill_files .agents/skills
    list_skill_files .codex/skills
  } | awk '{
    n = $0
    sub(/\/SKILL\.md$/, "", n)
    sub(/.*\//, "", n)
    print n
  }' | count_distinct
)"

# --- MCP servers ---------------------------------------------------------------

v_mcp_servers=0
mcp_present=0
for mcp_file in .mcp.json .cursor/mcp.json .vscode/mcp.json; do
  if [ -f "${mcp_file}" ]; then
    mcp_present=1
  fi
done
if [ "${mcp_present}" -eq 1 ]; then
  if command -v jq >/dev/null 2>&1; then
    for mcp_file in .mcp.json .cursor/mcp.json .vscode/mcp.json; do
      if [ ! -f "${mcp_file}" ]; then
        continue
      fi
      case "${mcp_file}" in
        .vscode/mcp.json) mcp_key="servers" ;;
        *) mcp_key="mcpServers" ;;
      esac
      mcp_n="$(mcp_count "${mcp_file}" "${mcp_key}")"
      case "${mcp_n}" in
        '' | *[!0-9]*)
          # Not valid JSON (or not a single JSON document).
          v_mcp_servers="unknown"
          break
          ;;
        *)
          v_mcp_servers=$((v_mcp_servers + mcp_n))
          ;;
      esac
    done
  else
    v_mcp_servers="unknown"
  fi
fi

# --- tests, CI, lint, type check, manifests --------------------------------------

# Depth 1 or 2, symbolic links not followed, skip list applied.
v_test_paths="$(
  { find . -maxdepth 2 \
      \( -type d \( -name .git -o -name node_modules -o -name vendor \
         -o -name dist -o -name build -o -name .venv \) -prune \) \
      -o \( -type d \( -name test -o -name tests -o -name __tests__ \
         -o -name spec \) -print \) 2>/dev/null || true; } | count_lines
)"

v_ci_workflows="$(count_files .github/workflows/*.yml .github/workflows/*.yaml \
  .gitlab-ci.yml azure-pipelines.yml)"

v_lint_configs="$(count_files .eslintrc* eslint.config.* biome.json ruff.toml \
  .ruff.toml .flake8 .golangci.yml .golangci.yaml .shellcheckrc)"

v_typecheck_configs="$(count_files tsconfig.json mypy.ini pyrightconfig.json)"

# To depth 4, symbolic links not followed, skip list applied.
v_package_manifests="$(
  { find . -maxdepth 4 \
      \( -type d \( -name .git -o -name node_modules -o -name vendor \
         -o -name dist -o -name build -o -name .venv \) -prune \) \
      -o \( -type f \( -name package.json -o -name pyproject.toml \
         -o -name go.mod -o -name Cargo.toml -o -name '*.csproj' \) \
         -print \) 2>/dev/null || true; } | count_lines
)"

# --- repository size -------------------------------------------------------------

v_tracked_files="unknown"
if command -v git >/dev/null 2>&1; then
  inside="$(GIT_OPTIONAL_LOCKS=0 git rev-parse --is-inside-work-tree 2>/dev/null || true)"
  if [ "${inside}" = "true" ]; then
    if tracked="$(GIT_OPTIONAL_LOCKS=0 git ls-files 2>/dev/null)"; then
      if [ -n "${tracked}" ]; then
        v_tracked_files="$(printf '%s\n' "${tracked}" | count_lines)"
      else
        v_tracked_files=0
      fi
    fi
  fi
fi

# --- output: the 18 keys, in the order of references/signals.md ------------------

echo "harness_claude=${v_harness_claude}"
echo "harness_cursor=${v_harness_cursor}"
echo "harness_copilot=${v_harness_copilot}"
echo "harness_codex=${v_harness_codex}"
echo "agent_kit_installed=${v_agent_kit_installed}"
echo "composer_crews=${v_composer_crews}"
echo "agent_files=${v_agent_files}"
echo "claude_agent_files=${v_claude_agent_files}"
echo "claude_agent_description_chars=${v_description_chars}"
echo "claude_agent_description_tokens_est=${v_description_tokens}"
echo "skill_files=${v_skill_files}"
echo "mcp_servers=${v_mcp_servers}"
echo "test_paths=${v_test_paths}"
echo "ci_workflows=${v_ci_workflows}"
echo "lint_configs=${v_lint_configs}"
echo "typecheck_configs=${v_typecheck_configs}"
echo "package_manifests=${v_package_manifests}"
echo "tracked_files=${v_tracked_files}"
