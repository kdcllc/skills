#!/usr/bin/env bash
# Structural verification of the docs/guide/ developer-guide suite and the root
# README.md ## Documentation section: file inventory, relative link resolution,
# cross-file anchor ban, absolute-path ban, Mermaid fence balance and conventions,
# and README section integrity.
#
# Usage (from repository root):
#   bash tests/docs-link-check.sh
#
# Fixture override (negative-evidence runs against a synthetic tree):
#   DOCS_LINK_CHECK_ROOT=/path/to/fixture bash tests/docs-link-check.sh
#   bash tests/docs-link-check.sh /path/to/fixture
#
# Exit 0 when all checks pass; exit 1 when any violation is found.
# Prints one FAIL line per violation, then a SUMMARY line. No network access.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${DOCS_LINK_CHECK_ROOT:-${1:-$(cd "$HERE/.." && pwd)}}"
GUIDE_DIR="$REPO_ROOT/docs/guide"
README="$REPO_ROOT/README.md"

# Frozen inventory of suite documents under docs/guide/
readonly -a EXPECTED_SUITE=(
  README.md
  getting-started.md
  decision-guide.md
  feature-workflow.md
  research-workflow.md
  autonomous-loop.md
  agents-and-models.md
  evaluation-system.md
  contributing.md
)

failures=()

add_failure() {
  failures+=("FAIL $1 $2: $3")
}

