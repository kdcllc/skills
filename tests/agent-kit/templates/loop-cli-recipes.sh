#!/usr/bin/env bash
# Guard: LOOP_CLI recipe documentation — no bare Codex recipe in skills/ or docs/,
# driver header examples, and autonomous-loop ### CLI recipes subsection.
# Mutation proofs under FIXTURE_TMPDIR only. No network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

GUIDE="$REPO_ROOT/docs/agent-kit/guide/autonomous-loop.md"
LOOP_SH="$REPO_ROOT/skills/agent-kit/templates/loop/loop.sh"
HEADER_RECIPE='codex exec --sandbox danger-full-access'

CLI_RECIPES_TERMS=(
  '--bare'
  'ANTHROPIC_API_KEY'
  'apiKeyHelper'
  'OAuth'
  'permission mode'
  '--permission-mode'
  'CLAUDE.md'
  'workspace-write'
  'danger-full-access'
  'agent -p'
  '--force'
)

pass=0
fail=0
last_check_detail=""

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    *)
      fail=$((fail + 1))
      echo "FAIL: $2${3:+ -- $3}" >&2
      ;;
  esac
}

finish_suite() {
  echo
  echo "=== loop-cli-recipes summary ==="
  echo "PASS: $pass   FAIL: $fail"
  if ((fail)); then
    echo "RESULT: $fail assertion(s) FAILED"
    return 1
  fi
  echo "RESULT: all assertions passed"
  return 0
}

require_fixture_root() {
  if ! assert_fixture_root "$1"; then
    report FAIL "fixture-root" "refused mutation path (fail closed): $1"
    finish_suite
    exit 1
  fi
}

mutation_expect_fail() {
  local name="$1"
  shift
  last_check_detail=""
  local errf
  errf="$(mktemp)"
  if "$@" 2>"$errf"; then
    report FAIL "$name" "check still passed on mutant"
    rm -f "$errf"
    return 1
  fi
  rm -f "$errf"
  report PASS "$name"
  return 0
}

run_named_check() {
  local name="$1"
  shift
  last_check_detail=""
  local errf
  errf="$(mktemp)"
  if "$@" 2>"$errf"; then
    rm -f "$errf"
    report PASS "$name"
    return 0
  fi
  last_check_detail="$(tr '\n' ' ' <"$errf" | sed 's/  */ /g;s/ $//')"
  rm -f "$errf"
  report FAIL "$name" "$last_check_detail"
  return 1
}

# --- check helpers (optional root / file overrides for mutation copies) ---

check_no_bare_codex_recipe() {
  local root="${1:-$REPO_ROOT}"
  local skills="$root/skills"
  local docs="$root/docs"
  if [[ ! -d "$skills" ]]; then
    echo "missing directory: $skills" >&2
    return 1
  fi
  if [[ ! -d "$docs" ]]; then
    echo "missing directory: $docs" >&2
    return 1
  fi
  local hits
  hits="$(rg -n --hidden 'LOOP_CLI="codex exec"|LOOP_CLI = "codex exec"' "$skills" "$docs")"; local rc=$?
  if ((rc > 1)); then echo "rg failed (rc=$rc) scanning: $skills $docs" >&2; return 1; fi
  if [[ -n "$hits" ]]; then
    echo "bare Codex LOOP_CLI recipe found: $hits" >&2
    return 1
  fi
  return 0
}

check_driver_header_recipe() {
  local root="${1:-$REPO_ROOT}"
  local sh="${2:-$root/skills/agent-kit/templates/loop/loop.sh}"
  if [[ ! -f "$sh" ]]; then
    echo "missing file: $sh" >&2
    return 1
  fi
  if ! head -n 20 "$sh" | grep -qF -- "$HEADER_RECIPE"; then
    echo "first 20 lines of loop.sh lack explicit Codex recipe: $sh" >&2
    return 1
  fi
  return 0
}

extract_cli_recipes_subsection() {
  local f="$1"
  awk '
    /^### CLI recipes$/ { in_sub = 1; next }
    in_sub && /^###? / { exit }
    in_sub { print }
  ' "$f"
}

check_cli_recipes_heading() {
  local f="${1:-$GUIDE}"
  if [[ ! -f "$f" ]]; then
    echo "missing file: $f" >&2
    return 1
  fi
  local count
  count="$(rg -c '^### CLI recipes$' "$f" 2>/dev/null || true)"
  if [[ "$count" != "1" ]]; then
    echo "expected exactly one ### CLI recipes heading in $f (got: ${count:-0})" >&2
    return 1
  fi
  if ! awk '/^## Driver knobs/{d=1} /^## /&&!/^## Driver knobs/{d=0} d&&/^### CLI recipes$/{found=1} END{exit !found}' "$f"; then
    echo "### CLI recipes is not inside ## Driver knobs in $f" >&2
    return 1
  fi
  return 0
}

