#!/usr/bin/env bash
# Guard: kit sources must not reintroduce legacy _goals/_research tokens outside
# an explicit allow-list (migration code, migration docs, legacy backfill labels).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
KIT="$REPO_ROOT/skills/agent-kit"

pass=0; fail=0

LEGACY_TOKEN_RE='(^|[^A-Za-z0-9])_(goals|research)([^A-Za-z0-9_]|$)'

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    *) fail=$((fail + 1)); echo "FAIL: $2${3:+ -- $3}" >&2 ;;
  esac
}

# file|extended-regex — the line must match this pattern to allow a legacy token hit
ALLOW=(
  'bin/emit.sh|_goals/backlog\.md\|_memory/loop/backlog\.md'
  'bin/emit.sh|RETIRED_GA_LINES='
  'bin/emit.sh|RETIRED_GI_LINES='
  'bin/emit.sh|\[ -d "\$ROOT/_goals" \]'
  'bin/emit.sh|if \[ -d "\$ROOT/_goals" \]'
  'bin/emit.sh|relpath="_goals/'
  'bin/emit.sh|find "\$ROOT/_goals"'
  'bin/emit.sh|if \[ -d "\$ROOT/_research" \]'
  'bin/emit.sh|find "\$ROOT/_research"'
  'bin/emit.sh|_research/\$base\|_memory/work/research/'
  'bin/emit.sh|moved legacy _goals/ and _research/'
  'bin/emit.sh|_goals/ or _research/ still exists'
  'templates/tools/memory.sh|"_goals/\$g/goal\.md"'
  'templates/memory/README.md|`/agent-kit --upgrade` moves legacy top-level `_goals/`'
  'templates/memory/README.md|Mapping: each `_goals/<goal>/`'
  'templates/memory/README.md|`_goals/archive/` is loop state'
  'templates/memory/README.md|`_research/` tree'
  'templates/memory/README.md|loop files `_goals/backlog.md`'
  'templates/memory/README.md|and `_goals/archive/`'
  'templates/memory/README.md|`_goals/breaker-state.json`'
  'templates/memory/README.md|Retired kit lines removed'
  'templates/memory/README.md|_goals/\*/orchestration-log\.md merge=union'
  'templates/memory/README.md|_goals/LEARNINGS\.md merge=union.*_goals/ESCALATIONS\.md merge=union'
  'templates/memory/README.md|^_goals/breaker-state\.json.*Leftover empty `_goals/`'
  'templates/memory/README.md|Leftover empty `_goals/` and `_research/`'
  'templates/memory/README.md|`_goals/<g>/goal.md`'
  'templates/skills/goal-criteria/SKILL.template.md|legacy `_goals/` / `_goals/archive/`'
  'SKILL.md|Legacy layout migration:'
  'SKILL.md|when `_goals/` or `_research/` still exist'
  'SKILL.md|`_goals/\*/orchestration-log.md merge=union'
  'SKILL.md|`_goals/LEARNINGS.md merge=union'
  'SKILL.md|`_goals/ESCALATIONS.md merge=union'
  'SKILL.md|`_goals/breaker-state.json`'
  'SKILL.md|list `_goals/backlog.md` as a seed'
  'README.md|when `_goals/` or `_research/` remain'
  'bin/README.md|legacy `_goals/` / `_research/`'
  'reference/harness-matrix.md|Legacy top-level `_goals/` / `_research/`'
)

line_allowed() {
  local relpath="$1" line="$2" entry f pat
  for entry in "${ALLOW[@]}"; do
    f="${entry%%|*}"
    pat="${entry#*|}"
    [[ "$relpath" == "$f" ]] || continue
    if grep -Eq "$pat" <<<"$line"; then
      return 0
    fi
  done
  return 1
}

line_has_legacy_token() {
  grep -Eq "$LEGACY_TOKEN_RE" <<<"$1"
}

scan_file() {
  local relpath="$1" abspath="$2" ln=0 bad=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    ln=$((ln + 1))
    line_has_legacy_token "$line" || continue
    if line_allowed "$relpath" "$line"; then
      continue
    fi
    bad=$((bad + 1))
    echo "  $relpath:$ln: $line" >&2
  done < "$abspath"
  [[ "$bad" -eq 0 ]]
}

violations=0
while IFS= read -r abspath; do
  relpath="${abspath#"$KIT"/}"
  scan_file "$relpath" "$abspath" || violations=$((violations + 1))
done < <(
  find "$KIT/templates" "$KIT/bin" "$KIT/emitters" "$KIT/reference" \
    "$KIT/SKILL.md" "$KIT/README.md" \
    -type f ! -name 'CHANGELOG.md' 2>/dev/null | LC_ALL=C sort
)

if [[ "$violations" -eq 0 ]]; then
  report PASS "legacy-path guard: no forbidden legacy tokens outside allow-list"
else
  report FAIL "legacy-path guard" "${violations} file(s) with forbidden hits — see stderr"
fi

# Negative control 1: non-allowlisted file with planted legacy path
neg="$(mktemp "${TMPDIR:-/tmp}/legpath.XXXXXX")"
cp "$KIT/templates/loop/loop.sh" "$neg"
printf '\n# PLANT forbidden legacy path reference _goals/planted/evil\n' >> "$neg"
if scan_file 'templates/loop/loop.sh' "$neg"; then
  report FAIL "legacy-path negative control (non-allowlisted file)" "planted line did not fail guard"
else
  report PASS "legacy-path negative control: planted _goals/ line fails guard"
fi
rm -f "$neg"

# Negative control 2: allow-listed file copy with a non-matching legacy token line
neg2="$(mktemp "${TMPDIR:-/tmp}/legpath2.XXXXXX")"
cp "$KIT/SKILL.md" "$neg2"
printf '\nDo not use _goals/planted/evil in new code.\n' >> "$neg2"
if scan_file 'SKILL.md' "$neg2"; then
  report FAIL "legacy-path negative control (allow-listed file)" "non-matching planted line did not fail guard"
else
  report PASS "legacy-path negative control: non-matching line in allow-listed file fails guard"
fi
rm -f "$neg2"

echo
echo "PASS: $pass   FAIL: $fail"
[[ "$fail" -eq 0 ]]
