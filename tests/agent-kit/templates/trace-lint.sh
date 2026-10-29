#!/usr/bin/env bash
# Guard: the `trace-lint` consumer-trace linter (tool, emit wiring, launcher).
#
# Behavioral section — runs the CANONICAL skills/agent-kit/templates/tools/trace-lint.sh
# (override with TRACE_LINT_BIN=<path> for mutation testing) over fixture goal files built in
# a temp dir from one valid base file and one literal replacement per case:
#   - valid traces exit 0 with the ok line (full trace, `none — reason`, fenced headings
#     ignored, CRLF input, `_memory/` hits ignored, `./`-prefixed hits, `Phase 6` under
#     `align_docs: true`, a double-backtick command containing ` — `, an escaped `\|`)
#   - one failing fixture per rule 1-9 (exit 3, that rule's message, `file:line` citations,
#     a last `trace-lint: <N> finding(s)` line whose N matches), plus the edge cases:
#     a single-file hit with no path, a Consumer cell split by an unescaped pipe, `1 hits`,
#     `Phase 6` under `align_docs: false` / the `true|false` placeholder / no key
#   - usage exit 2, missing file exit 4, `--help` exit 0, and a read-only run
#   - a fresh emit carries `_kit/trace-lint.sh` (executable, canonical bytes) and
#     `_kit/trace-lint.cmd` (the launcher template's bytes)
# Output follows the fix-cycle-provenance suite: PASS:/FAIL: lines, a summary, RESULT.
# Tracked, self-install-independent — no network, no LLM.
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

LINT="${TRACE_LINT_BIN:-$REPO_ROOT/skills/agent-kit/templates/tools/trace-lint.sh}"
LAUNCHER_TPL="$REPO_ROOT/skills/agent-kit/templates/tools/bash-launcher.cmd"
EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tracelint.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
# shellcheck source=../lib/emit-cache.sh
. "$HERE/../lib/emit-cache.sh"

pass=0
fail=0
skip=0

_suite_cleanup() {
  rm -rf "$FIXTURE_TMPDIR"
  emit_cache_cleanup
}
trap _suite_cleanup EXIT

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

FX="$FIXTURE_TMPDIR/fx"
mkdir -p "$FX"
BASE="$FX/base.md"

# The valid base trace: 3 searches (3 + 0 + 1 hits), 5 consumers, one row of every class
# shape (changes/task, changes/Phase 6, unaffected/test, unaffected/search, owner-excluded).
cat > "$BASE" <<'EOF'
# Goal: sample

## Problem Statement

Widgets drift.

## Discovery Summary (Phase 1 Q&A)

| # | Question | Answer |
|---|----------|--------|
| 1 | Scope | Docs under docs/old are excluded. |
| 2 | Release | Folded into the current release. |

## Searches

- **S1** `rg -n -H 'widget_id' src tests docs` — 3 hits
  ```text
  src/widget.sh:12:widget_id="$1"
  tests/widget.sh:4:assert widget_id
  docs/widget.md:7:The widget_id flag.
  ```
- **S2** `rg -n -H 'widgetId' docs` — 0 hits
  ```text
  ```
- **S3** `rg -n -H 'widget_ref' src` — 1 hit
  ```text
  src/ref.sh:3:widget_ref=1
  ```

## Consumers

| Surface | Consumer | Class | Evidence |
|---------|----------|-------|----------|
| `widget_id` | `src/widget.sh` | changes | task 01 |
| `widget_id` | `tests/widget.sh` | unaffected | test: `tests/widget.sh` |
| `widget_id` | `docs/widget.md` | changes | task 02 |
| `widgetId` | `docs/old/widget.md` | owner-excluded | Q&A row 1 |
| `widget_ref` | `src/ref.sh` | unaffected | search: S2 |

## Tasks (dependency order)

| # | Task file | Layer | Depends on |
|---|-----------|-------|------------|
| 01 | `01-widget.md` | src | — |

```yaml
phases:
  align_docs: true
```
EOF

BASE_OK='trace-lint: ok (3 searches, 5 consumers)'

# lit_replace <from> <to>: stdin → stdout with the first literal occurrence replaced;
# exit 1 when <from> is absent (so a stale fixture edit is never a silent no-op).
lit_replace() {
  FROM="$1" TO="$2" awk '
    BEGIN { RS = "\001"; from = ENVIRON["FROM"]; to = ENVIRON["TO"] }
    {
      i = index($0, from)
      if (i == 0) exit 1
      printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from))
    }'
}