check_cli_recipes_terms() {
  local f="${1:-$GUIDE}"
  local subsection missing=() t
  if [[ ! -f "$f" ]]; then
    echo "missing file: $f" >&2
    return 1
  fi
  subsection="$(extract_cli_recipes_subsection "$f")"
  if [[ -z "$subsection" ]]; then
    echo "empty or missing ### CLI recipes subsection in $f" >&2
    return 1
  fi
  for t in "${CLI_RECIPES_TERMS[@]}"; do
    if ! grep -qF -- "$t" <<<"$subsection"; then
      missing+=("$t")
    fi
  done
  if ((${#missing[@]})); then
    echo "missing terms in CLI recipes subsection of $f: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

# --- canonical checks on the live repo (read-only) ---

run_named_check "case 1: no bare Codex LOOP_CLI in skills/ or docs/" check_no_bare_codex_recipe
run_named_check "case 2: driver headers document explicit Codex recipe" check_driver_header_recipe
run_named_check "case 3: exactly one ### CLI recipes under ## Driver knobs" check_cli_recipes_heading
run_named_check "case 4: CLI recipes subsection contains required terms" check_cli_recipes_terms

# --- mutation proofs (private temp copies only) ---

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/loop-cli-recipes.XXXXXX")" || exit 1
trap 'rm -rf "${FIXTURE_TMPDIR:-}"' EXIT
# shellcheck source=../lib/fixture-root.sh
REPO_ROOT="$REPO_ROOT" FIXTURE_TMPDIR="$FIXTURE_TMPDIR" source "$HERE/../lib/fixture-root.sh"

mut_root="$FIXTURE_TMPDIR/bare-recipe"
mkdir -p "$mut_root/skills" "$mut_root/docs/agent-kit/guide"
require_fixture_root "$mut_root"
printf '%s\n' 'LOOP_CLI="codex exec"' >"$mut_root/docs/agent-kit/guide/evil.md"
mutation_expect_fail "case 1 detects violation" check_no_bare_codex_recipe "$mut_root"

mut_root="$FIXTURE_TMPDIR/header-mut"
mkdir -p "$mut_root/skills/agent-kit/templates/loop"
require_fixture_root "$mut_root"
cp "$LOOP_SH" "$mut_root/skills/agent-kit/templates/loop/loop.sh"
sed -i 's/codex exec --sandbox danger-full-access/claude -p/' \
  "$mut_root/skills/agent-kit/templates/loop/loop.sh"
mutation_expect_fail "case 2 detects violation" check_driver_header_recipe "$mut_root"

mut_dir="$FIXTURE_TMPDIR/guide-heading-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut_guide="$mut_dir/autonomous-loop.md"
cp "$GUIDE" "$mut_guide"
python3 - <<'PY' "$mut_guide"
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "### CLI recipes\n"
if needle not in text:
    sys.exit("CLI recipes heading not found")
block_start = text.index(needle)
rest = text[block_start:]
next_h = rest.find("\n### ", len(needle))
if next_h == -1:
    next_h = rest.find("\n## ", len(needle))
if next_h == -1:
    sys.exit("no following heading")
block_end = block_start + next_h
block = text[block_start:block_end]
text = text[:block_start] + text[block_end:]
driver = "## Driver knobs\n"
if driver not in text:
    sys.exit("Driver knobs not found")
insert_at = text.index(driver) + len(driver)
text = text[:insert_at] + "\n## Wrong section\n\n" + block + text[insert_at:]
path.write_text(text)
PY
mutation_expect_fail "case 3 detects violation" check_cli_recipes_heading "$mut_guide"

mut_dir="$FIXTURE_TMPDIR/guide-term-mut"
mkdir -p "$mut_dir"
require_fixture_root "$mut_dir"
mut_guide="$mut_dir/autonomous-loop.md"
cp "$GUIDE" "$mut_guide"
sed -i 's/--force//g' "$mut_guide"
mutation_expect_fail "case 4 detects violation" check_cli_recipes_terms "$mut_guide"

missing_guide="$FIXTURE_TMPDIR/no-such-guide/autonomous-loop.md"
mkdir -p "$(dirname "$missing_guide")"
require_fixture_root "$FIXTURE_TMPDIR/no-such-guide"
if check_cli_recipes_heading "$missing_guide" 2>/dev/null; then
  report FAIL "case 5 detects missing input file" "check passed without guide file"
else
  err="$(check_cli_recipes_heading "$missing_guide" 2>&1 || true)"
  if [[ "$err" == *"$missing_guide"* ]]; then
    report PASS "case 5 detects missing input file"
  else
    report FAIL "case 5 detects missing input file" "stderr did not name file: $err"
  fi
fi

rm -rf "$FIXTURE_TMPDIR"
FIXTURE_TMPDIR=""
trap - EXIT

finish_suite
exit $?
