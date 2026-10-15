#!/usr/bin/env bash
# Structural verification of tracked research briefs (_memory/research/), the index,
# legacy doc absence, and resolvable relative links in briefs, the index, and the
# docs/agent-kit hub README.
#
# Usage (from repository root):
#   bash tests/agent-kit/research-docs-check.sh
#
# Fixture override (checks only — mutation suite is skipped):
#   RESEARCH_DOCS_CHECK_ROOT=/path/to/fixture bash tests/agent-kit/research-docs-check.sh
#   bash tests/agent-kit/research-docs-check.sh /path/to/fixture
#
# Empty root is rejected (exit 2): RESEARCH_DOCS_CHECK_ROOT="" or a "" argument.
#
# Exit 0 when all checks pass; exit 1 when any violation is found; exit 2 on usage/root errors.
# Prints one FAIL line per violation, then a SUMMARY line. No network access.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_REPO_ROOT="$(cd "$HERE/../.." && pwd)"

if [[ -n "${RESEARCH_DOCS_CHECK_ROOT+x}" && -z "${RESEARCH_DOCS_CHECK_ROOT}" ]]; then
  echo "research-docs-check: RESEARCH_DOCS_CHECK_ROOT is set but empty" >&2
  exit 2
fi
if [[ $# -ge 1 && -z "${1}" ]]; then
  echo "research-docs-check: empty root argument" >&2
  exit 2
fi

ROOT_ARG_USED=0
ROOT_OVERRIDE=0
if [[ -n "${RESEARCH_DOCS_CHECK_ROOT+x}" ]]; then
  ROOT_OVERRIDE=1
  CHECK_ROOT="$RESEARCH_DOCS_CHECK_ROOT"
elif [[ $# -ge 1 ]]; then
  ROOT_ARG_USED=1
  CHECK_ROOT="$1"
else
  CHECK_ROOT="$REAL_REPO_ROOT"
fi

RUN_MUTATIONS=1
if [[ -n "${RESEARCH_DOCS_SKIP_MUTATIONS:-}" ]]; then
  RUN_MUTATIONS=0
elif [[ "$ROOT_OVERRIDE" -eq 1 || "$ROOT_ARG_USED" -eq 1 ]]; then
  RUN_MUTATIONS=0
fi
RESEARCH_DIR="$CHECK_ROOT/_memory/research"
HUB_README="$CHECK_ROOT/docs/agent-kit/README.md"
DOCS_KIT="$CHECK_ROOT/docs/agent-kit"

readonly VALID_STATUSES='proposed|ingested|adopted|shipped|superseded|rejected'
readonly MEMORY_ID_RE='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
readonly DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

failures=()
mutation_pass=0

add_failure() {
  failures+=("FAIL $1 $2: $3")
}

extract_frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0 }
    /^---$/ {
      if (!in_fm) { in_fm = 1; next }
      exit 0
    }
    in_fm && index($0, key ": ") == 1 {
      sub("^" key ": ", "")
      print
      exit 0
    }
  ' "$file"
}

frontmatter_has_key() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0; found = 0 }
    /^---$/ {
      if (!in_fm) { in_fm = 1; next }
      exit (found ? 0 : 1)
    }
    in_fm && index($0, key ": ") == 1 { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

brief_has_frontmatter_block() {
  awk 'NR == 1 && $0 == "---" { exit 0 } NR > 1 { exit 1 }' "$1"
}

is_inline_list_value() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#*: }"
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ "$line" == \[*] ]]
}

memory_record_exists() {
  local root="$1" id="$2"
  if [[ -f "$root/_memory/quarantine/${id}.md" ]]; then
    return 0
  fi
  local y m
  y="${id:0:4}"
  m="${id:4:2}"
  [[ -f "$root/_memory/records/$y/$m/${id}.md" ]]
}