# mk <name> [<from> <to>]... → $FX/<name>.md = the base with each replacement applied in order.
mk() {
  local name="$1" f="$FX/$1.md"
  shift
  cp "$BASE" "$f"
  while [ $# -ge 2 ]; do
    if lit_replace "$1" "$2" < "$f" > "$f.tmp"; then
      mv "$f.tmp" "$f"
    else
      rm -f "$f.tmp"
      report FAIL "fixture $name" "pattern not in base: $1"
    fi
    shift 2
  done
}

run() { # <args...> → RC, OUT (stdout), ERR (stderr)
  OUT="$("$BASH" "$LINT" "$@" 2>"$FX/stderr.txt")"
  RC=$?
  ERR="$(cat "$FX/stderr.txt")"
}

expect_ok() { # <name> <file> <want-line>
  run "$2"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$3" ] && [ -z "$ERR" ]; then
    report PASS "$1"
  else
    report FAIL "$1" "rc=$RC out=[$OUT] err=[$ERR]"
  fi
}

# expect_findings <name> <file> <message-substring> [<want-count>]: exit 3, every finding
# line is `trace-lint: <file>:<line>: <message>`, the last line counts them, the substring is
# in the output, and (when given) there are exactly <want-count> findings.
expect_findings() {
  local name="$1" f="$2" sub="$3" want="${4:-}" body last n bad
  run "$f"
  if [ "$RC" -ne 3 ]; then
    report FAIL "$name" "rc=$RC (want 3) out=[$OUT]"
    return
  fi
  last="$(printf '%s\n' "$OUT" | tail -n 1)"
  body="$(printf '%s\n' "$OUT" | sed '$d')"
  n="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  bad="$(printf '%s\n' "$body" | grep -vcE '^trace-lint: .+:[0-9]+: .+' || true)"
  if [ "$last" != "trace-lint: $n finding(s)" ]; then
    report FAIL "$name" "last line [$last] does not count $n finding line(s)"
  elif [ "$bad" != 0 ]; then
    report FAIL "$name" "finding line without file:line: out=[$OUT]"
  elif ! printf '%s\n' "$OUT" | grep -qF -- "$sub"; then
    report FAIL "$name" "message [$sub] not in out=[$OUT]"
  elif [ -n "$want" ] && [ "$n" != "$want" ]; then
    report FAIL "$name" "want $want finding(s), got $n: out=[$OUT]"
  else
    report PASS "$name"
  fi
}

# --- valid traces ---------------------------------------------------------------------------
expect_ok 'valid full trace → exit 0 with the ok line' "$BASE" "$BASE_OK"

cat > "$FX/none.md" <<'EOF'
# Goal: prose

## Consumers

none — the goal edits one paragraph of prose that no other component reads.

## Tasks (dependency order)
EOF
expect_ok 'valid `none — reason` trace → exit 0 with the none ok line' "$FX/none.md" \
  'trace-lint: ok (none — the goal edits one paragraph of prose that no other component reads.)'

mk fenced-headings 'Widgets drift.' 'Widgets drift.

```text
## Consumers
| fake | row | here | now |
## Searches
- **S9** broken
```'
expect_ok 'headings, rows and items inside fenced blocks are never read' "$FX/fenced-headings.md" "$BASE_OK"

awk '{ printf "%s\r\n", $0 }' "$BASE" > "$FX/crlf.md"
expect_ok 'CRLF line endings are accepted' "$FX/crlf.md" "$BASE_OK"

mk memory-hit '— 3 hits' '— 4 hits' \
  '  docs/widget.md:7:The widget_id flag.' '  docs/widget.md:7:The widget_id flag.
  _memory/records/2026/10/example.md:3:widget_id'
expect_ok 'a hit under _memory/ is ignored (no Consumer needed)' "$FX/memory-hit.md" "$BASE_OK"

mk dot-slash '  src/widget.sh:12:' '  ./src/widget.sh:12:'
expect_ok 'a leading ./ on a hit path is ignored' "$FX/dot-slash.md" "$BASE_OK"

mk phase6-true '| changes | task 02 |' '| changes | Phase 6 |'
expect_ok 'changes + Phase 6 under align_docs: true → passes' "$FX/phase6-true.md" "$BASE_OK"

mk phase6-comment '| changes | task 02 |' '| changes | Phase 6 |' \
  'align_docs: true' 'align_docs: true   # recorded from Phase 1'
expect_ok 'align_docs: true with a trailing comment still counts' "$FX/phase6-comment.md" "$BASE_OK"

mk task-letter '| changes | task 01 |' '| changes | task 01a (corrective) |'
expect_ok 'changes evidence task 01a (two digits plus a letter) → passes' "$FX/task-letter.md" "$BASE_OK"

mk dash-in-cmd '`rg -n -H '"'"'widgetId'"'"' docs` — 0 hits' '`rg -n -H '"'"'a — b'"'"' docs` — 0 hits'
expect_ok 'a command containing " — " (single-backtick span) → passes' "$FX/dash-in-cmd.md" "$BASE_OK"

mk bt-in-cmd '- **S2** `rg -n -H '"'"'widgetId'"'"' docs` — 0 hits' \
  '- **S2** ``rg -n -H '"'"'a ` b — c'"'"' docs`` — 0 hits'
expect_ok 'a command with " — " and a backtick in a double-backtick span → passes' "$FX/bt-in-cmd.md" "$BASE_OK"

mk pipe-escaped '  src/widget.sh:12:widget_id="$1"' '  src/a|b.sh:12:widget_id="$1"' \
  '`src/widget.sh`' '`src/a\|b.sh`'
expect_ok 'a Consumer cell with an escaped \| matches the hit path src/a|b.sh' "$FX/pipe-escaped.md" "$BASE_OK"

mk unaffected-diff '| unaffected | test: `tests/widget.sh` |' '| unaffected | diff: `git diff --stat -- src/widget.sh` |'
expect_ok 'unaffected evidence "diff: ..." → passes' "$FX/unaffected-diff.md" "$BASE_OK"

# --- rule 1: sections --------------------------------------------------------------------------
mk r1-no-consumers '## Consumers' '## Consumer'
expect_findings 'rule 1: missing ## Consumers' "$FX/r1-no-consumers.md" \
  "missing '## Consumers' section" 1

mk r1-fenced-consumers-only '## Consumers' '## Consumer' \
  'Widgets drift.' 'Widgets drift.

```text
## Consumers
```'
expect_findings 'rule 1: a ## Consumers heading inside a fence does not count' \
  "$FX/r1-fenced-consumers-only.md" "missing '## Consumers' section" 1

cat > "$FX/r1-none-with-searches.md" <<'EOF'
# Goal: prose

## Searches

- **S1** `rg -n -H 'x' src` — 0 hits
  ```text
  ```

## Consumers

none — nothing reads it.
EOF
expect_findings 'rule 1: "none — <reason>" with a ## Searches section present' \
  "$FX/r1-none-with-searches.md" "'## Searches' must be absent" 1

mk r1-no-searches '## Searches' '## Hits'
expect_findings 'rule 1: ## Searches missing when Consumers is not none' \
  "$FX/r1-no-searches.md" "missing '## Searches' section"

cat > "$FX/r1-no-items.md" <<'EOF'
# Goal: empty

## Searches

Nothing was searched.

## Consumers

| Surface | Consumer | Class | Evidence |
|---------|----------|-------|----------|
EOF
expect_findings 'rule 1: ## Searches without any item' "$FX/r1-no-items.md" \
  "'## Searches' has no items" 1

mk r1-header '| Surface | Consumer | Class | Evidence |' '| Surface | Consumer | Kind | Evidence |'
expect_findings 'rule 1: ## Consumers without the exact header row' "$FX/r1-header.md" \
  "must hold the header row '| Surface | Consumer | Class | Evidence |'" 1

# --- rule 2: search items ------------------------------------------------------------------------
mk r2-malformed '`rg -n -H '"'"'widgetId'"'"' docs` — 0 hits' '`rg -n -H '"'"'widgetId'"'"' docs` - 0 hits'
expect_findings 'rule 2: item without the em dash is malformed' "$FX/r2-malformed.md" \
  'malformed search item'

mk r2-nobackticks '- **S2** `rg -n -H '"'"'widgetId'"'"' docs` — 0 hits' '- **S2** rg -n -H widgetId docs — 0 hits'
expect_findings 'rule 2: item whose command is not in a code span is malformed' \
  "$FX/r2-nobackticks.md" 'malformed search item'

mk r2-one-hits '— 1 hit' '— 1 hits'
expect_findings 'rule 2: "1 hits" fails (1 hit is required)' "$FX/r2-one-hits.md" \
  "'1 hits' is invalid" 1

mk r2-many-hit '— 3 hits' '— 3 hit'
expect_findings 'rule 2: "3 hit" fails (hits is required when N is not 1)' "$FX/r2-many-hit.md" \
  "the word 'hit' is only for a count of 1" 1

mk r2-no-fence '- **S3** `rg -n -H '"'"'widget_ref'"'"' src` — 1 hit
  ```text' '- **S3** `rg -n -H '"'"'widget_ref'"'"' src` — 1 hit
  ```sh'
expect_findings 'rule 2: the next non-blank line must open a ```text fence' "$FX/r2-no-fence.md" \
  'must open a ```text block' 1

mk r2-count '— 3 hits' '— 4 hits'
expect_findings 'rule 2: the fence line count must equal N' "$FX/r2-count.md" \
  'S1 declares 4 hit(s) but its block has 3 non-empty line(s)' 1

# --- rule 3: unique ids ---------------------------------------------------------------------------
mk r3-dup '- **S3**' '- **S2**'
expect_findings 'rule 3: a repeated S<n> id' "$FX/r3-dup.md" 'duplicate search id S2' 1

# --- rule 4: hit lines ----------------------------------------------------------------------------
mk r4-nopath 'src/ref.sh:3:widget_ref=1' 'src/ref.sh widget_ref=1'
expect_findings 'rule 4: a hit line without :<line>: has no path' "$FX/r4-nopath.md" \
  'hit has no path (use -H)' 1

mk r4-single-file 'src/ref.sh:3:widget_ref=1' '3:widget_ref=1'
expect_findings 'rule 4: a single-file hit (no -H) "<line>:<text>" has no path' \
  "$FX/r4-single-file.md" 'hit has no path (use -H)' 1

# --- rule 5: every hit is listed --------------------------------------------------------------------
mk r5-unlisted '`src/ref.sh` | unaffected' '`src/other.sh` | unaffected'
expect_findings 'rule 5: a hit path that is not a Consumer' "$FX/r5-unlisted.md" \
  "hit path 'src/ref.sh' is not listed as a Consumer" 1

want_line="$(grep -n 'src/ref.sh:3:' "$FX/r5-unlisted.md" | cut -d: -f1)"
run "$FX/r5-unlisted.md"
if printf '%s\n' "$OUT" | grep -qF "trace-lint: $FX/r5-unlisted.md:$want_line: hit path 'src/ref.sh'"; then
  report PASS "rule 5: the finding cites the hit's own line ($want_line)"
else
  report FAIL "rule 5: the finding cites the hit's own line ($want_line)" "out=[$OUT]"
fi

mk r5-pipe-split '  src/widget.sh:12:widget_id="$1"' '  src/a|b.sh:12:widget_id="$1"' \
  '`src/widget.sh`' '`src/a|b.sh`'
expect_findings 'rule 5: a Consumer cell split by an unescaped pipe no longer matches the hit' \
  "$FX/r5-pipe-split.md" "hit path 'src/a|b.sh' is not listed as a Consumer"

# --- rule 6: class -------------------------------------------------------------------------------------
mk r6-class '| changes | task 01 |' '| change | task 01 |'
expect_findings 'rule 6: a class that is not changes/unaffected/owner-excluded' "$FX/r6-class.md" \
  "class 'change' must be exactly changes, unaffected or owner-excluded" 1

# --- rule 7: unaffected evidence -------------------------------------------------------------------------
mk r7-prefix 'test: `tests/widget.sh`' 'see tests/widget.sh'
expect_findings 'rule 7: unaffected evidence must start with test:/diff:/search:' \
  "$FX/r7-prefix.md" "unaffected evidence must start with 'test: ', 'diff: ' or 'search: S<n>'" 1

mk r7-search-hits 'search: S2' 'search: S3'
expect_findings 'rule 7: search: S<n> must name a search with 0 hits' "$FX/r7-search-hits.md" \
  "'search: S3' names a search with hits (needs 0 hits)" 1

mk r7-search-none 'search: S2' 'search: S9'
expect_findings 'rule 7: search: S<n> must name an existing search' "$FX/r7-search-none.md" \
  "'search: S9' names no search in '## Searches'" 1

mk r7-search-bare 'search: S2' 'search: none'
expect_findings 'rule 7: "search:" without an S<n> id is rejected' "$FX/r7-search-bare.md" \
  "unaffected evidence must start with" 1

# --- rule 8: owner-excluded evidence -------------------------------------------------------------------------
mk r8-shape 'Q&A row 1' 'decided by the owner'
expect_findings 'rule 8: owner-excluded evidence must contain Q&A row <n>' "$FX/r8-shape.md" \
  "owner-excluded evidence must contain 'Q&A row <n>'" 1

mk r8-row 'Q&A row 1' 'Q&A row 9'
expect_findings 'rule 8: Q&A row <n> must be a row of ## Discovery Summary' "$FX/r8-row.md" \
  "'Q&A row 9' is not a row of '## Discovery Summary'" 1

# --- rule 9: changes evidence -----------------------------------------------------------------------------------
mk r9-task '| changes | task 01 |' '| changes | task one |'
expect_findings 'rule 9: changes evidence must name task <NN>' "$FX/r9-task.md" \
  "changes evidence must contain 'task <NN>' or be exactly 'Phase 6'" 1

mk r9-task-digit '| changes | task 01 |' '| changes | task 1 |'
expect_findings 'rule 9: task 1 (one digit) is not task <NN>' "$FX/r9-task-digit.md" \
  "changes evidence must contain 'task <NN>'" 1

mk r9-phase7 '| changes | task 02 |' '| changes | Phase 7 |'
expect_findings 'rule 9: only Phase 6 is a valid phase evidence' "$FX/r9-phase7.md" \
  "changes evidence must contain 'task <NN>'" 1

mk r9-p6-false '| changes | task 02 |' '| changes | Phase 6 |' 'align_docs: true' 'align_docs: false'
expect_findings 'rule 9: Phase 6 under align_docs: false fails' "$FX/r9-p6-false.md" \
  "'Phase 6' is valid only when the goal sets 'align_docs: true'" 1

mk r9-p6-placeholder '| changes | task 02 |' '| changes | Phase 6 |' \
  'align_docs: true' 'align_docs: true|false    # recorded from Phase 1 answers'
expect_findings 'rule 9: Phase 6 under the align_docs: true|false placeholder fails' \
  "$FX/r9-p6-placeholder.md" "'Phase 6' is valid only when the goal sets 'align_docs: true'" 1

mk r9-p6-nokey '| changes | task 02 |' '| changes | Phase 6 |' 'align_docs: true' 'pull_request: false'
expect_findings 'rule 9: Phase 6 with no align_docs key fails' "$FX/r9-p6-nokey.md" \
  "'Phase 6' is valid only when the goal sets 'align_docs: true'" 1

# --- usage, exit codes, read-only -----------------------------------------------------------------------------
run
if [ "$RC" -eq 2 ] && printf '%s\n' "$ERR" | grep -qF 'usage: trace-lint.sh <goal.md>' && [ -z "$OUT" ]; then
  report PASS 'usage: no argument → exit 2 (usage on stderr, nothing on stdout)'
else
  report FAIL 'usage: no argument → exit 2' "rc=$RC out=[$OUT] err=[$ERR]"
fi

run "$BASE" "$BASE"
if [ "$RC" -eq 2 ] && [ -z "$OUT" ]; then
  report PASS 'usage: two arguments → exit 2'
else
  report FAIL 'usage: two arguments → exit 2' "rc=$RC out=[$OUT]"
fi

run --nope "$BASE"
if [ "$RC" -eq 2 ] && printf '%s\n' "$ERR" | grep -qF "unknown flag '--nope'"; then
  report PASS 'usage: unknown flag → exit 2 naming the flag'
else
  report FAIL 'usage: unknown flag → exit 2' "rc=$RC err=[$ERR]"
fi

run --help
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF 'usage: trace-lint.sh <goal.md>' && [ -z "$ERR" ]; then
  report PASS 'usage: --help → exit 0 with usage on stdout'
else
  report FAIL 'usage: --help → exit 0' "rc=$RC out=[$OUT] err=[$ERR]"
fi

run "$FX/does-not-exist.md"
if [ "$RC" -eq 4 ] && [ -z "$OUT" ] && printf '%s\n' "$ERR" | grep -q '^trace-lint: '; then
  report PASS 'missing file → exit 4 (message on stderr)'
else
  report FAIL 'missing file → exit 4' "rc=$RC out=[$OUT] err=[$ERR]"
fi

run "$FX"
if [ "$RC" -eq 4 ]; then
  report PASS 'a directory instead of a file → exit 4'
else
  report FAIL 'a directory instead of a file → exit 4' "rc=$RC"
fi

ro="$FX/ro"
mkdir -p "$ro"
cp "$BASE" "$ro/goal.md"
before="$(cksum < "$ro/goal.md")"
listing_before="$(cd "$ro" && ls -A)"
(cd "$ro" && "$BASH" "$LINT" goal.md >/dev/null 2>&1)
after="$(cksum < "$ro/goal.md")"
listing_after="$(cd "$ro" && ls -A)"
if [ "$before" = "$after" ] && [ "$listing_before" = "$listing_after" ]; then
  report PASS 'a run reads only the goal file and writes nothing (file bytes and directory unchanged)'
else
  report FAIL 'a run reads only the goal file and writes nothing' "before=[$before] after=[$after] ls=[$listing_after]"
fi

# --- portability ----------------------------------------------------------------------------------------------
if bash -n "$LINT" 2>/dev/null; then
  report PASS 'tool parses (bash -n)'
else
  report FAIL 'tool parses (bash -n)'
fi

if grep -nE 'declare -A|\$\{[a-zA-Z_]+,,\}|jq' "$LINT" >/dev/null 2>&1; then
  report FAIL 'tool is Bash 3.2 safe: no associative arrays, no ,, expansion, no JSON tool'
else
  report PASS 'tool is Bash 3.2 safe: no associative arrays, no ,, expansion, no JSON tool'
fi

if grep -nE '\{\{[A-Z_]*\}\}|BOOTSTRAP:' "$LINT" >/dev/null 2>&1; then
  report FAIL 'tool carries no template token or bootstrap comment'
else
  report PASS 'tool carries no template token or bootstrap comment'
fi

# --- fresh emit -------------------------------------------------------------------------------------------------
PAR_REPORT_FAIL="report"
emit_cache_init

alloc_root() {
  EMIT_ALLOC_PATH="$(mktemp -d "$FIXTURE_TMPDIR/root.XXXXXX")" || exit 1
  assert_fixture_root "$EMIT_ALLOC_PATH" || exit 1
}
alloc_root
root="$EMIT_ALLOC_PATH"
if emit_cache_copy "$root" "$FIXTURE"; then
  if [ -f "$root/_kit/trace-lint.sh" ] && [ -x "$root/_kit/trace-lint.sh" ]; then
    report PASS 'fresh emit: _kit/trace-lint.sh exists and is executable'
  else
    report FAIL 'fresh emit: _kit/trace-lint.sh exists and is executable'
  fi
  if cmp -s "$REPO_ROOT/skills/agent-kit/templates/tools/trace-lint.sh" "$root/_kit/trace-lint.sh"; then
    report PASS 'fresh emit: _kit/trace-lint.sh is byte-identical to the canonical tool'
  else
    report FAIL 'fresh emit: _kit/trace-lint.sh is byte-identical to the canonical tool'
  fi
  if [ -f "$root/_kit/trace-lint.cmd" ] && cmp -s "$LAUNCHER_TPL" "$root/_kit/trace-lint.cmd"; then
    report PASS 'fresh emit: _kit/trace-lint.cmd exists and equals the launcher template bytes'
  else
    report FAIL 'fresh emit: _kit/trace-lint.cmd exists and equals the launcher template bytes'
  fi
  out="$("$BASH" "$root/_kit/trace-lint.sh" "$BASE" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$BASE_OK" ]; then
    report PASS 'fresh emit: the emitted _kit/trace-lint.sh lints the base trace → exit 0'
  else
    report FAIL 'fresh emit: the emitted _kit/trace-lint.sh lints the base trace' "rc=$rc out=[$out]"
  fi
else
  report FAIL 'fresh emit: emit_cache_copy succeeded'
fi
emit_cache_verify

echo
echo "=== trace-lint summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
