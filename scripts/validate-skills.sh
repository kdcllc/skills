#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/validate-skills.sh [repo-root]
# Checks repo layout, SKILL.md frontmatter, per-skill versions and changelogs,
# the README catalog, and the Claude Code / Cursor marketplace manifests, then
# runs every skill-specific guard in scripts/checks/. Requires bash and jq.

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

NAME_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
SEMVER_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
MAX_NAME_LENGTH=64
MAX_DESCRIPTION_LENGTH=1024
MAX_SKILL_LINES=500
SPEC_KEYS=(name description license compatibility metadata allowed-tools)

# Folders the Skills CLI scans; anything committed here would be published.
AGENT_SKILL_DIRS=(
  .agents/skills
  .claude/skills
  .codex/skills
  .cursor/skills
  .gemini/skills
  .github/skills
  .kiro/skills
  .windsurf/skills
)

CLAUDE_RESERVED_MARKETPLACES=(
  agent-skills
  anthropic-agent-skills
  claude-code-plugins
  claude-plugins-official
  gh
  github
  inline
  npm
  skills-dir
)

CURSOR_MARKETPLACE_KEYS='["name","owner","metadata","plugins"]'
CURSOR_ENTRY_KEYS='["name","source","description","minClientVersions"]'
CURSOR_PLUGIN_KEYS='["name","displayName","description","version","minClientVersions","author","publisher","homepage","repository","license","logo","keywords","category","tags","commands","agents","skills","rules","hooks","variables","mcpServers"]'

errors=0

error() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

# Prints the YAML frontmatter body (between the opening and closing ---).
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$1"
}

has_closed_frontmatter() {
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$1"
}

# Prints a top-level scalar value, folding block (>-, |) and continuation lines.
frontmatter_value() {
  awk -v key="$2" '
    found && /^[^ \t]/ { exit }
    found {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line != "") out = out (out == "" ? "" : " ") line
      next
    }
    index($0, key ":") == 1 {
      val = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", val)
      sub(/[ \t]+$/, "", val)
      found = 1
      out = (val ~ /^[>|][-+]?$/) ? "" : val
      next
    }
    END { if (found) print out }
  ' <<<"$1"
}

# Prints a scalar nested one level under metadata: (for example metadata.version).
metadata_value() {
  awk -v key="$2" '
    /^metadata:/ { in_meta = 1; next }
    in_meta && /^[^ \t]/ { exit }
    in_meta && $1 == key ":" {
      val = $0
      sub(/^[ \t]+[^:]+:[ \t]*/, "", val)
      sub(/[ \t]+$/, "", val)
      print val
      exit
    }
  ' <<<"$1"
}

# Prints the first released version heading (## [X.Y.Z]) in a changelog.
latest_changelog_version() {
  awk '
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
      v = $2
      gsub(/[][]/, "", v)
      print v
      exit
    }
  ' "$1"
}

