#!/usr/bin/env bash
# Guard: canonical /research templates and memory wiring for tracked _memory/research/.
# PASS/FAIL lines; mutation proofs under mktemp only. No network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
KIT="$REPO_ROOT/skills/agent-kit"
TEMPLATES="$KIT/templates"

RESEARCH_TPL="$TEMPLATES/skills/research/SKILL.template.md"
BRIEF_TPL="$TEMPLATES/skills/research/templates/research-brief.md"
INDEX_TPL="$TEMPLATES/skills/research/templates/research-index.md"
MEM_PROTO="$TEMPLATES/skills/feature/reference/memory-protocol.md"
MEM_README="$TEMPLATES/memory/README.md"
GOAL_CRIT="$TEMPLATES/skills/goal-criteria/SKILL.template.md"

pass=0
fail=0

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    *) fail=$((fail + 1)); echo "FAIL: $2${3:+ -- $3}" >&2 ;;
  esac
}

finish_suite() {
  echo
  echo "PASS: $pass   FAIL: $fail"
  [[ "$fail" -eq 0 ]]
}

require_fixture_root() {
  if ! assert_fixture_root "$1"; then
    report FAIL "fixture-root" "refused mutation path (fail closed): $1"
    finish_suite; exit 1
  fi
}

mutation_expect_fail() {
  local name="$1"
  shift
  if "$@"; then
    report FAIL "${name}-mutation" "check still passed on mutant"
    return 1
  fi
  report PASS "${name}-mutation: check FAILs on mutant (load-bearing)"
  return 0
}

check_research_skill_paths() {
  local f="${1:-$RESEARCH_TPL}"
  [[ -f "$f" ]] || return 1
  grep -qF '_memory/work/research/<topic>/prompt.md' "$f" || return 1
  grep -qF '_memory/work/research/<topic>/review.md' "$f" || return 1
  grep -qF '_memory/research/<topic>.md' "$f" || return 1
  grep -qF '_memory/research/README.md' "$f" || return 1
  return 0
}

check_research_brief_template() {
  local f="${1:-$BRIEF_TPL}" key st
  [[ -f "$f" ]] || return 1
  for key in title topic date status goals supersedes memory; do
    grep -qE "^${key}:" "$f" || return 1
  done
  for st in proposed ingested adopted shipped superseded rejected; do
    grep -qF "$st" "$f" || return 1
  done
  return 0
}

check_research_index_template() {
  local f="${1:-$INDEX_TPL}"
  [[ -f "$f" ]]
}

check_no_research_prompts_under() {
  local dir="${1:-$TEMPLATES}"
  local hits
  hits="$(grep -rl 'research/prompts' "$dir" 2>/dev/null || true)"
  [[ -z "$hits" ]]
}

check_memory_protocol_research() {
  local f="${1:-$MEM_PROTO}"
  [[ -f "$f" ]] || return 1
  grep -qF '_memory/research/<topic>.md' "$f" || return 1
  grep -qF 'research-ingest' "$f" || return 1
  grep -qF 'status: shipped' "$f" || return 1
  grep -qF '_memory/research/README.md' "$f" || return 1
  return 0
}

check_memory_readme_research_tracked() {
  local f="${1:-$MEM_README}"
  [[ -f "$f" ]] || return 1
  grep -qF 'research/              # TRACKED' "$f" || return 1
  grep -qF '**Tracked:**' "$f" || return 1
  grep -qF 'research/' "$f" || return 1
  return 0
}

check_goal_criteria_research_writes() {
  local f="${1:-$GOAL_CRIT}"
  [[ -f "$f" ]] || return 1
  grep -qF '_memory/research/' "$f" || return 1
  grep -qF 'writes:' "$f" || return 1
  grep -qF 'NEEDS REVISION' "$f" || return 1
  return 0
}

check_goal_criteria_no_v018() {
  local f="${1:-$GOAL_CRIT}"
  [[ -f "$f" ]] || return 1
  ! grep -qF 'v0.18.0' "$f"
}

if check_research_skill_paths; then
  report PASS "research SKILL paths (_memory/work/research + _memory/research brief/index)"
else
  report FAIL "research SKILL paths (_memory/work/research + _memory/research brief/index)"
