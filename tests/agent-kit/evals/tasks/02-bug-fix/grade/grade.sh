#!/usr/bin/env bash
# Hidden grader for 02-bug-fix. Usage: bash grade.sh <project-dir>
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=${1:-}
if [ -z "$proj" ] || [ ! -d "$proj" ]; then
  echo "grade: project directory not found: ${proj:-<none>}" >&2
  exit 2
fi
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
mkdir "$work/p"
cp -R "$proj"/. "$work/p"/ || exit 2
cd "$work/p" || exit 2
rm -rf .git .claude _kit _loop _memory .pytest_cache .mypy_cache .ruff_cache
find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
export PYTHONDONTWRITEBYTECODE=1
fail=0
check() { if [ "$2" -eq 0 ]; then echo "CHECK pass $1"; else echo "CHECK fail $1"; fail=1; fi; }
hidden() { PYTHONPATH="$work/p" python3 -B -m unittest discover -s "$here/hidden" -p "$1" >/dev/null 2>&1; }

# no-regression: the project's tests pass and the count is not below the seed's
out=$(python3 -B -m unittest discover -s tests -t . 2>&1); rc=$?
n=$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' | tail -1)
[ "$rc" -eq 0 ] && [ -n "$n" ] && [ "$n" -ge "$(cat "$here/seed-test-count")" ]
check no-regression $?

hidden test_counts.py; check page-count-boundaries $?
hidden test_slices.py; check page-slice-boundaries $?
# task-specific: invalid page numbers and sizes raise ValueError
hidden test_invalid.py; check invalid-pages-raise-valueerror $?

if [ "$fail" -eq 0 ]; then echo "GRADE pass"; exit 0; fi
echo "GRADE fail"; exit 1