unquote() {
  local value="$1"
  if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Resolves a manifest path ("./x") against a base directory.
resolve_path() {
  local base="$1" rel="$2"
  rel="${rel#./}"
  rel="${rel%/}"
  if [[ -z "$rel" || "$rel" == "." ]]; then
    printf '%s' "$base"
  else
    printf '%s/%s' "$base" "$rel"
  fi
}

check_repo_layout() {
  local rel dir

  if [[ -f "${ROOT}/SKILL.md" ]]; then
    error "SKILL.md at the repo root makes the Skills CLI treat this as a single-skill repo; move it to skills/<name>/"
  fi

  for dir in "${ROOT}"/*/; do
    [[ -f "${dir}SKILL.md" ]] || continue
    rel="${dir#"${ROOT}/"}"
    error "${rel}SKILL.md is discovered by the Skills CLI; skills must live in skills/<name>/"
  done

  # Inside a git work tree only tracked files reach the Skills CLI, so a
  # gitignored local install (the agent-kit dogfood instance) is allowed.
  local in_git=0
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1

  for rel in "${AGENT_SKILL_DIRS[@]}"; do
    if (( in_git )); then
      if [[ -n "$(git -C "$ROOT" ls-files -- "$rel")" ]]; then
        error "${rel}/ has tracked files; the Skills CLI scans it and would publish them. Untrack it and move its skills to skills/<name>/"
      fi
    elif [[ -d "${ROOT}/${rel}" ]]; then
      error "${rel}/ is scanned by the Skills CLI and would be published; remove it or move its skills to skills/<name>/"
    fi
  done
}

check_skill() {
  local dir="$1"
  local dir_name rel skill_md fm key name description license allowed_tools line_count version changelog latest

  dir_name="$(basename "$dir")"
  rel="skills/${dir_name}"
  skill_md="${dir}/SKILL.md"

  if [[ ! -f "$skill_md" ]]; then
    error "${rel}/ has no SKILL.md"
    return
  fi

  if ! has_closed_frontmatter "$skill_md"; then
    error "${rel}/SKILL.md must start with YAML frontmatter delimited by --- lines"
    return
  fi

  fm="$(frontmatter "$skill_md")"

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if ! contains "$key" "${SPEC_KEYS[@]}"; then
      error "${rel}/SKILL.md: frontmatter key '${key}' is not in the Agent Skills spec; move it under metadata"
    fi
  done < <(grep -oE '^[A-Za-z0-9_-]+:' <<<"$fm" | tr -d ':')

  name="$(unquote "$(frontmatter_value "$fm" name)")"
  if [[ -z "$name" ]]; then
    error "${rel}/SKILL.md: missing name"
  else
    if [[ "$name" != "$dir_name" ]]; then
      error "${rel}/SKILL.md: name '${name}' must match the folder name '${dir_name}'"
    fi
    if (( ${#name} > MAX_NAME_LENGTH )) || [[ ! "$name" =~ $NAME_PATTERN ]]; then
      error "${rel}/SKILL.md: name '${name}' must be 1-${MAX_NAME_LENGTH} characters of lowercase letters, digits, and single hyphens"
    fi
  fi

  description="$(unquote "$(frontmatter_value "$fm" description)")"
  if [[ -z "$description" ]]; then
    error "${rel}/SKILL.md: missing description"
  elif (( ${#description} > MAX_DESCRIPTION_LENGTH )); then
    error "${rel}/SKILL.md: description is ${#description} characters (max ${MAX_DESCRIPTION_LENGTH})"
  elif [[ "$description" == TODO* ]]; then
    error "${rel}/SKILL.md: description is still the template placeholder"
  fi

  allowed_tools="$(frontmatter_value "$fm" allowed-tools)"
  if [[ "$allowed_tools" == "- "* || "$allowed_tools" == "["* ]]; then
    error "${rel}/SKILL.md: allowed-tools must be a space-separated string, not a list"
  fi

  license="$(unquote "$(frontmatter_value "$fm" license)")"
  if [[ -n "$license" && "$license" != "MIT" ]] && ! compgen -G "${dir}/LICENSE*" >/dev/null; then
    error "${rel}/: license is '${license}' but the folder has no LICENSE.txt"
  fi

  line_count="$(wc -l <"$skill_md" | tr -d ' ')"
  if (( line_count >= MAX_SKILL_LINES )); then
    error "${rel}/SKILL.md: ${line_count} lines (keep it under ${MAX_SKILL_LINES}; move detail into references/)"
  fi

  version="$(unquote "$(metadata_value "$fm" version)")"
  if [[ -z "$version" ]]; then
    error "${rel}/SKILL.md: missing metadata.version"
  elif [[ ! "$version" =~ $SEMVER_PATTERN ]]; then
    error "${rel}/SKILL.md: metadata.version '${version}' must be MAJOR.MINOR.PATCH"
  fi

  changelog="${dir}/CHANGELOG.md"
  if [[ ! -f "$changelog" ]]; then
    error "${rel}/: missing CHANGELOG.md"
  else
    grep -qE '^## \[Unreleased\]' "$changelog" || error "${rel}/CHANGELOG.md: missing '## [Unreleased]' section"
    latest="$(latest_changelog_version "$changelog")"
    if [[ -z "$latest" ]]; then
      error "${rel}/CHANGELOG.md: no released '## [X.Y.Z]' entry"
    elif [[ -n "$version" && "$latest" != "$version" ]]; then
      error "${rel}: metadata.version is ${version} but the latest CHANGELOG.md entry is ${latest}"
    fi
  fi

  if [[ ! -f "${ROOT}/README.md" ]] || ! grep -qF "skills/${dir_name}/" "${ROOT}/README.md"; then
    error "${rel}: missing from the Skills table in README.md (link to skills/${dir_name}/SKILL.md)"
  fi
}

check_plugin_names() {
  local file="$1"
  local dupes

  dupes="$(jq -r '.plugins[]?.name // empty' "$file" | sort | uniq -d)"
  if [[ -n "$dupes" ]]; then
    error "${file#"${ROOT}/"}: duplicate plugin names: ${dupes//$'\n'/, }"
  fi
}

check_claude_marketplace() {
  local file="${ROOT}/.claude-plugin/marketplace.json"
  local rel=".claude-plugin/marketplace.json"
  local name plugin source skill base target

  if [[ ! -f "$file" ]]; then
    error "missing ${rel}"
    return
  fi
  if ! jq empty "$file" 2>/dev/null; then
    error "${rel} is not valid JSON"
    return
  fi

  name="$(jq -r '.name // empty' "$file")"
  [[ -n "$name" ]] || error "${rel}: missing name"
  if contains "$name" "${CLAUDE_RESERVED_MARKETPLACES[@]}" || [[ "$name" == claudeai-* ]]; then
    error "${rel}: marketplace name '${name}' is reserved"
  fi
  [[ -n "$(jq -r '.owner.name // empty' "$file")" ]] || error "${rel}: missing owner.name"
  if [[ "$(jq -r '.plugins | type' "$file")" != "array" ]]; then
    error "${rel}: plugins must be an array"
    return
  fi

  check_plugin_names "$file"

  while IFS=$'\t' read -r plugin source; do
    if [[ -z "$plugin" ]]; then
      error "${rel}: plugin entry missing name"
      continue
    fi
    if [[ ! "$plugin" =~ $NAME_PATTERN ]]; then
      error "${rel}: plugin name '${plugin}' must be kebab-case"
    fi
    if [[ "$plugin" == claude-* || "$plugin" == anthropic-* || "$plugin" == cc-plugin-* ]]; then
      error "${rel}: plugin name '${plugin}' uses a reserved prefix"
    fi

    # Object sources (github, url, npm, ...) point outside this repo.
    [[ "$source" == "<object>" ]] && continue
    if [[ "$source" != ./* && "$source" != "." ]]; then
      error "${rel}: plugin '${plugin}' source '${source}' must be a relative path starting with ./"
      continue
    fi
    base="$(resolve_path "$ROOT" "$source")"
    if [[ ! -d "$base" ]]; then
      error "${rel}: plugin '${plugin}' source '${source}' does not exist"
      continue
    fi

    while IFS= read -r skill; do
      [[ -n "$skill" ]] || continue
      if [[ "$skill" != ./* ]]; then
        error "${rel}: plugin '${plugin}' skill path '${skill}' must start with ./"
        continue
      fi
      target="$(resolve_path "$base" "$skill")"
      if [[ ! -f "${target}/SKILL.md" ]]; then
        error "${rel}: plugin '${plugin}' lists '${skill}' but ${target#"${ROOT}/"}/SKILL.md does not exist"
      fi
    done < <(jq -r --arg p "$plugin" '.plugins[] | select(.name == $p) | .skills // empty | if type == "string" then . else .[] end' "$file")
  done < <(jq -r '.plugins[] | [(.name // ""), (.source | if type == "string" then . elif . == null then "" else "<object>" end)] | @tsv' "$file")
}

check_cursor_manifests() {
  local marketplace="${ROOT}/.cursor-plugin/marketplace.json"
  local plugin_json="${ROOT}/.cursor-plugin/plugin.json"
  local mrel=".cursor-plugin/marketplace.json"
  local prel=".cursor-plugin/plugin.json"
  local key plugin source plugin_name

  if [[ ! -f "$marketplace" ]]; then
    error "missing ${mrel}"
  elif ! jq empty "$marketplace" 2>/dev/null; then
    error "${mrel} is not valid JSON"
  else
    [[ -n "$(jq -r '.name // empty' "$marketplace")" ]] || error "${mrel}: missing name"
    while IFS= read -r key; do
      error "${mrel}: top-level key '${key}' is not allowed by the Cursor schema"
    done < <(jq -r --argjson allowed "$CURSOR_MARKETPLACE_KEYS" 'keys[] | select(. as $k | $allowed | index($k) | not)' "$marketplace")

    if [[ "$(jq -r '.plugins | type' "$marketplace")" != "array" ]]; then
      error "${mrel}: plugins must be an array"
    else
      check_plugin_names "$marketplace"
      while IFS= read -r key; do
        error "${mrel}: plugin entry key '${key}' is not allowed by the Cursor schema (only name, source, description, minClientVersions)"
      done < <(jq -r --argjson allowed "$CURSOR_ENTRY_KEYS" '.plugins[] | keys[] | select(. as $k | $allowed | index($k) | not)' "$marketplace" | sort -u)

      while IFS=$'\t' read -r plugin source; do
        if [[ ! "$plugin" =~ $NAME_PATTERN ]]; then
          error "${mrel}: plugin name '${plugin}' must be kebab-case"
        fi
        if [[ -z "$source" ]]; then
          error "${mrel}: plugin '${plugin}' missing source"
        elif [[ "$source" != *://* && ! -d "$(resolve_path "$ROOT" "$source")" ]]; then
          error "${mrel}: plugin '${plugin}' source '${source}' does not exist"
        fi
      done < <(jq -r '.plugins[] | [(.name // ""), (.source // "")] | @tsv' "$marketplace")
    fi
  fi

  if [[ ! -f "$plugin_json" ]]; then
    error "missing ${prel}"
  elif ! jq empty "$plugin_json" 2>/dev/null; then
    error "${prel} is not valid JSON"
  else
    plugin_name="$(jq -r '.name // empty' "$plugin_json")"
    if [[ ! "$plugin_name" =~ $NAME_PATTERN ]]; then
      error "${prel}: name '${plugin_name}' must be kebab-case"
    fi
    while IFS= read -r key; do
      error "${prel}: key '${key}' is not allowed by the Cursor schema"
    done < <(jq -r --argjson allowed "$CURSOR_PLUGIN_KEYS" 'keys[] | select(. as $k | $allowed | index($k) | not)' "$plugin_json")
    if [[ -f "$marketplace" ]] && jq empty "$marketplace" 2>/dev/null &&
      [[ -z "$(jq -r --arg n "$plugin_name" '.plugins[]? | select(.name == $n) | .name' "$marketplace")" ]]; then
      error "${prel}: name '${plugin_name}' has no matching entry in ${mrel}"
    fi
  fi
}

check_repo_layout
check_claude_marketplace
check_cursor_manifests

shopt -s nullglob
skill_dirs=("${ROOT}"/skills/*/)
shopt -u nullglob

for dir in "${skill_dirs[@]}"; do
  check_skill "${dir%/}"
done

shopt -s nullglob
check_scripts=("${ROOT}"/scripts/checks/*.sh)
shopt -u nullglob

for check in "${check_scripts[@]}"; do
  bash "$check" "$ROOT" || error "${check#"${ROOT}/"} failed"
done

if (( errors > 0 )); then
  echo "validation failed: ${errors} error(s)" >&2
  exit 1
fi

if (( ${#skill_dirs[@]} == 0 )); then
  echo "ok: no skills yet; repo layout and marketplace manifests are valid"
else
  echo "ok: ${#skill_dirs[@]} skill(s) validated, ${#check_scripts[@]} skill check(s) passed"
fi
