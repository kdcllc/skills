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

SEED_TESTS=2

# Tests for textstats exist: a test file imports it and the suite grew.
count_tests() {
  (cd "$P" && python3 -B -m unittest discover -s tests -t . 2>&1 |
    sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' | tail -1)
}
textstats_tests_added() {
  local n
  grep -rlw 'textstats' "$P/tests" >/dev/null 2>&1 || return 1
  n=$(count_tests)
  [ -n "$n" ] && [ "$n" -ge $((SEED_TESTS + 1)) ]
}

textstats_unchanged() {
  local want have
  want=$(tr -d '[:space:]' <"$HERE/textstats.sha256")
  have=$(sha256sum "$P/textstats.py" 2>/dev/null | cut -d' ' -f1)
  [ -n "$have" ] && [ "$want" = "$have" ]
}

# The agent's tests must fail when textstats.py is replaced by a mutant.
mutant_killed() {
  local m=$1 d="$WORK/mut-$(basename "$1" .py)"
  mkdir "$d" && cp -R "$P/." "$d/" || return 1
  cp "$m" "$d/textstats.py" || return 1
  if (cd "$d" && python3 -B -m unittest discover -s tests -t . >/dev/null 2>&1); then
    return 1
  fi
  return 0
}

check no-regression no_regression
check textstats-tests-added textstats_tests_added
check textstats-unchanged textstats_unchanged
for m in "$HERE"/mutants/*.py; do
  check "mutant-killed-$(basename "$m" .py)" mutant_killed "$m"
done

if [ "$FAILED" -eq 0 ]; then
  echo "GRADE pass"
  exit 0
fi
echo "GRADE fail"
exit 1