fi

if check_research_brief_template; then
  report PASS "research-brief.md frontmatter keys and six statuses"
else
  report FAIL "research-brief.md frontmatter keys and six statuses"
fi

if check_research_index_template; then
  report PASS "research-index.md template exists"
else
  report FAIL "research-index.md template exists"
fi

if check_no_research_prompts_under "$TEMPLATES"; then
  report PASS "templates tree has no research/prompts path"
else
  report FAIL "templates tree has no research/prompts path" "grep hit under templates/"
fi

if check_memory_protocol_research; then
  report PASS "memory-protocol names brief source and feature archive status update"
else
  report FAIL "memory-protocol names brief source and feature archive status update"
fi

if check_memory_readme_research_tracked; then
  report PASS "memory/README.md lists research/ as tracked"
else
  report FAIL "memory/README.md lists research/ as tracked"
fi

if check_goal_criteria_research_writes; then
  report PASS "goal-criteria flags _memory/research/ in writes carve-out"
else
  report FAIL "goal-criteria flags _memory/research/ in writes carve-out"
fi

if check_goal_criteria_no_v018; then
  report PASS "goal-criteria contains no v0.18.0"
else
  report FAIL "goal-criteria contains no v0.18.0"
fi

# --- mutation proofs (private temp copies only) ---
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/research-layout.XXXXXX")"
trap 'rm -rf "${FIXTURE_TMPDIR:-}"' EXIT
# shellcheck source=../lib/fixture-root.sh
REPO_ROOT="$REPO_ROOT" FIXTURE_TMPDIR="$FIXTURE_TMPDIR" source "$HERE/../lib/fixture-root.sh"

mut_dir="$FIXTURE_TMPDIR/skill-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/research-skill.md"
cp "$RESEARCH_TPL" "$mut"
sed -i '/_memory\/work\/research\/<topic>\/prompt\.md/d' "$mut"
mutation_expect_fail "research-skill-paths" check_research_skill_paths "$mut"

mut_dir="$FIXTURE_TMPDIR/brief-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/brief.md"
cp "$BRIEF_TPL" "$mut"
sed -i '/^memory:/d' "$mut"
mutation_expect_fail "research-brief-keys" check_research_brief_template "$mut"

mut_dir="$FIXTURE_TMPDIR/index-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/research-index.md"
cp "$INDEX_TPL" "$mut"
rm -f "$mut"
mutation_expect_fail "research-index-exists" check_research_index_template "$mut"

mut_tree="$FIXTURE_TMPDIR/templates-mini"
mkdir -p "$mut_tree/skills/research"
require_fixture_root "$mut_tree"
printf 'research/prompts/old\n' > "$mut_tree/skills/research/evil.txt"
mutation_expect_fail "no-research-prompts" check_no_research_prompts_under "$mut_tree"

mut_dir="$FIXTURE_TMPDIR/proto-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/mem-proto.md"
cp "$MEM_PROTO" "$mut"
sed -i 's/_memory\/research\/<topic>.md/_memory\/evil\/brief.md/' "$mut"
mutation_expect_fail "memory-protocol-research" check_memory_protocol_research "$mut"

mut_dir="$FIXTURE_TMPDIR/readme-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/mem-readme.md"
cp "$MEM_README" "$mut"
sed -i 's/research\/              # TRACKED/research\/              # SCRATCH/' "$mut"
mutation_expect_fail "memory-readme-tracked" check_memory_readme_research_tracked "$mut"

mut_dir="$FIXTURE_TMPDIR/goal-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/goal-crit.md"
cp "$GOAL_CRIT" "$mut"
sed -i '/_memory\/research\//d' "$mut"
mutation_expect_fail "goal-criteria-research-writes" check_goal_criteria_research_writes "$mut"

mut_dir="$FIXTURE_TMPDIR/v018-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut="$mut_dir/goal-v018.md"
cp "$GOAL_CRIT" "$mut"
printf '\nv0.18.0\n' >> "$mut"
mutation_expect_fail "goal-criteria-no-v018" check_goal_criteria_no_v018 "$mut"

rm -rf "$FIXTURE_TMPDIR"
FIXTURE_TMPDIR=""
trap - EXIT

finish_suite