is_expected_suite_basename() {
  local name="$1"
  local expected
  for expected in "${EXPECTED_SUITE[@]}"; do
    if [[ "$name" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

# Print markdown inline-link targets (handles [text](url) and ![alt](url)).
# Link text may contain parentheses; the URL follows the first ]( sequence.
extract_markdown_link_targets() {
  awk '
  {
    line = $0
    pos = 1
    while (pos <= length(line)) {
      close_bracket = index(substr(line, pos), "](")
      if (close_bracket == 0) {
        break
      }
      close_bracket = close_bracket + pos - 1
      url_start = close_bracket + 2
      url_end = url_start
      while (url_end <= length(line) && substr(line, url_end, 1) != ")") {
        url_end++
      }
      if (url_end > length(line)) {
        break
      }
      print substr(line, url_start, url_end - url_start)
      pos = url_end + 1
    }
  }
  ' "$1"
}

path_component() {
  local target="$1"
  target="${target%%#*}"
  printf '%s\n' "$target"
}

resolve_relative_target() {
  local link_dir="$1"
  local target="$2"
  local path dir name resolved_dir

  path="$(path_component "$target")"
  [[ -z "$path" ]] && return 1

  dir="$(dirname "$path")"
  name="$(basename "$path")"

  if [[ "$dir" == "." ]]; then
    printf '%s\n' "$link_dir/$name"
    return 0
  fi

  if ! resolved_dir="$(cd "$link_dir/$dir" 2>/dev/null && pwd)"; then
    return 1
  fi
  printf '%s\n' "$resolved_dir/$name"
}

target_exists() {
  local link_dir="$1"
  local target="$2"
  local resolved

  if ! resolved="$(resolve_relative_target "$link_dir" "$target")"; then
    return 1
  fi
  [[ -e "$resolved" ]]
}

check_inventory() {
  local base missing
  for base in "${EXPECTED_SUITE[@]}"; do
    if [[ ! -f "$GUIDE_DIR/$base" ]]; then
      add_failure "check-1" "$GUIDE_DIR/$base" "missing expected file"
    fi
  done
}

check_suite_links() {
  local guide_file link_dir linking_base target path resolved fragment suite_base

  for guide_file in "${EXPECTED_SUITE[@]}"; do
    guide_file="$GUIDE_DIR/$guide_file"
    [[ -f "$guide_file" ]] || continue

    link_dir="$(dirname "$guide_file")"
    linking_base="$(basename "$guide_file")"

    while IFS= read -r target || [[ -n "$target" ]]; do
      [[ -z "$target" ]] && continue

      path="$(path_component "$target")"

      # Check 4 — absolute filesystem paths
      if [[ -n "$path" && "$path" == /* ]]; then
        add_failure "check-4" "$guide_file" "absolute path link target: $target"
        continue
      fi

      # Check 2 — skip external schemes
      if [[ "$target" == http://* || "$target" == https://* || "$target" == mailto:* ]]; then
        continue
      fi

      # Check 2 — fragment-only links exempt
      if [[ "$target" == \#* ]]; then
        continue
      fi

      # Check 2 — resolve relative path component
      if ! target_exists "$link_dir" "$target"; then
        add_failure "check-2" "$guide_file" "broken relative link: $target"
      fi

      # Check 3 — cross-file anchors within the suite
      fragment="${target#*#}"
      if [[ "$target" == *"#"* && "$fragment" != "$target" ]]; then
        if resolved="$(resolve_relative_target "$link_dir" "$target")"; then
          if [[ "$resolved" != "$guide_file" ]]; then
            suite_base="$(basename "$resolved")"
            if [[ "$resolved" == "$GUIDE_DIR/$suite_base" ]] && is_expected_suite_basename "$suite_base"; then
              add_failure "check-3" "$guide_file" "cross-file anchor forbidden: $target"
            fi
          fi
        fi
      fi
    done < <(extract_markdown_link_targets "$guide_file")
  done
}

check_mermaid_fences() {
  local guide_file fence_count mermaid_count in_mermaid mermaid_file line_num first_line

  for guide_file in "${EXPECTED_SUITE[@]}"; do
    guide_file="$GUIDE_DIR/$guide_file"
    [[ -f "$guide_file" ]] || continue

    fence_count="$(grep -c '^[[:space:]]*```' "$guide_file" || true)"
    if (( fence_count % 2 != 0 )); then
      add_failure "check-5" "$guide_file" "unbalanced fenced-code fences (count=$fence_count)"
    fi

    mermaid_count="$(grep -c '^[[:space:]]*```mermaid[[:space:]]*$' "$guide_file" || true)"
    if (( mermaid_count == 0 )); then
      add_failure "check-5" "$guide_file" "no mermaid block"
    fi

    in_mermaid=0
    line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_num=$((line_num + 1))
      if grep -qE '^[[:space:]]*```mermaid[[:space:]]*$' <<< "$line"; then
        in_mermaid=1
        first_line=""
        continue
      fi
      if (( in_mermaid == 1 )) && grep -qE '^[[:space:]]*```[[:space:]]*$' <<< "$line"; then
        in_mermaid=0
        continue
      fi
      if (( in_mermaid == 1 )); then
        if [[ "$line" == *'%%{init'* ]]; then
          add_failure "check-5" "$guide_file" "mermaid block contains %%{init at line $line_num"
        fi
        if [[ -z "$first_line" ]] && grep -qE '[^[:space:]]' <<< "$line"; then
          first_line="${line#"${line%%[![:space:]]*}"}"
          if [[ "$first_line" != flowchart* && "$first_line" != sequenceDiagram* && "$first_line" != stateDiagram-v2* ]]; then
            add_failure "check-5b" "$guide_file" "disallowed mermaid diagram type: ${first_line%% *}"
          fi
        fi
      fi
    done < "$guide_file"
  done
}

check_readme_documentation_section() {
  local heading_count section_file target path link_dir

  if [[ ! -f "$README" ]]; then
    add_failure "check-6" "$README" "README.md missing"
    return
  fi

  heading_count="$(grep -c '^## Documentation$' "$README" || true)"
  if (( heading_count == 0 )); then
    add_failure "check-6" "$README" "missing ## Documentation heading"
    return
  fi
  if (( heading_count > 1 )); then
    add_failure "check-6" "$README" "multiple ## Documentation headings (count=$heading_count)"
    return
  fi

  section_file="$(mktemp)"
  awk '
    /^## Documentation$/ { in_doc = 1; next }
    /^## / && in_doc { exit }
    in_doc { print }
  ' "$README" > "$section_file"

  link_dir="$(dirname "$README")"
  while IFS= read -r target || [[ -n "$target" ]]; do
    [[ -z "$target" ]] && continue
    if [[ "$target" == http://* || "$target" == https://* || "$target" == mailto:* ]]; then
      continue
    fi
    path="$(path_component "$target")"
    [[ -z "$path" || "$path" == \#* ]] && continue
    if [[ "$path" != docs/guide/* && "$path" != */docs/guide/* ]]; then
      continue
    fi
    if ! target_exists "$link_dir" "$target"; then
      add_failure "check-6" "$README" "broken Documentation section link: $target"
    fi
  done < <(extract_markdown_link_targets "$section_file")

  rm -f "$section_file"
}

check_inventory
check_suite_links
check_mermaid_fences
check_readme_documentation_section

if ((${#failures[@]} > 0)); then
  mapfile -t sorted_failures < <(printf '%s\n' "${failures[@]}" | sort -k3,3 -k2,2)
  printf '%s\n' "${sorted_failures[@]}"
  echo "SUMMARY: 0 passed, ${#failures[@]} failed"
  exit 1
fi

echo "SUMMARY: all checks passed"
exit 0