extract_ids_from_inline_list() {
  local list="$1"
  list="${list#\[}"
  list="${list%]}"
  list="${list// /}"
  if [[ -z "$list" ]]; then
    return 0
  fi
  local IFS=','
  local part
  for part in $list; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [[ -n "$part" ]] && printf '%s\n' "$part"
  done
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

link_targets_work_memory() {
  local target="$1"
  local path
  path="$(path_component "$target")"
  [[ "$path" == *"_memory/work/"* ]] && return 0
  [[ "$target" == *"_memory/work/"* ]] && return 0
  return 1
}

extract_markdown_link_targets_skip_fences() {
  awk '
    /^[[:space:]]*```/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      line = $0
      pos = 1
      while (pos <= length(line)) {
        close_bracket = index(substr(line, pos), "](")
        if (close_bracket == 0) break
        close_bracket = close_bracket + pos - 1
        url_start = close_bracket + 2
        url_end = url_start
        while (url_end <= length(line) && substr(line, url_end, 1) != ")") url_end++
        if (url_end > length(line)) break
        print substr(line, url_start, url_end - url_start)
        pos = url_end + 1
      }
    }
  ' "$1"
}

check_brief_frontmatter() {
  local brief="$1"
  local rel="$2"
  local stem key val topic date status recheck shipped goals sup supersedes mem line id

  stem="${brief##*/}"
  stem="${stem%.md}"

  if ! brief_has_frontmatter_block "$brief"; then
    add_failure "check-a" "$rel" "missing opening --- frontmatter block"
    return
  fi

  for key in title topic date status goals supersedes memory; do
    if ! frontmatter_has_key "$brief" "$key"; then
      add_failure "check-a" "$rel" "frontmatter missing required key: $key"
    fi
  done

  topic="$(extract_frontmatter_value "$brief" topic)"
  if [[ -z "$topic" ]]; then
    add_failure "check-b" "$rel" "empty topic"
  elif [[ "$topic" != "$stem" ]]; then
    add_failure "check-b" "$rel" "topic '$topic' != file stem '$stem'"
  fi

  date="$(extract_frontmatter_value "$brief" date)"
  if [[ -z "$date" ]]; then
    add_failure "check-b" "$rel" "empty date"
  elif ! [[ "$date" =~ $DATE_RE ]]; then
    add_failure "check-b" "$rel" "date not YYYY-MM-DD: $date"
  fi

  if frontmatter_has_key "$brief" recheck_by; then
    recheck="$(extract_frontmatter_value "$brief" recheck_by)"
    if [[ -n "$recheck" && ! "$recheck" =~ $DATE_RE ]]; then
      add_failure "check-b" "$rel" "recheck_by not YYYY-MM-DD: $recheck"
    fi
  fi

  status="$(extract_frontmatter_value "$brief" status)"
  if [[ -z "$status" ]]; then
    add_failure "check-c" "$rel" "empty status"
  elif ! [[ "$status" =~ ^($VALID_STATUSES)$ ]]; then
    add_failure "check-c" "$rel" "invalid status: $status"
  fi

  for key in goals supersedes memory; do
    if frontmatter_has_key "$brief" "$key"; then
      line="$(awk -v key="$key" '
        BEGIN { in_fm = 0 }
        /^---$/ { if (!in_fm) { in_fm = 1; next } exit 0 }
        in_fm && index($0, key ": ") == 1 { print; exit 0 }
      ' "$brief")"
      if ! is_inline_list_value "$line"; then
        add_failure "check-d" "$rel" "$key must be an inline [...] list"
      fi
    fi
  done

  if frontmatter_has_key "$brief" shipped_in; then
    line="$(awk '
      BEGIN { in_fm = 0 }
      /^---$/ { if (!in_fm) { in_fm = 1; next } exit 0 }
      in_fm && index($0, "shipped_in: ") == 1 { print; exit 0 }
    ' "$brief")"
    if ! is_inline_list_value "$line"; then
      add_failure "check-d" "$rel" "shipped_in must be an inline [...] list"
    fi
  fi

  mem="$(extract_frontmatter_value "$brief" memory)"
  if [[ -n "$mem" ]]; then
    while IFS= read -r id || [[ -n "$id" ]]; do
      [[ -z "$id" ]] && continue
      if ! [[ "$id" =~ $MEMORY_ID_RE ]]; then
        add_failure "check-d" "$rel" "memory id format invalid: $id"
        continue
      fi
      if ! memory_record_exists "$CHECK_ROOT" "$id"; then
        add_failure "check-d" "$rel" "memory id not in records/ or quarantine/: $id"
      fi
    done < <(extract_ids_from_inline_list "$mem")
  fi
}

check_all_briefs() {
  local brief rel
  shopt -s nullglob
  for brief in "$RESEARCH_DIR"/*.md; do
    [[ "$(basename "$brief")" == "README.md" ]] && continue
    rel="${brief#"$CHECK_ROOT"/}"
    check_brief_frontmatter "$brief" "$rel"
  done
  shopt -u nullglob
}

check_research_index() {
  local index="$RESEARCH_DIR/README.md"
  local brief stem index_rel target

  if [[ ! -f "$index" ]]; then
    add_failure "check-e" "_memory/research/README.md" "missing index"
    return
  fi
  index_rel="_memory/research/README.md"

  shopt -s nullglob
  for brief in "$RESEARCH_DIR"/*.md; do
    [[ "$(basename "$brief")" == "README.md" ]] && continue
    stem="${brief##*/}"
    stem="${stem%.md}"
    if ! grep -qF "(${stem}.md)" "$index"; then
      add_failure "check-e" "$index_rel" "index missing link to ${stem}.md"
    fi
  done
  shopt -u nullglob

  local link_dir
  link_dir="$(dirname "$index")"
  while IFS= read -r target || [[ -n "$target" ]]; do
    [[ -z "$target" ]] && continue
    if [[ "$target" == http://* || "$target" == https://* || "$target" == mailto:* ]]; then
      continue
    fi
    if [[ "$(path_component "$target")" == \#* || "$(path_component "$target")" == "" ]]; then
      continue
    fi
    if ! target_exists "$link_dir" "$target"; then
      add_failure "check-e" "$index_rel" "broken index link: $target"
    fi
  done < <(extract_markdown_link_targets_skip_fences "$index")
}

check_legacy_research_docs() {
  local f base
  shopt -s nullglob
  for f in "$DOCS_KIT"/research-*.md "$DOCS_KIT"/design-*.md; do
    base="${f#"$CHECK_ROOT"/}"
    add_failure "check-f" "$base" "legacy research/design doc must not exist"
  done
  shopt -u nullglob
}

check_markdown_links_in_file() {
  local file="$1" rel="$2" link_dir target path
  [[ -f "$file" ]] || return 0
  link_dir="$(dirname "$file")"
  while IFS= read -r target || [[ -n "$target" ]]; do
    [[ -z "$target" ]] && continue
    if [[ "$target" == http://* || "$target" == https://* || "$target" == mailto:* ]]; then
      continue
    fi
    path="$(path_component "$target")"
    if [[ -z "$path" || "$path" == \#* ]]; then
      continue
    fi
    if link_targets_work_memory "$target"; then
      add_failure "check-g" "$rel" "link targets gitignored _memory/work/: $target"
      continue
    fi
    if ! target_exists "$link_dir" "$target"; then
      add_failure "check-g" "$rel" "broken relative link: $target"
    fi
  done < <(extract_markdown_link_targets_skip_fences "$file")
}

check_relative_links() {
  local brief rel
  shopt -s nullglob
  for brief in "$RESEARCH_DIR"/*.md; do
    rel="${brief#"$CHECK_ROOT"/}"
    check_markdown_links_in_file "$brief" "$rel"
  done
  shopt -u nullglob
  if [[ -f "$HUB_README" ]]; then
    check_markdown_links_in_file "$HUB_README" "docs/agent-kit/README.md"
  else
    add_failure "check-g" "docs/agent-kit/README.md" "hub README missing"
  fi
}

run_all_checks() {
  failures=()
  if [[ ! -d "$RESEARCH_DIR" ]]; then
    add_failure "check-a" "_memory/research" "directory missing"
    return 1
  fi
  check_all_briefs
  check_research_index
  check_legacy_research_docs
  check_relative_links
  ((${#failures[@]} > 0))
}

emit_summary_and_exit() {
  if ((${#failures[@]} > 0)); then
    local line sorted
    sorted="$(printf '%s\n' "${failures[@]}" | LC_ALL=C sort -k3,3 -k2,2)"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] && printf '%s\n' "$line"
    done <<< "$sorted"
    echo "SUMMARY: 0 passed, ${#failures[@]} failed"
    exit 1
  fi
  echo "SUMMARY: all checks passed"
  exit 0
}

copy_fixture_tree() {
  local dest="$1"
  assert_fixture_root "$dest" || return 1
  mkdir -p "$dest/_memory" "$dest/docs/agent-kit"
  cp -a "$REAL_REPO_ROOT/_memory/research" "$dest/_memory/"
  cp -a "$REAL_REPO_ROOT/_memory/records" "$dest/_memory/"
  if [[ -d "$REAL_REPO_ROOT/_memory/quarantine" ]]; then
    cp -a "$REAL_REPO_ROOT/_memory/quarantine" "$dest/_memory/"
  fi
  cp -a "$REAL_REPO_ROOT/docs/agent-kit/README.md" "$dest/docs/agent-kit/"
  if [[ -d "$REAL_REPO_ROOT/docs/agent-kit/guide" ]]; then
    cp -a "$REAL_REPO_ROOT/docs/agent-kit/guide" "$dest/docs/agent-kit/"
  fi
  mkdir -p "$dest/skills"
  if [[ -d "$REAL_REPO_ROOT/skills/agent-kit" ]]; then
    cp -a "$REAL_REPO_ROOT/skills/agent-kit" "$dest/skills/"
  fi
  return 0
}

run_check_on_root_capture() {
  local root="$1"
  # Subprocess exits 1 on check failures; capture output without tripping set -e.
  RESEARCH_DOCS_SKIP_MUTATIONS=1 RESEARCH_DOCS_CHECK_ROOT="$root" \
    bash "$HERE/research-docs-check.sh" 2>&1 || true
}

run_check_on_root_expect_pass() {
  local root="$1"
  RESEARCH_DOCS_SKIP_MUTATIONS=1 RESEARCH_DOCS_CHECK_ROOT="$root" bash "$HERE/research-docs-check.sh" >/dev/null 2>&1
}

mutation_report() {
  local family="$1" detail="$2"
  mutation_pass=$((mutation_pass + 1))
  echo "MUTATION PASS check-${family}: ${detail}"
}

mutation_expect_fail_grep() {
  local family="$1" grep_pat="$2" root="$3" detail="$4"
  local out
  out="$(run_check_on_root_capture "$root")"
  if printf '%s\n' "$out" | grep -qE "$grep_pat"; then
    mutation_report "$family" "$detail"
    return 0
  fi
  echo "MUTATION FAIL check-${family}: expected output matching /${grep_pat}/" >&2
  printf '%s\n' "$out" | tail -8 >&2
  exit 1
}

run_empty_root_selftests() {
  local rc
  set +e
  RESEARCH_DOCS_SKIP_MUTATIONS=1 bash "$HERE/research-docs-check.sh" "" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "SELFTEST FAIL: empty argument must exit 2 (got $rc)" >&2
    exit 1
  fi
  echo "SELFTEST PASS: empty root argument exits 2"

  set +e
  RESEARCH_DOCS_SKIP_MUTATIONS=1 RESEARCH_DOCS_CHECK_ROOT="" bash "$HERE/research-docs-check.sh" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "SELFTEST FAIL: empty RESEARCH_DOCS_CHECK_ROOT must exit 2 (got $rc)" >&2
    exit 1
  fi
  echo "SELFTEST PASS: empty RESEARCH_DOCS_CHECK_ROOT exits 2"
}

run_mutation_suite() {
  local fixture sub
  FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/research-docs-check.XXXXXX")"
  trap 'rm -rf "${FIXTURE_TMPDIR:-}"' EXIT

  # shellcheck source=lib/fixture-root.sh
  REPO_ROOT="$REAL_REPO_ROOT" FIXTURE_TMPDIR="$FIXTURE_TMPDIR" source "$HERE/lib/fixture-root.sh"

  fixture="$FIXTURE_TMPDIR/base"
  mkdir -p "$fixture"
  copy_fixture_tree "$fixture" || {
    echo "MUTATION FAIL setup: copy_fixture_tree failed" >&2
    exit 1
  }
  if ! run_check_on_root_expect_pass "$fixture"; then
    echo "MUTATION FAIL setup: base fixture should pass" >&2
    exit 1
  fi

  clone_fixture() {
    local dest="$1"
    cp -a "$fixture" "$dest"
    assert_fixture_root "$dest" || {
      echo "MUTATION FAIL setup: assert_fixture_root refused $dest" >&2
      exit 1
    }
  }

  # (a) missing required frontmatter key
  sub="$FIXTURE_TMPDIR/mut-a"
  clone_fixture "$sub"
  sed -i '/^memory:/d' "$sub/_memory/research/agent-memory-store.md"
  mutation_expect_fail_grep "a" '^FAIL check-a ' "$sub" "missing memory key fails"

  # (b) topic != stem
  sub="$FIXTURE_TMPDIR/mut-b"
  clone_fixture "$sub"
  sed -i 's/^topic: agent-memory-store/topic: wrong-stem/' "$sub/_memory/research/agent-memory-store.md"
  mutation_expect_fail_grep "b" '^FAIL check-b ' "$sub" "topic stem mismatch fails"

  # (c) invalid status
  sub="$FIXTURE_TMPDIR/mut-c"
  clone_fixture "$sub"
  sed -i 's/^status: shipped/status: pending/' "$sub/_memory/research/squad-ideas.md"
  mutation_expect_fail_grep "c" '^FAIL check-c ' "$sub" "invalid status fails"

  # (d) memory id missing on disk
  sub="$FIXTURE_TMPDIR/mut-d"
  clone_fixture "$sub"
  sed -i 's/memory: \[20261008T120006Z-b10ad6b8\]/memory: [20990101T000000Z-deadbeef]/' \
    "$sub/_memory/research/agent-memory-store.md"
  mutation_expect_fail_grep "d" '^FAIL check-d ' "$sub" "missing memory record fails"

  # (e) index missing brief link
  sub="$FIXTURE_TMPDIR/mut-e"
  clone_fixture "$sub"
  sed -i '/\[squad-ideas\.md\]/d' "$sub/_memory/research/README.md"
  mutation_expect_fail_grep "e" '^FAIL check-e ' "$sub" "index missing brief row fails"

  # (f) legacy research-*.md file
  sub="$FIXTURE_TMPDIR/mut-f"
  clone_fixture "$sub"
  printf '# legacy\n' > "$sub/docs/agent-kit/research-evil.md"
  mutation_expect_fail_grep "f" '^FAIL check-f ' "$sub" "legacy research-*.md fails"

  # (g) broken relative link
  sub="$FIXTURE_TMPDIR/mut-g"
  clone_fixture "$sub"
  printf '\nSee [broken](no-such-file.md).\n' >> "$sub/_memory/research/squad-ideas.md"
  mutation_expect_fail_grep "g" '^FAIL check-g .*broken relative link' "$sub" "broken relative link fails"

  # (g2) _memory/work/ link ban (target file exists so only the ban can fail)
  sub="$FIXTURE_TMPDIR/mut-g2"
  clone_fixture "$sub"
  mkdir -p "$sub/_memory/work/research/x"
  : > "$sub/_memory/work/research/x/prompt.md"
  printf '\nBad [scratch](../../_memory/work/research/x/prompt.md).\n' >> "$sub/_memory/research/squad-ideas.md"
  mutation_expect_fail_grep "g" '^FAIL check-g .*_memory/work/' "$sub" "_memory/work/ link target fails"

  # base fixture must be untouched by every mutation (clones are independent copies)
  if ! run_check_on_root_expect_pass "$fixture"; then
    echo "MUTATION FAIL teardown: base fixture no longer passes (a mutation wrote through to it)" >&2
    exit 1
  fi
  mutation_pass=$((mutation_pass + 1))
  echo "MUTATION PASS base-fixture: still passes after all mutations"

  rm -rf "$FIXTURE_TMPDIR"
  FIXTURE_TMPDIR=""
  trap - EXIT
}

if [[ -n "${RESEARCH_DOCS_SKIP_MUTATIONS:-}" ]]; then
  run_all_checks || true
  emit_summary_and_exit
fi

run_all_checks || true
if ((${#failures[@]} > 0)); then
  emit_summary_and_exit
fi

if [[ "$RUN_MUTATIONS" -eq 1 ]]; then
  run_empty_root_selftests
  run_mutation_suite
  echo "SUMMARY: all checks passed (${mutation_pass} mutation proofs)"
else
  echo "SUMMARY: all checks passed"
fi
exit 0
