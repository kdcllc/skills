#!/usr/bin/env bash
# Hidden grader for 01-trivial-fix. Usage: bash grade.sh <project-dir>
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

# no-regression: the project's tests pass and the count is not below the seed's
out=$(python3 -B -m unittest discover -s tests -t . 2>&1); rc=$?
n=$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' | tail -1)
[ "$rc" -eq 0 ] && [ -n "$n" ] && [ "$n" -ge "$(cat "$here/seed-test-count")" ]
check no-regression $?

# behaviour: the message for two inputs matches exactly
o1=$(python3 -B -m unitconv 10 2>/dev/null); o2=$(python3 -B -m unitconv 42.195 2>/dev/null)
[ "$o1" = "10.00 km = 6.21 miles" ] && [ "$o2" = "42.20 km = 26.22 miles" ]
check cli-output-two-inputs $?

# behaviour: the error path is unchanged
python3 -B -m unitconv abc >/dev/null 2>"$work/err"; erc=$?
[ "$erc" -eq 2 ] && [ "$(cat "$work/err")" = "error: not a number: abc" ]
check error-path-unchanged $?

# task-specific: exactly one non-test .py source differs from the seed
cur=$(find . -name '*.py' -not -path './tests/*' | sort | xargs -r sha256sum)
changed=$({ cat "$here/seed-sources.sha256"; printf '%s\n' "$cur"; } | sort | uniq -u | awk '{print $2}' | sort -u | wc -l)
[ "$changed" -eq 1 ]
check one-source-file-changed $?

if [ "$fail" -eq 0 ]; then echo "GRADE pass"; exit 0; fi
echo "GRADE fail"; exit 1
