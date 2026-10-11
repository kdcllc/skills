#!/usr/bin/env bash
# agent-kit guard, run by scripts/validate-skills.sh with the repo root as $1.
# Only checks that never read the local dogfood instance, so a stale or missing
# instance cannot fail validation for unrelated skills:
#   - emit the full instance from the dogfood fixture into a temp root (emit's
#     verify step fails on unresolved tokens, frontmatter names, and .cursor/
#     isolation);
#   - the developer-guide link checker;
#   - the invocation-flags template guard.
# The full suite (instance checks, harness, twin parity) is tests/agent-kit/run-all.sh.
set -u

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fail=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! out="$(bash "$ROOT/skills/agent-kit/bin/emit.sh" --root "$tmp" \
    --kit "$ROOT/skills/agent-kit" \
    --answers "$ROOT/tests/agent-kit/fixtures/self-answers.json" 2>&1)"; then
  echo "error: agent-kit: emit from the dogfood fixture failed" >&2
  printf '%s\n' "$out" | tail -n 20 >&2
  fail=1
fi

for t in tests/agent-kit/docs-link-check.sh tests/agent-kit/templates/invocation-flags.sh; do
  if ! out="$(bash "$ROOT/$t" 2>&1)"; then
    echo "error: agent-kit: $t failed" >&2
    printf '%s\n' "$out" | grep -E '^(FAIL|error)' | head -n 10 >&2
    fail=1
  fi
done

exit "$fail"
