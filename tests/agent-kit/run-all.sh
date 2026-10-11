#!/usr/bin/env bash
# Full agent-kit suite: refresh the gitignored dogfood instance, then run the
# structural checks, every template guard, the docs checker, and the loop /
# self-install harness. Prints one line per suite and exits non-zero when any
# suite fails.
#
# Usage (from anywhere):  bash tests/agent-kit/run-all.sh [--no-install]
#   --no-install  Skip scripts/agent-kit/self-install.sh (use the current instance).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

install=1
for arg in "$@"; do
  case "$arg" in
    --no-install) install=0 ;;
    *) echo "usage: $0 [--no-install]" >&2; exit 2 ;;
  esac
done

if (( install )); then
  if ! bash scripts/agent-kit/self-install.sh >/dev/null; then
    echo "FAIL  self-install (scripts/agent-kit/self-install.sh)"
    exit 1
  fi
  echo "ok    self-install"
fi

suites=(
  tests/agent-kit/checks.sh
  tests/agent-kit/docs-link-check.sh
)
for t in tests/agent-kit/templates/*.sh; do
  suites+=("$t")
done
suites+=(tests/agent-kit/loop-harness/run.sh)

failed=0
log_dir="$(mktemp -d)"
for t in "${suites[@]}"; do
  log="$log_dir/$(basename "$(dirname "$t")")-$(basename "$t" .sh).log"
  start=$SECONDS
  if bash "$t" >"$log" 2>&1; then
    printf 'ok    %s (%ss)\n' "$t" "$((SECONDS - start))"
  else
    failed=$((failed + 1))
    printf 'FAIL  %s (%ss) -- log: %s\n' "$t" "$((SECONDS - start))" "$log"
    grep -E '^(FAIL|error)' "$log" | head -n 10 | sed 's/^/        /'
  fi
done

if (( failed > 0 )); then
  echo "agent-kit: ${failed} suite(s) failed; logs in ${log_dir}"
  exit 1
fi
rm -rf "$log_dir"
echo "agent-kit: ${#suites[@]} suite(s) passed"
