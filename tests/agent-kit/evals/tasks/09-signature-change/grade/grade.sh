#!/usr/bin/env bash
# Hidden grader. Usage: bash grade.sh <project-dir>
# Prints CHECK pass|fail <name> per check, then GRADE pass|fail.
# Exit 0 all checks pass, 1 any check fails, 2 grader error.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJ=${1:-}
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "grade: project directory not found: ${PROJ}" >&2
  exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
P="$WORK/p"
mkdir "$P" && cp -R "$PROJ/." "$P/" || exit 2
# Judge only seed-relative paths: drop kit files and tool caches from the copy.
(
  cd "$P" || exit 1
  rm -rf .git .claude _kit _loop _memory CLAUDE.md AGENTS.md .gitignore \
    .gitattributes orchestration-kit.manifest.json
  find . \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache \
    -o -name .ruff_cache \) -type d -prune -exec rm -rf {} +
  find . -name '*.pyc' -type f -delete
) || exit 2

FAILED=0
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "CHECK pass $name"
  else
    echo "CHECK fail $name"
    FAILED=1
  fi
}

# No-regression: the project's tests pass and their count is not below the seed's.
no_regression() {
  local out n
  out=$(cd "$P" && python3 -B -m unittest discover -s tests -t . 2>&1) || return 1
  n=$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' | tail -1)
  [ -n "$n" ] && [ "$n" -ge "$SEED_TESTS" ]
}

hidden() { # hidden <file.py> [TestClass]
  local f=$1
  shift
  (cd "$WORK" && PROJ_DIR="$P" python3 -B "$HERE/$f" "$@")
}

SEED_TESTS=5

signature_required() { hidden hidden_money.py SignatureTests; }
format_rule() { hidden hidden_money.py FormatTests; }
callers_pass_currency() { hidden hidden_money.py CallerTests; }

check no-regression no_regression
check format-rule format_rule
check callers-pass-currency callers_pass_currency
check currency-required-no-default signature_required

if [ "$FAILED" -eq 0 ]; then
  echo "GRADE pass"
  exit 0
fi
echo "GRADE fail"
exit 1
