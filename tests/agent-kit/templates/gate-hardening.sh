#!/usr/bin/env bash
# Regression guard for the evaluator-gate hardening rules (goal evaluator-gate-hardening,
# tasks 01–06 and 04b): the F1–F7 floor, the citation rule, the required-fix line and the
# issue key (task-criteria), the evaluator verdict format, the fix-cycle flow (tree snapshots,
# changed list, citation and scope checks, backlog, keys, early ladder entry), the
# continuation-ladder and ORCHESTRATION mirrors, the quality-failure classes, the ship-pr
# backlog section, the harness-matrix hook addendum, and the maintainer-guide mirrors.
# Goal gate-hardening-backlog, task 06 adds exact anchors for the keys wording, the
# copied-template grouped-check proofs, and locks for the F5 mapping, the `uncited` key form,
# the every-evaluation fix-cycles paragraph and the `unknown` model_check sentence.
# Goal consumer-trace, task 06 locks the consumer-trace contract and flow: the goal template's
# `## Searches` / `## Consumers` / `trace:` key, the goal-criteria Phase 3 gate, pre-flight
# check 2, the goal-revisions amendment, the ORCHESTRATION flow, the evaluator consumer-trace
# mode and F6 audit item, and the emitter's `_kit/trace-lint` entries, each with a mutation proof.
# Goal release-backlog, task 06 isolates the evaluation-system F7 and Citations phrases, holds the KEYS
# anchors to an exact count of 1, locks the legacy-goal skip qualifier and clause, adds single-anchor
# proofs (the Who and Format labels, the preflight Searches sentence, the goal-revisions additive and
# no-sweep rules), and gives `emit_mutant` the same "nothing changed" guard as `mutation_proof`.
# Sections:
#   1. canonical checks — one named check per template or doc, every anchor a literal the
#      owning task wrote (no line numbers);
#   2. grouped checks — vocabulary, frontmatter validity and sibling-project naming;
#   3. a behavioral check of the canonical log-spawn.sh `keys` subcommand on fixture reports;
#   4. mutation proofs — each copies a real template or doc to a temp dir, removes or alters
#      one anchor, and asserts the matching check fails; a base run afterwards still passes;
#   5. a fresh-emit check of the floor and citation anchors in the emitted copies.
# Tracked, self-install-independent — no network, no LLM, no dependence on an emitted instance.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
GUIDE="$REPO_ROOT/docs/agent-kit/guide"

TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
DIAGNOSTICIAN="$TEMPLATES/agents/diagnostician.md"
FIX_CYCLES_REF="$TEMPLATES/skills/feature/reference/fix-cycles.md"
LADDER_REF="$TEMPLATES/skills/feature/reference/continuation-ladder.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
SHIP_PR="$TEMPLATES/skills/ship-pr/SKILL.template.md"
TEST_LADDER="$TEMPLATES/skills/test-ladder/SKILL.template.md"
GOAL_TEMPLATE="$TEMPLATES/skills/feature/templates/goal.md"
GOAL_CRITERIA="$TEMPLATES/skills/goal-criteria/SKILL.template.md"
PREFLIGHT_REF="$TEMPLATES/skills/feature/reference/preflight.md"
GOAL_REVISIONS_REF="$TEMPLATES/skills/feature/reference/goal-revisions.md"
LOOP_SKILL="$TEMPLATES/loop/SKILL.template.md"
MODELS_MAP="$TEMPLATES/models.map.md"
LOG_SPAWN_CANON="$TEMPLATES/tools/log-spawn.sh"
HARNESS_MATRIX="$REPO_ROOT/skills/agent-kit/reference/harness-matrix.md"
EMIT_BIN="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
EVALSYS_DOC="$GUIDE/evaluation-system.md"
FEATURE_WORKFLOW_DOC="$GUIDE/feature-workflow.md"
ARCHITECTURE_DOC="$GUIDE/architecture.md"
README_DOC="$GUIDE/README.md"
AGENTS_MODELS_DOC="$GUIDE/agents-and-models.md"
LOOP_DOC="$GUIDE/autonomous-loop.md"
DECISION_DOC="$GUIDE/decision-guide.md"

EMIT_SH="${EMIT_SH:-$EMIT_BIN}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akgh.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
# shellcheck source=../lib/emit-cache.sh
. "$HERE/../lib/emit-cache.sh"

pass=0
fail=0
skip=0

if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; else HAVE_JQ=0; fi

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

alloc_root() {
  EMIT_ALLOC_PATH="$(mktemp -d "$FIXTURE_TMPDIR/root.XXXXXX")" || exit 1
  assert_fixture_root "$EMIT_ALLOC_PATH" || exit 1
}

alloc_path() {
  EMIT_ALLOC_PATH="$(mktemp "$FIXTURE_TMPDIR/${1}.XXXXXX")"
}

# ---------------------------------------------------------------------------
# Literals shared by several checks
# ---------------------------------------------------------------------------
DRIFT_SENTENCE='Demoted `[backlog] [late]` notes count toward this total.'
TEMP_INDEX_CMD='GIT_INDEX_FILE=<temp> git read-tree HEAD && GIT_INDEX_FILE=<temp> git add -A && GIT_INDEX_FILE=<temp> git write-tree'
TAG_PLACEHOLDER='[line-patch|structural] [carried|regression|new]'
CIT_SENT_HEAD='In citation modes (Phase 4 task evaluations, ladder re-evaluations, Phase 5 audits), task-criteria'
CIT_SENT_TAIL='`NEEDS FIXES` needs at least one cited `major` or `blocker`.'
TERMINOLOGY_SENTENCE='Early arbitration (`criteria-defect`) ends at the human on criteria-sound; early ladder entry (a repeated `[structural]` key) continues to rung 4 on criteria-sound.'
EARLY_WORDING='(cycle 3, or earlier on early ladder entry)'
CYCLES_RAN='every cycle that ran (three, fewer on early ladder entry)'
FEATURE_SKILL_MAX_BYTES=11264
F5_SENTENCE='requirement that no `AC<n>` or `SC<n>` covers cites **`F5`**'
UNCITED_FORM='keys as `uncited <location> :: <defect>`, with the line suffix removed from the location'
EVERY_EVAL_READ='Also read it before every Phase 4 task evaluation and Phase 5 audit'
UNKNOWN_SENTENCE='a reported value starting with `unknown` always gives `model_check: unverified`'
ORCH_KEYS_PHRASE='appends a `KEYS` line (and a `REPEAT` line for each repeated key)'
EVALSYS_F7_PHRASE='(including **F7** for bypass-class problems'
EVALSYS_CITATIONS_PHRASE='§ **Citations** applies **only** to Phase 4 task evaluations'
WORKFLOW_KEYS_PHRASE='appends a `KEYS` line and a `REPEAT` line for each repeated key, each carrying kind and provenance tags'
F6_AUDIT_SENTENCE="A failure of either is a blocking finding citing **\`F6\`** against the goal's \`## Consumers\`."
PREFLIGHT_TRANSITION='**Transition:** a goal planned before this rule (no `## Consumers` section, with a `reference-sweep.md`) is checked against that artifact until its next material amendment.'
REVISIONS_STEP5='5. Confirm every `changes` row in `goal.md` `## Consumers` names a task that still exists after the renumbering.'
REVISIONS_AMEND='A surface the Phase 5 audit finds changed but not listed in `## Consumers` is an amendment: add the search, its hits and the row with evidence, re-run `_kit/trace-lint.sh`, then a targeted evaluation.'
TRACE_GATE_START='^[*][*]Consumer trace [(]Phase 3 gate[)][.][*][*]'
TRACE_GATE_END='^[*][*]Corrective tasks'
# Goal release-backlog, task 06: the legacy-goal skip carries its qualifier and its clause, the
# uncited old-shape example carries defect text, and the pointers name the bold paragraph.
LEGACY_SKIP_EVAL='(no `## Consumers` section) skips checks (a) and (b); check its legacy artifact as that rule states'
LEGACY_SKIP_ORCH='(no `## Consumers` section) skips checks (a) and (b); the audit checks its legacy artifact as that rule states'
UNCITED_OLD_SHAPE='the older ``- [ ] `file:line`: <defect> — fix`` shape'
EVAL_TRACE_POINTER='item 4 of the **Consumer trace (Phase 3 gate)** paragraph of'
ORCH_TRACE_POINTER='item 1 of the goal-criteria **Consumer trace (Phase 3 gate)** paragraph'
SHIP_PR_PREFIX='`- <goal>/B<n> (<source>): <finding>`'
CORRECTIVE_CHECKS='satisfies the Pairwise disjointness and Single owner checks of the seven write-set checks above'
PREFLIGHT_SEARCHES='`goal.md` carries `## Searches` and `## Consumers`'
REVISIONS_ADDITIVE='It is additive; when a missed consumer needs an edit, it is a corrective task'

# ---------------------------------------------------------------------------
# Helpers — every need_* records the first-order cause in MISSING instead of printing
# ---------------------------------------------------------------------------
MISSING=""
note_miss() { MISSING="${MISSING:+$MISSING; }$1"; }

count_fixed() { # count_fixed <file> <needle> → line count (0 if missing)
  local f="$1" needle="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cF -- "$needle" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

count_line_eq() { # count_line_eq <file> <exact line> → number of lines equal to it
  local f="$1" line="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cxF -- "$line" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

count_re() { # count_re <file> <ERE> → number of lines matching
  local f="$1" re="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cE -- "$re" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

flat() { # flat <file> → the whole file on one line, whitespace runs collapsed
  tr '\n\t' '  ' < "$1" | tr -s ' '
}

sec() { # sec <file> <start-ERE> <end-ERE> → lines after the start line, up to the end line
  awk -v s="$2" -v e="$3" 'f && $0 ~ e {exit} !f && $0 ~ s {f=1; next} f' "$1"
}

sec_flat() { sec "$@" | tr '\n\t' '  ' | tr -s ' '; }

need_eq() { # need_eq <file> <needle> <want>
  local got; got="$(count_fixed "$1" "$2")"
  [[ "$got" == "$3" ]] || note_miss "'$2' x$got (want $3)"
}

need_ge() { # need_ge <file> <needle> <min>
  local got; got="$(count_fixed "$1" "$2")"
  [[ "${got:-0}" -ge "$3" ]] || note_miss "'$2' x$got (want >= $3)"
}

need_line_eq() { # need_line_eq <file> <exact line> <want>
  local got; got="$(count_line_eq "$1" "$2")"
  [[ "$got" == "$3" ]] || note_miss "line '$2' x$got (want $3)"
}

need_re_eq() { # need_re_eq <file> <ERE> <want> <label>
  local got; got="$(count_re "$1" "$2")"
  [[ "$got" == "$3" ]] || note_miss "$4 x$got (want $3)"
}

need_re_ge() { # need_re_ge <file> <ERE> <min> <label>
  local got; got="$(count_re "$1" "$2")"
  [[ "${got:-0}" -ge "$3" ]] || note_miss "$4 x$got (want >= $3)"
}

need_flat() { # need_flat <file> <needle> — present in the whitespace-collapsed file
  flat "$1" | grep -qF -- "$2" || note_miss "flat '$2' absent"
}

need_none_flat() { # need_none_flat <file> <ERE> <label> [grep flags…] — absent in the collapsed file
  local f="$1" re="$2" label="$3"; shift 3
  if flat "$f" | grep -qE "$@" -- "$re"; then note_miss "stale wording: $label"; fi
}

need_sec_flat() { # need_sec_flat <file> <start-ERE> <end-ERE> <needle>
  sec_flat "$1" "$2" "$3" | grep -qF -- "$4" || note_miss "section '$2' lacks '$4'"
}

need_sec_re_ge() { # need_sec_re_ge <file> <start> <end> <ERE> <min> <label>
  local n; n="$(sec "$1" "$2" "$3" | grep -cE -- "$4" || true)"
  [[ "${n:-0}" -ge "$5" ]] || note_miss "$6 in section x${n:-0} (want >= $5)"
}

need_no_colon_space_description() { # a colon-space in a plain-scalar description is invalid YAML
  if grep -qE '^description: .*: ' "$1"; then note_miss "description contains colon-space"; fi
}

need_order() { # need_order <file> <label> <needle1> <needle2> … — first occurrences rise strictly
  local f="$1" label="$2" prev=0 cur needle; shift 2
  for needle in "$@"; do
    cur="$(grep -n -m1 -F -- "$needle" "$f" | cut -d: -f1)"
    if [[ -z "$cur" ]] || [[ "$cur" -le "$prev" ]]; then
      note_miss "$label order broken at '$needle'"
      return
    fi
    prev="$cur"
  done
}

citation_sentence_line() { # the one verdict sentence line of a file ('' when not exactly one)
  local f="$1"
  [[ "$(count_fixed "$f" "$CIT_SENT_HEAD")" == 1 ]] || { printf ''; return; }
  grep -F -- "$CIT_SENT_HEAD" "$f"
}

need_citation_sentence() { # need_citation_sentence <file> <other file> — one line, whole, identical
  local f="$1" other="$2" mine theirs
  mine="$(citation_sentence_line "$f")"
  theirs="$(citation_sentence_line "$other")"
  [[ -n "$mine" ]] || { note_miss "citation-mode sentence not exactly once"; return; }
  [[ "$mine" == *"$CIT_SENT_TAIL" ]] || note_miss "citation-mode sentence not whole on one line"
  [[ -n "$theirs" ]] || { note_miss "counterpart citation-mode sentence missing"; return; }
  [[ "$mine" == "$theirs" ]] || note_miss "citation-mode sentence differs between evaluator.md and evaluation-system.md"
}

emit_file_clean() { # no unresolved {{TOK}} or BOOTSTRAP[
  local f="$1"
  [[ -f "$f" ]] || return 1
  ! grep -qE '\{\{[A-Z_]+\}\}|BOOTSTRAP\[' "$f" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Canonical checks — one function per template or doc; $1 is the file under test
# ---------------------------------------------------------------------------
check_task_criteria() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_re_eq "$f" '^- \*\*F[0-9]+\*\* — ' 7 'floor items'
  need_re_eq "$f" '^- \*\*F[1-7]\*\* — ' 7 'floor items F1-F7'
  need_line_eq "$f" '## Floor' 1
  need_line_eq "$f" '## Citations' 1
  need_line_eq "$f" '### Issue key' 1
  need_eq "$f" 'ac2 src/a.sh :: missing guard' 1
  need_eq "$f" '<citation> `<location>`: <defect>' 1
  need_ge "$f" 'Changed since last evaluation' 1
  need_ge "$f" '[backlog] [late]' 1
  need_ge "$f" 'Phase 6 doc evaluations' 1
  need_eq "$f" "$DRIFT_SENTENCE" 1
  local tok
  for tok in 'F1' 'F3' 'F4' 'F7' 'AC<n>' 'reverses cycle N:'; do
    need_sec_flat "$f" '^## Provenance tags' '^## ' "$tok"
  done
  need_sec_flat "$f" '^### Issue key$' '^##' 'A `|` inside a key becomes `/`'
  need_sec_flat "$f" '^### Issue key$' '^##' '<citation> <location> :: <defect>'
  need_eq "$f" "$F5_SENTENCE" 1
  need_sec_flat "$f" '^### Issue key$' '^##' "$UNCITED_FORM"
  need_sec_flat "$f" '^### Issue key$' '^##' "$UNCITED_OLD_SHAPE"
  [[ -z "$MISSING" ]]
}

check_evaluator() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" '1. **[severity: blocker/major/minor]** <citation or "uncited"> `location` — [what is wrong and why it matters]' 1
  need_eq "$f" '- [ ] <citation> `<location>`: <defect> — <fix> [line-patch|structural] [carried|regression|new]' 1
  need_eq "$f" '- [ ] <citation> `file:line`: <defect> — replace `<exact old text>` with `<exact new text>` [line-patch]' 1
  need_eq "$f" "$TAG_PLACEHOLDER" 1
  need_eq "$f" '<citation> `<location>`: <defect>' 1
  need_ge "$f" '**Citations**' 1
  need_flat "$f" 'every cycle that ran'
  need_eq "$f" 'Phase 6 doc evaluations' 1
  need_eq "$f" 'no blockers,' 1
  need_ge "$f" "$DRIFT_SENTENCE" 1
  need_ge "$f" 'uncited ones tagged `[backlog]`, late demoted ones `[backlog] [late]`' 1
  need_flat "$f" "after fix-cycle exhaustion $EARLY_WORDING"
  need_flat "$f" "$CYCLES_RAN"
  need_none_flat "$f" 'fix cycles 1–3|after cycle-3 exhaustion|the three fix-cycle evaluator verdicts|after three implement' 'cycle-3 wording' -i
  need_no_colon_space_description "$f"
  need_citation_sentence "$f" "$EVALSYS_DOC"
  # consumer-trace mode, the Phase 3 re-run section and the Phase 5 F6 audit item
  need_line_eq "$f" '## Consumer-trace mode' 1
  need_ge "$f" '## Consumer trace (blind)' 1
  need_eq "$f" 'and consumer-trace mode excepted' 2
  need_flat "$f" 'add a `### Searches to re-run` section to the verdict'
  need_flat "$f" 'run the Phase 5 consumer check'
  need_flat "$f" "$F6_AUDIT_SENTENCE"
  need_ge "$f" 'skips checks (a) and (b)' 1
  need_flat "$f" "$LEGACY_SKIP_EVAL"
  # goal release-backlog, task 06: the two modes' evidence is separated, and the pointers name the bold paragraph
  need_flat "$f" 'Arbitration reviews criteria, not code, so its evidence is acceptance-criteria citation only'
  need_flat "$f" 'consumer-trace mode scores no work, so its evidence is the output of the searches it runs'
  need_flat "$f" 'A search-tool call prints no `rg` line, so write the equivalent command'
  need_flat "$f" 'then one `<path>:<line>:<text>` hit per match'
  need_flat "$f" "$EVAL_TRACE_POINTER"
  need_none_flat "$f" '§ Consumer trace' 'pointer to a heading that does not exist'
  [[ -z "$MISSING" ]]
}

check_diagnostician() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_none_flat "$f" 'three fix-cycle histories|fix-cycle 3 exhaustion|after three implement|cycles 1–3|post-cycle-3' 'cycle-3 wording' -i
  need_flat "$f" "after fix-cycle exhaustion $EARLY_WORDING"
  need_flat "$f" 'every fix-cycle history that ran'
  need_flat "$f" 'the cycles that ran'
  need_ge "$f" 'the three post-exhaustion implementation attempts' 1
  need_no_colon_space_description "$f"
  [[ -z "$MISSING" ]]
}

check_fix_cycles() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_ge "$f" 'eval-tree [#' 1
  need_ge "$f" 'git write-tree' 1
  need_ge "$f" 'Changed since last evaluation' 1
  need_ge "$f" 'git diff --name-only <previous sha> <current sha>' 1
  need_ge "$f" 'follow-ups.md' 1
  need_ge "$f" 'log-spawn.sh keys' 1
  need_eq "$f" "$TEMP_INDEX_CMD" 1
  need_ge "$f" 'round trip settles' 1
  need_ge "$f" 'Citation check' 1
  need_ge "$f" 'Late-finding scope check' 1
  need_flat "$f" 'asks the evaluator to correct the verdict'
  need_ge "$f" 'Rows use the form `- B<n> (<source>): <finding> — <status>`' 1
  need_eq "$f" "$DRIFT_SENTENCE" 1
  need_line_eq "$f" '## Early ladder entry' 1
  need_ge "$f" 'early ladder entry: ' 1
  local e='^## Early ladder entry$' x='^## '
  need_sec_flat "$f" "$e" "$x" 'Under `ladder: escalate` (default, or key absent), no decision reads `KEYS` or `REPEAT`; keys are log-only.'
  need_sec_flat "$f" "$e" "$x" 'Under `ladder: auto`, a `[structural]` `REPEAT` ends fix cycles before cycle 3'
  need_sec_flat "$f" "$e" "$x" '`[line-patch]` repeats never trigger it'
  need_sec_flat "$f" "$e" "$x" 'Unused fix cycles are not carried over'
  need_sec_flat "$f" "$e" "$x" "the ladder's budget and guards are unchanged"
  need_sec_flat "$f" "$e" "$x" 'a task never gets more attempts than on cycle-3 exhaustion'
  need_sec_flat "$f" '^## On cycle-3 exhaustion' "$x" '§ Early ladder entry'
  need_sec_flat "$f" '^## On cycle-3 exhaustion' "$x" 'rung 5 runs first'
  need_flat "$f" "$EVERY_EVAL_READ"
  [[ -z "$MISSING" ]]
}

check_ladder() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_line_eq "$f" '# Continuation ladder (cycle-3 exhaustion)' 1
  need_flat "$f" 'the ladder may also start early, per `reference/fix-cycles.md` § Early ladder entry'
  need_flat "$f" "$CYCLES_RAN"
  need_flat "$f" 'after the last fix cycle (cycle 3, or earlier on early entry)'
  need_ge "$f" "Issue keys are logged per the task-criteria skill's" 1
  need_ge "$f" '3 additional implementation attempts' 1
  need_eq "$f" "$DRIFT_SENTENCE" 1
  need_none_flat "$f" 'all three|after cycle 3' 'all-three / after-cycle-3 wording'
  [[ -z "$MISSING" ]]
}

check_orchestration() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_ge "$f" 'preexisting-dirty.txt' 1
  need_order "$f" 'QC class' '- **flaky** — ' '- **local-edits** — ' '- **pre-existing** — ' '- **introduced** — '
  need_re_ge "$f" 'flaky \(.*local-edits \(.*pre-existing \(.*introduced \(' 1 'Phase 5 class summary line'
  need_flat "$f" 'Loop runs never commit fixes for pre-existing failures'
  need_flat "$f" 'those failures become `follow-ups.md` rows'
  need_eq "$f" "$ORCH_KEYS_PHRASE" 1
  need_flat "$f" "$UNKNOWN_SENTENCE"
  need_ge "$f" 'eval-tree' 1
  need_ge "$f" 'log-spawn.sh keys' 1
  need_ge "$f" '**Early ladder entry** (`reference/fix-cycles.md` § Early ladder entry)' 1
  need_flat "$f" 'Phase 5 never enters the ladder early'
  need_ge "$f" 'Backlog (not fixed here)' 1
  need_ge "$f" 'open `follow-ups.md` rows' 2
  need_ge "$f" "$DRIFT_SENTENCE" 1
  need_flat "$f" 'after the last fix cycle (cycle 3, or earlier on early entry)'
  need_flat "$f" 'every cycle that ran'
  need_flat "$f" 'every fix-cycle history that ran'
  need_ge "$f" 'Diagnosis-only (post-exhaustion, no code writes)' 1
  need_flat "$f" 'fewer on early ladder entry'
  need_none_flat "$f" 'all three fix-cycle|after cycle 3|post-cycle-3|If cycles 1–3 all' 'cycle-3 wording'
  # consumer-trace flow: blind mode, Phase 3 re-runs, the Phase 5 changed-path list and F6
  need_ge "$f" 'consumer-trace mode' 1
  need_ge "$f" '### Searches to re-run' 1
  need_ge "$f" 'citing `F6`' 1
  need_ge "$f" 'base-commit.txt' 2
  need_ge "$f" 'git ls-files --others --exclude-standard' 1
  need_ge "$f" 'skips checks (a) and (b)' 1
  need_flat "$f" "$LEGACY_SKIP_ORCH"
  need_eq "$f" 'reference-sweep' 0
  # goal release-backlog, task 06: the orchestrator is the subject, the fix is a pre-flight fix,
  # and the pointer names the bold paragraph
  need_flat "$f" "The orchestrator diffs that trace's Consumer paths against"
  need_flat "$f" 'The orchestrator fixes pre-flight failures and logs them'
  need_none_flat "$f" 'It diffs that trace|§ Consumer trace' 'subject-less diff sentence or pointer to a heading that does not exist'
  need_flat "$f" "$ORCH_TRACE_POINTER"
  [[ -z "$MISSING" ]]
}

check_feature_skill() {
  local f="$1" bytes
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  bytes="$(wc -c < "$f" | tr -d ' ')"
  [[ "${bytes:-0}" -le "$FEATURE_SKILL_MAX_BYTES" ]] || note_miss "$bytes bytes (limit $FEATURE_SKILL_MAX_BYTES)"
  need_ge "$f" 'classify per ORCHESTRATION.md § Quality Checks' 1
  [[ -z "$MISSING" ]]
}

check_ship_pr() {
  local f="$1" h n
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_line_eq "$f" '## Backlog (not fixed here)' 1
  h="$(grep -n -m1 -xF -- '## Backlog (not fixed here)' "$f" | cut -d: -f1)"
  n="$(grep -n -m1 -xF -- '## Notes for reviewers' "$f" | cut -d: -f1)"
  if [[ -z "$h" || -z "$n" || "$h" -ge "$n" ]]; then note_miss "backlog section is not before '## Notes for reviewers'"; fi
  need_flat "$f" 'Omit this section when there are no open rows'
  need_flat "$f" 'Backlog rows are never described as fixed in the PR body'
  need_ge "$f" '- B<n> (<source>): <finding>' 1
  # the multi-goal prefix is in the body template as well as in the prose below it
  need_ge "$f" "$SHIP_PR_PREFIX" 2
  [[ -z "$MISSING" ]]
}

check_test_ladder() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_re_eq "$f" 'flaky.*local-edits.*pre-existing.*introduced' 1 'one-line class order'
  need_ge "$f" 'ORCHESTRATION.md `### Quality Checks`' 1
  [[ -z "$MISSING" ]]
}

check_harness_matrix() {
  local f="$1" h='^## Addendum 2026-10-27 — Cursor hook behavior$' x='^## ' term
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_line_eq "$f" '## Addendum 2026-10-27 — Cursor hook behavior' 1
  for term in 'staff-confirmed' 'documented' 'community-reported' 'unconfirmed'; do
    need_sec_flat "$f" "$h" "$x" "**$term**"
  done
  need_sec_re_ge "$f" "$h" "$x" 'kit_guard' 2 'kit_guard lines'
  need_sec_re_ge "$f" "$h" "$x" 'Cursor.{0,40}JSON|JSON.{0,40}Cursor' 1 'Cursor JSON reply line'
  need_sec_re_ge "$f" "$h" "$x" 'Copilot.*CLAUDE_PROJECT_DIR|CLAUDE_PROJECT_DIR.*Copilot' 1 'Copilot CLAUDE_PROJECT_DIR line'
  need_sec_flat "$f" "$h" "$x" 'Re-check these facts by 2027-01-27'
  need_eq "$f" 'superseded by the 2026-10-27 addendum' 1
  [[ -z "$MISSING" ]]
}

check_eval_system_doc() {
  local f="$1" t
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  local h='^## Floor, citations, and issue keys' x='^## '
  need_re_eq "$f" "$h" 1 'floor, citations, and issue keys heading'
  need_sec_flat "$f" "$h" "$x" "$EVALSYS_F7_PHRASE"
  need_sec_flat "$f" "$h" "$x" "$EVALSYS_CITATIONS_PHRASE"
  for t in 'Issue key' '[backlog] [late]' 'Changed since last evaluation'; do
    need_ge "$f" "$t" 1
  done
  need_ge "$f" "$DRIFT_SENTENCE" 3
  need_flat "$f" 'every cycle that ran'
  need_none_flat "$f" 'fix cycles 1–3|after cycle-3 exhaustion|the three fix-cycle evaluator verdicts|after three implement' 'cycle-3 wording' -i
  need_citation_sentence "$f" "$EVALUATOR"
  [[ -z "$MISSING" ]]
}

check_feature_workflow() {
  local f="$1" t
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  for t in 'preexisting-dirty.txt' 'follow-ups.md' 'Backlog (not fixed here)' 'eval-tree'; do
    need_ge "$f" "$t" 1
  done
  need_eq "$f" "$WORKFLOW_KEYS_PHRASE" 1
  need_re_ge "$f" '[Ee]arly ladder entry' 1 'early ladder entry'
  need_ge "$f" "$DRIFT_SENTENCE" 2
  need_eq "$f" 'Eval2 --> LadderEntry: repeated structural key · ladder auto' 1
  need_eq "$f" "$TERMINOLOGY_SENTENCE" 1
  need_none_flat "$f" 'all three|after cycle 3, summed|criteria-sound after cycle 3|On cycle-3 exhaustion — continuation|After cycle-3 exhaustion, if|only after cycle-3 exhaustion' 'cycle-3 wording'
  [[ -z "$MISSING" ]]
}

check_architecture_doc() {
  local f="$1" st ed
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" 'spawn/outcome/note/keys' 1
  need_ge "$f" "$DRIFT_SENTENCE" 1
  need_eq "$f" 'FixCycle --> LadderAuto: repeated structural key · early entry' 1
  st="$(grep -n -m1 -F -- 'state "Ladder auto" as LadderAuto' "$f" | cut -d: -f1)"
  ed="$(grep -n -m1 -F -- 'FixCycle --> LadderAuto: repeated structural key · early entry' "$f" | cut -d: -f1)"
  if [[ -z "$st" || -z "$ed" || "$ed" -le "$st" ]]; then note_miss "diagram edge is not after the LadderAuto state declaration"; fi
  need_eq "$f" "$TERMINOLOGY_SENTENCE" 1
  need_ge "$f" 'Rung5 --> Rung4: criteria-sound' 1
  need_eq "$f" 'criteria-sound after cycle 3' 0
  [[ -z "$MISSING" ]]
}

check_readme_doc() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_flat "$f" "after fix-cycle exhaustion $EARLY_WORDING"
  need_flat "$f" 'every fix-cycle history that ran'
  need_none_flat "$f" 'after fix-cycle 3|all three fix-cycle|fix cycles 1–3|three implement→evaluate fix cycles' 'cycle-3 wording' -i
  [[ -z "$MISSING" ]]
}

check_agents_models_doc() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_flat "$f" "after fix-cycle exhaustion $EARLY_WORDING"
  need_flat "$f" 'every fix-cycle history that ran'
  need_flat "$f" "$CYCLES_RAN"
  need_flat "$f" "When fix cycles are exhausted $EARLY_WORDING, the continuation ladder applies these pins:"
  need_ge "$f" "$DRIFT_SENTENCE" 2
  need_none_flat "$f" 'after fix-cycle 3|all three fix-cycle|fix cycles 1–3|three implement→evaluate fix cycles' 'cycle-3 wording' -i
  [[ -z "$MISSING" ]]
}

check_models_map() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_flat "$f" "When fix cycles are exhausted $EARLY_WORDING, the continuation ladder (see ORCHESTRATION.md) applies:"
  need_none_flat "$f" 'after fix-cycle 3|all three fix-cycle|fix cycles 1–3|three implement→evaluate fix cycles' 'cycle-3 wording' -i
  [[ -z "$MISSING" ]]
}

check_emit_pointer() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" "When fix cycles are exhausted $EARLY_WORDING" 1
  need_eq "$f" 'After three fix cycles' 0
  # the consumer-trace lint is a single-copy kit tool with a Windows launcher
  need_eq "$f" 'for f in log-spawn.sh memory.sh trace-lint.sh' 1
  need_ge "$f" '"_kit/trace-lint.cmd"' 1
  [[ -z "$MISSING" ]]
}

check_loop_skill() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_flat "$f" 'so cycle-3 exhaustion, or an earlier repeated structural fix (early ladder entry), runs the continuation ladder unattended'
  [[ -z "$MISSING" ]]
}

check_loop_doc() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_ge "$f" 'so cycle-3 exhaustion, or an earlier repeated structural fix (early ladder entry), runs the continuation ladder unattended' 2
  [[ -z "$MISSING" ]]
}

check_decision_doc() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_ge "$f" 'so cycle-3 exhaustion, or an earlier repeated structural fix (early ladder entry), runs the continuation ladder unattended' 1
  [[ -z "$MISSING" ]]
}

check_goal_template() {
  local f="$1" line
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" 'auto may enter it early (reference/fix-cycles.md § Early ladder entry)' 1
  line="$(grep -F -- 'auto may enter it early' "$f" | head -n 1)"
  [[ "$line" == *'ladder: escalate|auto'* ]] || note_miss "early-entry note is not on the 'ladder:' line"
  need_ge "$f" 'escalate (default): on cycle-3 exhaustion, escalate to the user with the continuation ladder offered' 1
  # consumer trace: the two sections, the table header and the `trace` phases key with its default
  need_line_eq "$f" '## Searches' 1
  need_line_eq "$f" '## Consumers' 1
  need_line_eq "$f" '| Surface | Consumer | Class | Evidence |' 1
  need_ge "$f" 'trace: planner|blind' 1
  need_ge "$f" 'planner (default): the planner-written trace only' 1
  [[ -z "$MISSING" ]]
}

check_goal_criteria() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" '**Consumer trace (Phase 3 gate).**' 1
  need_ge "$f" '### Searches to re-run' 1
  need_ge "$f" '_kit/trace-lint.sh' 1
  need_eq "$f" 'reference-sweep' 0
  need_eq "$f" 'follows the transition rule in the feature skill' 1
  # the five points of the gate, each inside the gate's own paragraph
  local t
  for t in '**Who.**' '**Format.**' '**Lint.**' '**Re-runs (mandatory).**' '**Trace choice.**'; do
    need_sec_flat "$f" "$TRACE_GATE_START" "$TRACE_GATE_END" "$t"
  done
  need_sec_flat "$f" "$TRACE_GATE_START" "$TRACE_GATE_END" '**Lint.** `_kit/trace-lint.sh <goal.md>` exits 0'
  need_sec_flat "$f" "$TRACE_GATE_START" "$TRACE_GATE_END" 'under `### Searches to re-run`'
  need_sec_flat "$f" "$TRACE_GATE_START" "$TRACE_GATE_END" '**provisional**'
  need_sec_flat "$f" "$TRACE_GATE_START" "$TRACE_GATE_END" '`trace: blind` is required when any surface is destructive'
  # goal release-backlog, task 06: the lead names which points are mechanical, and the corrective-task
  # clause names the write-set checks it relies on instead of numbering them after the new list
  need_flat "$f" 'checked on five points. Points 2 and 3 are mechanical, enforced by the pre-flight lint; points 1, 4 and 5 state their own verdict.'
  need_flat "$f" "$CORRECTIVE_CHECKS"
  need_none_flat "$f" 'checks 3–4' 'write-set checks numbered after the Consumer trace list'
  [[ -z "$MISSING" ]]
}

check_preflight() {
  local f="$1" s='^### 2[.] Missed callers' x='^### 3[.] '
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_sec_flat "$f" "$s" "$x" "$PREFLIGHT_SEARCHES"
  need_sec_flat "$f" "$s" "$x" 'Run `_kit/trace-lint.sh _memory/work/goals/<goal>/goal.md`'
  need_sec_flat "$f" "$s" "$x" '`trace-lint` exits non-zero'
  need_eq "$f" 'reference-sweep' 1
  need_sec_flat "$f" "$s" "$x" "$PREFLIGHT_TRANSITION"
  [[ -z "$MISSING" ]]
}

check_goal_revisions() {
  local f="$1"
  MISSING=""
  [[ -f "$f" ]] || { note_miss "file missing"; return 1; }
  need_eq "$f" "$REVISIONS_STEP5" 1
  need_eq "$f" "$REVISIONS_AMEND" 1
  need_ge "$f" "$REVISIONS_ADDITIVE" 1
  need_eq "$f" 'reference-sweep' 0
  [[ -z "$MISSING" ]]
}

# Grouped checks — take one or more files or directories.
# The stale-vocabulary stem is written with a character class so this guard never matches itself.
check_vocabulary() {
  MISSING=""
  local hits
  hits="$(grep -rIil 'ju[d]g' "$@" 2>/dev/null | head -n 3 | tr '\n' ' ')"
  [[ -z "$hits" ]] || note_miss "stale vocabulary in: $hits"
  [[ -z "$MISSING" ]]
}

check_frontmatter_descriptions() {
  MISSING=""
  local hits
  hits="$(grep -rIEn --include='*.md' '^description: .*: ' "$@" 2>/dev/null | head -n 3 | tr '\n' ' ')"
  [[ -z "$hits" ]] || note_miss "colon-space in a description: $hits"
  [[ -z "$MISSING" ]]
}

# Sibling-project names are written as character classes, so neither appears in this file.
check_sibling_names() {
  MISSING=""
  local hits
  hits="$(grep -rIEil -e '\bar[g]us\b|\bbe[a]m\b' "$@" 2>/dev/null | head -n 3 | tr '\n' ' ')"
  [[ -z "$hits" ]] || note_miss "sibling-project name in: $hits"
  [[ -z "$MISSING" ]]
}

# ---------------------------------------------------------------------------
# Behavioral check: the canonical log-spawn.sh `keys` subcommand on fixture reports
# ---------------------------------------------------------------------------
KEYS_G="_memory/work/goals/demo"

keys_fixture() { # keys_fixture <bin> → prints a root whose log holds SPAWN headings [#01]..[#06]
  local bin="$1" d i nn
  d="$(mktemp -d "$FIXTURE_TMPDIR/keysfx.XXXXXX")" || return 1
  assert_fixture_root "$d" || return 1
  mkdir -p "$d/$KEYS_G/spawns"
  for i in 1 2 3 4 5 6; do
    nn="$(printf '%02d' "$i")"
    printf 'ctx %s\n' "$nn" > "$d/$KEYS_G/spawns/$nn-context.md"
    bash "$bin" spawn --root "$d" --goal demo --agent evaluator --phase P4 \
      --model-requested m --context "$KEYS_G/spawns/$nn-context.md" >/dev/null 2>&1 || return 1
  done
  printf '%s' "$d"
}

keys_call() { # keys_call <bin> <root> <spawn> <task> <report> → KRC
  bash "$1" keys --root "$2" --goal demo --spawn "$3" --task "$4" --report "$KEYS_G/spawns/$5" >/dev/null 2>&1
  KRC=$?
}

check_keys_behavior() {
  local bin="$1" fx log lines_a lines_b rc_dup rc_missing want_a want_b
  MISSING=""
  [[ -f "$bin" ]] || { note_miss "file missing"; return 1; }
  fx="$(keys_fixture "$bin")"
  [[ -n "$fx" ]] || { note_miss "fixture setup failed"; return 1; }
  log="$fx/$KEYS_G/orchestration-log.md"

  # Two evaluations of task 01: the [structural] item repeats → exactly one REPEAT.
  printf '%s\n' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC2 `src/a.sh:12-14`: missing guard — add the check [structural]' \
    > "$fx/$KEYS_G/spawns/r1.md"
  printf '%s\n' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC2 `src/a.sh:20`: missing guard — add the check, sharper wording [structural] [carried]' \
    > "$fx/$KEYS_G/spawns/r2.md"
  keys_call "$bin" "$fx" 01 01 r1.md; rc_dup=$KRC
  keys_call "$bin" "$fx" 02 01 r2.md; rc_missing=$KRC
  [[ $rc_dup -eq 0 && $rc_missing -eq 0 ]] || note_miss "two evaluations: keys exited $rc_dup/$rc_missing (want 0/0)"
  want_a='- KEYS [#01] task 01: ac2 src/a.sh :: missing guard [structural] [-]'
  grep -qxF -- "$want_a" "$log" 2>/dev/null || note_miss "first KEYS line absent or wrong"
  want_b='- REPEAT [#02] task 01: ac2 src/a.sh :: missing guard [structural] [carried]'
  grep -qxF -- "$want_b" "$log" 2>/dev/null || note_miss "[structural] REPEAT line absent or wrong"
  [[ "$(grep -c '^- REPEAT ' "$log" 2>/dev/null || true)" == 1 ]] || note_miss "two evaluations did not yield exactly one REPEAT"

  # A repeated [line-patch] item (task 02) → a REPEAT that carries [line-patch].
  printf '%s\n' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `b.sh:3`: wrong exit — replace `1` with `2` [line-patch]' > "$fx/$KEYS_G/spawns/r3.md"
  printf '%s\n' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `b.sh:5`: wrong exit — replace `1` with `2` [line-patch] [carried]' > "$fx/$KEYS_G/spawns/r4.md"
  keys_call "$bin" "$fx" 03 02 r3.md
  keys_call "$bin" "$fx" 04 02 r4.md
  want_a='- REPEAT [#04] task 02: ac1 b.sh :: wrong exit [line-patch] [carried]'
  grep -qxF -- "$want_a" "$log" 2>/dev/null || note_miss "[line-patch] REPEAT line absent or wrong"
  [[ "$(grep -c '^- REPEAT ' "$log" 2>/dev/null || true)" == 2 ]] || note_miss "line-patch repeat did not yield the second REPEAT"

  # An old-shape uncited item (first word is a backtick span) keys as `uncited <location> :: <defect>`.
  printf '%s\n' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] `src/a.sh:12`: missing guard — fix it [structural]' > "$fx/$KEYS_G/spawns/r5.md"
  keys_call "$bin" "$fx" 05 03 r5.md
  [[ $KRC -eq 0 ]] || note_miss "uncited item: keys exited $KRC (want 0)"
  want_a='- KEYS [#05] task 03: uncited src/a.sh :: missing guard [structural] [-]'
  grep -qxF -- "$want_a" "$log" 2>/dev/null || note_miss "uncited KEYS line absent or wrong"
  [[ "$(grep -c '^- REPEAT ' "$log" 2>/dev/null || true)" == 2 ]] || note_miss "an uncited first appearance produced a REPEAT"

  # Ledger integrity (exit 3): a duplicate KEYS [#NN], and a spawn number with no SPAWN heading.
  lines_a="$(wc -l < "$log" | tr -d ' ')"
  keys_call "$bin" "$fx" 01 01 r1.md; rc_dup=$KRC
  keys_call "$bin" "$fx" 99 01 r1.md; rc_missing=$KRC
  lines_b="$(wc -l < "$log" | tr -d ' ')"
  [[ $rc_dup -eq 3 ]] || note_miss "duplicate KEYS [#01] exited $rc_dup (want 3)"
  [[ $rc_missing -eq 3 ]] || note_miss "spawn 99 without a SPAWN heading exited $rc_missing (want 3)"
  [[ "$lines_a" == "$lines_b" ]] || note_miss "an error path appended to the log"
  [[ -z "$MISSING" ]]
}

# ---------------------------------------------------------------------------
# Runner helpers
# ---------------------------------------------------------------------------
run_check() { # run_check <name> <check_fn> <args…>
  local name="$1" fn="$2"; shift 2
  if "$fn" "$@"; then
    report PASS "canonical $name"
  else
    report FAIL "canonical $name" "$MISSING"
  fi
}

canonical_entries() { # name<TAB>path<TAB>check function
  printf '%s\t%s\t%s\n' \
    'task-criteria/SKILL.template.md' "$TASK_CRITERIA" check_task_criteria \
    'agents/evaluator.md' "$EVALUATOR" check_evaluator \
    'agents/diagnostician.md' "$DIAGNOSTICIAN" check_diagnostician \
    'feature/reference/fix-cycles.md' "$FIX_CYCLES_REF" check_fix_cycles \
    'feature/reference/continuation-ladder.md' "$LADDER_REF" check_ladder \
    'ORCHESTRATION.md' "$ORCH_TEMPLATE" check_orchestration \
    'feature/SKILL.template.md (size and QC pointer)' "$FEATURE_SKILL" check_feature_skill \
    'ship-pr/SKILL.template.md' "$SHIP_PR" check_ship_pr \
    'test-ladder/SKILL.template.md' "$TEST_LADDER" check_test_ladder \
    'reference/harness-matrix.md' "$HARNESS_MATRIX" check_harness_matrix \
    'feature/templates/goal.md' "$GOAL_TEMPLATE" check_goal_template \
    'goal-criteria/SKILL.template.md (consumer trace gate)' "$GOAL_CRITERIA" check_goal_criteria \
    'feature/reference/preflight.md (check 2)' "$PREFLIGHT_REF" check_preflight \
    'feature/reference/goal-revisions.md' "$GOAL_REVISIONS_REF" check_goal_revisions \
    'bin/emit.sh (Codex pointer, trace-lint tool)' "$EMIT_BIN" check_emit_pointer \
    'models.map.md' "$MODELS_MAP" check_models_map \
    'loop/SKILL.template.md' "$LOOP_SKILL" check_loop_skill \
    'docs evaluation-system.md' "$EVALSYS_DOC" check_eval_system_doc \
    'docs feature-workflow.md' "$FEATURE_WORKFLOW_DOC" check_feature_workflow \
    'docs architecture.md' "$ARCHITECTURE_DOC" check_architecture_doc \
    'docs README.md' "$README_DOC" check_readme_doc \
    'docs agents-and-models.md' "$AGENTS_MODELS_DOC" check_agents_models_doc \
    'docs autonomous-loop.md' "$LOOP_DOC" check_loop_doc \
    'docs decision-guide.md' "$DECISION_DOC" check_decision_doc \
    'log-spawn.sh keys behavior (canonical tool)' "$LOG_SPAWN_CANON" check_keys_behavior
}

grouped_checks() { # run the grouped checks once, reporting each (arg: pass|quiet)
  local mode="$1" rc=0
  if check_vocabulary "$TEMPLATES/agents" "$TEMPLATES/skills" "$ORCH_TEMPLATE"; then
    [[ "$mode" == quiet ]] || report PASS 'canonical vocabulary: no stale word in templates/agents, templates/skills, ORCHESTRATION.md'
  else
    rc=1; [[ "$mode" == quiet ]] || report FAIL 'canonical vocabulary' "$MISSING"
  fi
  if check_frontmatter_descriptions "$TEMPLATES/agents" "$TEMPLATES/skills" "$LOOP_SKILL"; then
    [[ "$mode" == quiet ]] || report PASS 'canonical frontmatter: no description line holds a colon-space'
  else
    rc=1; [[ "$mode" == quiet ]] || report FAIL 'canonical frontmatter' "$MISSING"
  fi
  if check_sibling_names "$REPO_ROOT/skills/agent-kit" "$REPO_ROOT/docs/agent-kit" "$REPO_ROOT/tests/agent-kit"; then
    [[ "$mode" == quiet ]] || report PASS 'naming: no sibling-project name in skills/agent-kit, docs/agent-kit, tests/agent-kit'
  else
    rc=1; [[ "$mode" == quiet ]] || report FAIL 'naming' "$MISSING"
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# Mutators (operate on a copy) and the mutation-proof runner
# ---------------------------------------------------------------------------
m_sub() { # m_sub <file> <from> <to> — replace every literal occurrence
  local f="$1" from="$2" to="$3" c r
  c="$(cat "$f"; printf x)"; c="${c%x}"
  r=${c//"$from"/$to}
  printf '%s' "$r" > "$f"
}

m_swap() { # m_swap <file> <a> <b> — exchange two literal strings
  m_sub "$1" "$2" '@@SWAP@@'
  m_sub "$1" "$3" "$2"
  m_sub "$1" '@@SWAP@@' "$3"
}

m_del_lines() { # m_del_lines <file> <fixed> — drop every line containing the string
  grep -vF -- "$2" "$1" > "$1.new"
  mv "$1.new" "$1"
}

m_append() { # m_append <file> <line>
  printf '%s\n' "$2" >> "$1"
}

m_pad() { # m_pad <file> <bytes> — append that many filler bytes
  head -c "$2" /dev/zero | tr '\0' 'x' >> "$1"
}

mutation_proof() { # mutation_proof <name> <src> <check_fn> <mutator> [args…]
  local name="$1" src="$2" check_fn="$3" mut="$4" d copy
  shift 4
  d="$(mktemp -d "$FIXTURE_TMPDIR/mut.XXXXXX")" || { report FAIL "mutation-proof $name" "mktemp failed"; return; }
  copy="$d/$(basename "$src")"
  cp "$src" "$copy" || { report FAIL "mutation-proof $name" "copy failed"; rm -rf "$d"; return; }
  "$mut" "$copy" "$@"
  if cmp -s "$src" "$copy"; then
    report FAIL "mutation-proof $name" "the mutation changed nothing"
  elif "$check_fn" "$copy"; then
    report FAIL "mutation-proof $name" "check still passed on the mutated copy"
  else
    report PASS "mutation-proof $name" "check failed on: ${MISSING:0:110}"
  fi
  rm -rf "$d"
}

mutation_proof_copy() { # mutation_proof_copy <name> <src> <check_fn> <mutator> [args…]
  # For the grouped checks (they scan a directory). Copies a real template or doc into a fresh
  # temp directory, asserts the check passes on the clean copy (true negative), mutates the
  # copy, and asserts the check then fails (true positive).
  local name="$1" src="$2" check_fn="$3" mut="$4" d copy
  shift 4
  d="$(mktemp -d "$FIXTURE_TMPDIR/grp.XXXXXX")" || { report FAIL "mutation-proof $name" "mktemp failed"; return; }
  copy="$d/$(basename "$src")"
  cp "$src" "$copy" || { report FAIL "mutation-proof $name" "copy failed"; rm -rf "$d"; return; }
  if ! "$check_fn" "$d"; then
    report FAIL "mutation-proof $name" "clean copy was rejected: $MISSING"
    rm -rf "$d"; return
  fi
  "$mut" "$copy" "$@"
  if cmp -s "$src" "$copy"; then
    report FAIL "mutation-proof $name" "the mutation changed nothing"
  elif "$check_fn" "$d"; then
    report FAIL "mutation-proof $name" "check still passed on the mutated copy"
  else
    report PASS "mutation-proof $name" "check failed on: ${MISSING:0:110}"
  fi
  rm -rf "$d"
}

# The stale-vocabulary stem and the sibling-project name are assembled at run time, so this
# file never holds either one literally.
stale_stem() { printf '%s%s' ju dg; }
sibling_name() { printf '%s%s' ar gus; }

# ---------------------------------------------------------------------------
# Fresh-emit check
# ---------------------------------------------------------------------------
answers_for_emit() { # outfile
  jq '
    .harnesses = ["claude-code", "cursor"] |
    .primary = "claude-code" |
    .flags.research = false |
    .flags.loop = false
  ' "$FIXTURE" > "$1"
}

check_emitted_gate_anchors() { # check_emitted_gate_anchors <emit root>
  local root="$1" ide base
  MISSING=""
  [[ -d "$root" ]] || { note_miss "emit root missing"; return 1; }
  for ide in .claude .cursor; do
    base="$root/$ide"
    local tc="$base/skills/task-criteria/SKILL.md"
    local ev="$base/agents/evaluator.md"
    local fc="$base/skills/feature/reference/fix-cycles.md"
    local orch="$base/ORCHESTRATION.md"
    local f
    for f in "$tc" "$ev" "$fc" "$orch"; do
      [[ -f "$f" ]] || { note_miss "$ide: ${f#"$base"/} missing"; continue; }
      if grep -qE '\{\{[A-Z_]+\}\}' "$f"; then note_miss "$ide: ${f#"$base"/} has an unresolved token"; fi
    done
    [[ -f "$tc" && -f "$ev" && -f "$fc" && -f "$orch" ]] || continue
    # floor and citation anchors
    need_re_eq "$tc" '^- \*\*F[1-7]\*\* — ' 7 "$ide task-criteria floor items"
    need_line_eq "$tc" '## Floor' 1
    need_line_eq "$tc" '## Citations' 1
    need_line_eq "$tc" '### Issue key' 1
    need_eq "$tc" 'ac2 src/a.sh :: missing guard' 1
    need_ge "$tc" '[backlog] [late]' 1
    need_ge "$ev" '**Citations**' 1
    need_eq "$ev" "$TAG_PLACEHOLDER" 1
    need_eq "$ev" "$CIT_SENT_HEAD" 1
    need_ge "$fc" 'eval-tree [#' 1
    need_eq "$fc" "$TEMP_INDEX_CMD" 1
    need_line_eq "$fc" '## Early ladder entry' 1
    need_ge "$fc" 'log-spawn.sh keys' 1
    need_ge "$orch" 'Backlog (not fixed here)' 1
    need_ge "$orch" 'preexisting-dirty.txt' 1
    need_ge "$orch" '**Early ladder entry**' 1
    # consumer-trace contract: the emitted feature goal template carries the two sections
    local gt="$base/skills/feature/templates/goal.md"
    if [[ ! -f "$gt" ]]; then
      note_miss "$ide: skills/feature/templates/goal.md missing"
    else
      need_line_eq "$gt" '## Searches' 1
      need_line_eq "$gt" '## Consumers' 1
      need_ge "$gt" 'trace: planner|blind' 1
    fi
  done
  # the consumer-trace lint is emitted once, under _kit/, with its Windows launcher
  [[ -f "$root/_kit/trace-lint.sh" ]] || note_miss "_kit/trace-lint.sh missing from the emit"
  [[ -f "$root/_kit/trace-lint.cmd" ]] || note_miss "_kit/trace-lint.cmd missing from the emit"
  [[ -z "$MISSING" ]]
}

emit_mutant() { # emit_mutant <name> <emit root> <path under root> <mutator> [args…]
  # Copies the fresh emit, mutates one emitted file (or removes it with m_rm), and asserts that
  # check_emitted_gate_anchors fails on the copy.
  local name="$1" root="$2" rel="$3" mut="$4" d copy
  shift 4
  d="$(mktemp -d "$FIXTURE_TMPDIR/emm.XXXXXX")" || { report FAIL "mutation-proof $name" "mktemp failed"; return; }
  assert_fixture_root "$d" || { report FAIL "mutation-proof $name" "bad fixture root"; return; }
  cp -Rp "$root/." "$d/" || { report FAIL "mutation-proof $name" "copy failed"; rm -rf "$d"; return; }
  copy="$d/$rel"
  if [[ ! -f "$copy" ]]; then
    report FAIL "mutation-proof $name" "emitted file $rel missing"
  elif ! check_emitted_gate_anchors "$d"; then
    report FAIL "mutation-proof $name" "clean copy was rejected: $MISSING"
  else
    "$mut" "$copy" "$@"
    if cmp -s "$root/$rel" "$copy"; then
      report FAIL "mutation-proof $name" "the mutation changed nothing"
    elif check_emitted_gate_anchors "$d"; then
      report FAIL "mutation-proof $name" "check still passed on the mutated emit"
    else
      report PASS "mutation-proof $name" "check failed on: ${MISSING:0:110}"
    fi
  fi
  rm -rf "$d"
}

m_rm() { # m_rm <file> — remove the file
  rm -f "$1"
}

# ===========================================================================
# 1–2. Canonical and grouped checks
# ===========================================================================
PAR_REPORT_FAIL="report"
emit_cache_init

while IFS=$'\t' read -r name path fn; do
  run_check "$name" "$fn" "$path"
done < <(canonical_entries)

grouped_checks pass

# ===========================================================================
# 3. Mutation proofs (each on a copy; the originals are never touched)
# ===========================================================================
mutation_proof 'task-criteria: F7 removed from the floor' "$TASK_CRITERIA" check_task_criteria m_del_lines '- **F7** — '
mutation_proof 'task-criteria: worked-example key altered' "$TASK_CRITERIA" check_task_criteria \
  m_sub 'ac2 src/a.sh :: missing guard' 'ac2 src/a.sh :: missing check'
mutation_proof 'task-criteria: ### Issue key heading removed' "$TASK_CRITERIA" check_task_criteria m_del_lines '### Issue key'
mutation_proof 'task-criteria: drift sentence removed' "$TASK_CRITERIA" check_task_criteria m_del_lines "$DRIFT_SENTENCE"
mutation_proof 'task-criteria: F5 mapping sentence altered' "$TASK_CRITERIA" check_task_criteria \
  m_sub 'covers cites **`F5`**' 'covers cites **`F3`**'
mutation_proof 'task-criteria: uncited key form altered' "$TASK_CRITERIA" check_task_criteria \
  m_sub 'keys as `uncited <location> :: <defect>`' 'keys as `<location> :: <defect>`'
mutation_proof 'task-criteria: uncited old-shape example loses its defect text' "$TASK_CRITERIA" check_task_criteria \
  m_sub '`file:line`: <defect> — fix``' '`file:line` — fix``'
mutation_proof 'evaluator: Citations paragraph pointer removed' "$EVALUATOR" check_evaluator m_del_lines '**Citations** — '
mutation_proof 'evaluator: pinned tag literal duplicated' "$EVALUATOR" check_evaluator m_append "$TAG_PLACEHOLDER"
mutation_proof 'evaluator: citation-mode sentence altered' "$EVALUATOR" check_evaluator \
  m_sub 'uncited findings never block' 'uncited findings may block'
mutation_proof 'diagnostician: old all-three wording reintroduced' "$DIAGNOSTICIAN" check_diagnostician \
  m_append 'The diagnostician reads all three fix-cycle histories.'
mutation_proof 'fix-cycles: temp-index command half-applied' "$FIX_CYCLES_REF" check_fix_cycles \
  m_sub 'git add -A' 'git add .'
mutation_proof 'fix-cycles: Early ladder entry heading removed' "$FIX_CYCLES_REF" check_fix_cycles \
  m_del_lines '## Early ladder entry'
mutation_proof 'fix-cycles: keys ordering sentence removed' "$FIX_CYCLES_REF" check_fix_cycles \
  m_del_lines 'round trip settles'
mutation_proof 'fix-cycles: every-evaluation read paragraph removed' "$FIX_CYCLES_REF" check_fix_cycles \
  m_del_lines "$EVERY_EVAL_READ"
mutation_proof 'continuation-ladder: budget literal altered' "$LADDER_REF" check_ladder \
  m_sub '3 additional implementation attempts' '5 additional implementation attempts'
mutation_proof 'continuation-ladder: all-three wording wrapped across a line break' "$LADDER_REF" check_ladder \
  m_append $'If all\nthree evaluator verdicts flagged the item.'
mutation_proof 'ORCHESTRATION: quality-check classes reordered' "$ORCH_TEMPLATE" check_orchestration \
  m_swap '- **local-edits** — ' '- **pre-existing** — '
mutation_proof 'ORCHESTRATION: dirty-snapshot file name dropped' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'preexisting-dirty.txt' 'dirty.txt'
mutation_proof 'ORCHESTRATION: old after-cycle-3 guard wording back' "$ORCH_TEMPLATE" check_orchestration \
  m_append 'At most 3 additional implementation attempts after cycle 3.'
mutation_proof 'ORCHESTRATION: unknown model_check sentence weakened' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'always gives `model_check: unverified`' 'may give `model_check: unverified`'
mutation_proof 'ORCHESTRATION: issue-keys bullet phrase altered' "$ORCH_TEMPLATE" check_orchestration \
  m_sub "$ORCH_KEYS_PHRASE" 'appends a keys line'
mutation_proof 'ORCHESTRATION: issue-keys bullet phrase duplicated' "$ORCH_TEMPLATE" check_orchestration \
  m_append "$ORCH_KEYS_PHRASE"
mutation_proof 'feature skill: over the byte budget' "$FEATURE_SKILL" check_feature_skill m_pad 400
mutation_proof 'feature skill: Quality Checks pointer removed' "$FEATURE_SKILL" check_feature_skill \
  m_sub 'classify per ORCHESTRATION.md § Quality Checks' 'classify the failure'
mutation_proof 'ship-pr: backlog heading removed' "$SHIP_PR" check_ship_pr m_del_lines '## Backlog (not fixed here)'
mutation_proof 'ship-pr: body template loses the multi-goal prefix' "$SHIP_PR" check_ship_pr \
  m_sub 'write each bullet as `- <goal>/B<n> (<source>): <finding>`. ' ''
mutation_proof 'test-ladder: class order swapped on the pointer line' "$TEST_LADDER" check_test_ladder \
  m_sub '(flaky, local-edits, pre-existing, introduced)' '(flaky, pre-existing, local-edits, introduced)'
mutation_proof 'harness-matrix: superseded note removed' "$HARNESS_MATRIX" check_harness_matrix \
  m_sub ' — superseded by the 2026-10-27 addendum (Cursor hook behavior)' ''
mutation_proof 'harness-matrix: kit_guard interaction lines removed' "$HARNESS_MATRIX" check_harness_matrix \
  m_del_lines 'kit_guard'
mutation_proof 'evaluation-system doc: citation sentence altered' "$EVALSYS_DOC" check_eval_system_doc \
  m_sub 'uncited findings never block' 'uncited findings may block'
mutation_proof 'evaluation-system doc: floor, citations and keys heading removed' "$EVALSYS_DOC" check_eval_system_doc \
  m_del_lines '## Floor, citations, and issue keys'
# The heading proof above breaks every section-scoped anchor at once; these two alter one phrase each.
mutation_proof 'evaluation-system doc: F7 bypass-class phrase altered' "$EVALSYS_DOC" check_eval_system_doc \
  m_sub "$EVALSYS_F7_PHRASE" '(including **F6** for bypass-class problems'
mutation_proof 'evaluation-system doc: Citations scope phrase altered' "$EVALSYS_DOC" check_eval_system_doc \
  m_sub "$EVALSYS_CITATIONS_PHRASE" '§ **Citations** applies to every evaluator mode'
mutation_proof 'feature-workflow doc: orchestration-log keys sentence altered' "$FEATURE_WORKFLOW_DOC" check_feature_workflow \
  m_sub "$WORKFLOW_KEYS_PHRASE" 'appends a keys line'
mutation_proof 'feature-workflow doc: orchestration-log keys sentence duplicated' "$FEATURE_WORKFLOW_DOC" check_feature_workflow \
  m_append "$WORKFLOW_KEYS_PHRASE"
mutation_proof 'feature-workflow doc: terminology sentence removed' "$FEATURE_WORKFLOW_DOC" check_feature_workflow \
  m_del_lines "$TERMINOLOGY_SENTENCE"
mutation_proof 'feature-workflow doc: ladder diagram edge removed' "$FEATURE_WORKFLOW_DOC" check_feature_workflow \
  m_del_lines 'Eval2 --> LadderEntry: repeated structural key · ladder auto'
mutation_proof 'architecture doc: ladder diagram edge removed' "$ARCHITECTURE_DOC" check_architecture_doc \
  m_del_lines 'FixCycle --> LadderAuto: repeated structural key · early entry'
mutation_proof 'Codex pointer: old after-three-cycles wording restored' "$EMIT_BIN" check_emit_pointer \
  m_sub "When fix cycles are exhausted $EARLY_WORDING" 'After three fix cycles'
mutation_proof 'agents-and-models doc: loop-range wording restored' "$AGENTS_MODELS_DOC" check_agents_models_doc \
  m_append 'The arbiter reads fix cycles 1–3.'
mutation_proof 'goal template: early-entry note dropped from the ladder line' "$GOAL_TEMPLATE" check_goal_template \
  m_sub '; auto may enter it early (reference/fix-cycles.md § Early ladder entry)' ''

# Consumer-trace rules (goal consumer-trace, task 06): each proof removes or alters one anchor.
mutation_proof 'goal template: ## Searches heading renamed' "$GOAL_TEMPLATE" check_goal_template \
  m_sub '## Searches' '## Search list'
mutation_proof 'goal template: ## Consumers heading renamed' "$GOAL_TEMPLATE" check_goal_template \
  m_sub '## Consumers' '## Consumer list'
mutation_proof 'goal template: consumers table header removed' "$GOAL_TEMPLATE" check_goal_template \
  m_del_lines '| Surface | Consumer | Class | Evidence |'
mutation_proof 'goal template: trace phases key narrowed to planner' "$GOAL_TEMPLATE" check_goal_template \
  m_sub 'trace: planner|blind' 'trace: planner'
mutation_proof 'goal template: trace key default wording dropped' "$GOAL_TEMPLATE" check_goal_template \
  m_sub 'planner (default): the planner-written trace only' 'planner: the planner-written trace only'

mutation_proof 'goal-criteria: Consumer trace gate heading replaced' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '**Consumer trace (Phase 3 gate).**' '**Reference sweep (Phase 3 gate).**'
mutation_proof 'goal-criteria: Searches to re-run section name dropped' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '### Searches to re-run' '### Re-run list'
mutation_proof 'goal-criteria: lint tool pointer dropped' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '_kit/trace-lint.sh' '_kit/lint.sh'
mutation_proof 'goal-criteria: retired sweep artifact reintroduced' "$GOAL_CRITERIA" check_goal_criteria \
  m_append 'A reference-sweep.md artifact lists every hit.'
mutation_proof 'goal-criteria: transition-rule pointer removed' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub 'follows the transition rule in the feature skill' 'follows the usual rule'
# Single-anchor proofs: each alters one label or sentence, so only its own section check can fail.
mutation_proof 'goal-criteria: Who clause label renamed' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '**Who.**' '**Whom.**'
mutation_proof 'goal-criteria: Format clause label renamed' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '**Format.**' '**Layout.**'
mutation_proof 'goal-criteria: gate lead repeats the verdict again' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub 'checked on five points. Points 2 and 3 are mechanical, enforced by the pre-flight lint; points 1, 4 and 5 state their own verdict.' 'checked on five points; each violation is NEEDS REVISION.'
mutation_proof 'goal-criteria: corrective-task clause numbered after the new list' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub "$CORRECTIVE_CHECKS" 'satisfies checks 3–4'
mutation_proof 'goal-criteria: Lint clause removed' "$GOAL_CRITERIA" check_goal_criteria \
  m_del_lines '3. **Lint.**'
mutation_proof 'goal-criteria: Re-runs clause made optional' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '**Re-runs (mandatory).**' '**Re-runs (optional).**'
mutation_proof 'goal-criteria: provisional-verdict rule dropped' "$GOAL_CRITERIA" check_goal_criteria \
  m_sub '**provisional**' 'final'
mutation_proof 'goal-criteria: Trace choice clause removed' "$GOAL_CRITERIA" check_goal_criteria \
  m_del_lines '5. **Trace choice.**'

mutation_proof 'preflight: check 2 lint run removed' "$PREFLIGHT_REF" check_preflight \
  m_sub '_kit/trace-lint.sh' '_kit/lint.sh'
mutation_proof 'preflight: check 2 failure rule altered' "$PREFLIGHT_REF" check_preflight \
  m_sub '`trace-lint` exits non-zero' '`trace-lint` prints a warning'
mutation_proof 'preflight: second reference-sweep mention added' "$PREFLIGHT_REF" check_preflight \
  m_append 'Pre-flight writes reference-sweep.md for every goal.'
mutation_proof 'preflight: transition sentence removed' "$PREFLIGHT_REF" check_preflight \
  m_del_lines '**Transition:**'
mutation_proof 'preflight: check 2 Searches and Consumers sentence altered' "$PREFLIGHT_REF" check_preflight \
  m_sub "$PREFLIGHT_SEARCHES" '`goal.md` carries a trace'

mutation_proof 'goal-revisions: renumbering step 5 removed' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_del_lines 'names a task that still exists after the renumbering'
mutation_proof 'goal-revisions: step 5 reverted to the old sweep wording' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_sub 'Confirm every `changes` row in `goal.md` `## Consumers` names a task' 'Confirm renamed symbols from `reference-sweep.md` match across tasks'
mutation_proof 'goal-revisions: unlisted-surface amendment sentence removed' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_del_lines 'A surface the Phase 5 audit finds changed but not listed'
mutation_proof 'goal-revisions: amendment no longer re-runs the lint' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_sub 're-run `_kit/trace-lint.sh`, then a targeted evaluation' 'then a targeted evaluation'
mutation_proof 'goal-revisions: additive sentence altered' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_sub 'It is additive; when a missed consumer needs an edit' 'It is material; when a missed consumer needs an edit'
mutation_proof 'goal-revisions: retired reference-sweep artifact reintroduced' "$GOAL_REVISIONS_REF" check_goal_revisions \
  m_append 'Renumbering re-runs the reference-sweep.md artifact.'

mutation_proof 'ORCHESTRATION: consumer-trace mode named differently' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'consumer-trace mode' 'blind mode'
mutation_proof 'ORCHESTRATION: Searches to re-run section renamed' "$ORCH_TEMPLATE" check_orchestration \
  m_sub '### Searches to re-run' '### Re-runs'
mutation_proof 'ORCHESTRATION: Phase 5 unlisted-surface finding no longer cites F6' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'citing `F6`' 'citing `F3`'
mutation_proof 'ORCHESTRATION: base-commit file name dropped' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'base-commit.txt' 'base.txt'
mutation_proof 'ORCHESTRATION: untracked-path listing dropped from the changed paths' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'git ls-files --others --exclude-standard' 'git ls-files --modified'
mutation_proof 'ORCHESTRATION: retired reference-sweep artifact reintroduced' "$ORCH_TEMPLATE" check_orchestration \
  m_append 'Pre-flight records reference-sweep.md.'
mutation_proof 'ORCHESTRATION: Phase 5 legacy-goal skip sentence altered' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'skips checks (a) and (b)' 'runs checks (a) and (b)'
mutation_proof 'ORCHESTRATION: legacy-goal skip loses its no-Consumers-section qualifier' "$ORCH_TEMPLATE" check_orchestration \
  m_sub '(no `## Consumers` section) skips' 'skips'
mutation_proof 'ORCHESTRATION: legacy-goal skip loses its legacy-artifact clause' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'the audit checks its legacy artifact' 'the audit ignores its legacy artifact'
mutation_proof 'ORCHESTRATION: blind-trace diff sentence loses its subject' "$ORCH_TEMPLATE" check_orchestration \
  m_sub "The orchestrator diffs that trace's Consumer paths against" "It diffs that trace's Consumer paths against"
mutation_proof 'ORCHESTRATION: pre-flight fix wording generalized' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'The orchestrator fixes pre-flight failures and logs them' 'The orchestrator fixes failures and logs them'
mutation_proof 'ORCHESTRATION: Consumer trace pointer names a heading again' "$ORCH_TEMPLATE" check_orchestration \
  m_sub 'item 1 of the goal-criteria' 'goal-criteria § Consumer trace item 1 of the goal-criteria'

mutation_proof 'evaluator: consumer-trace mode heading removed' "$EVALUATOR" check_evaluator \
  m_del_lines '## Consumer-trace mode'
mutation_proof 'evaluator: blind trace output header altered' "$EVALUATOR" check_evaluator \
  m_sub '## Consumer trace (blind)' '## Consumer trace'
mutation_proof 'evaluator: consumer-trace exception dropped from the arbitration line' "$EVALUATOR" check_evaluator \
  m_sub 'Arbitration mode and consumer-trace mode excepted' 'Arbitration mode excepted'
mutation_proof 'evaluator: third consumer-trace exception added' "$EVALUATOR" check_evaluator \
  m_append 'Phase 4 output and consumer-trace mode excepted.'
mutation_proof 'evaluator: Searches to re-run section dropped' "$EVALUATOR" check_evaluator \
  m_sub '`### Searches to re-run` section' '`### Re-runs` section'
mutation_proof 'evaluator: Phase 5 F6 audit citation altered' "$EVALUATOR" check_evaluator \
  m_sub 'citing **`F6`** against' 'citing **`F3`** against'
mutation_proof 'evaluator: Phase 5 consumer check removed from the final audit' "$EVALUATOR" check_evaluator \
  m_sub 'run the Phase 5 consumer check' 'run the Phase 5 check'
mutation_proof 'evaluator: Phase 5 legacy-goal skip sentence altered' "$EVALUATOR" check_evaluator \
  m_sub 'skips checks (a) and (b)' 'runs checks (a) and (b)'
mutation_proof 'evaluator: legacy-goal skip loses its no-Consumers-section qualifier' "$EVALUATOR" check_evaluator \
  m_sub '(no `## Consumers` section) skips' 'skips'
mutation_proof 'evaluator: legacy-goal skip loses its legacy-artifact clause' "$EVALUATOR" check_evaluator \
  m_sub 'check its legacy artifact' 'ignore its legacy artifact'
mutation_proof 'evaluator: arbitration evidence clause merged back with consumer-trace mode' "$EVALUATOR" check_evaluator \
  m_sub 'Arbitration reviews criteria, not code, so its evidence is' 'No code is under review, so arbiter evidence is'
mutation_proof 'evaluator: consumer-trace evidence clause dropped' "$EVALUATOR" check_evaluator \
  m_sub 'consumer-trace mode scores no work' 'consumer-trace mode scores the work'
mutation_proof 'evaluator: search-tool rendering sentence altered' "$EVALUATOR" check_evaluator \
  m_sub 'A search-tool call prints no' 'A search-tool call prints'
mutation_proof 'evaluator: hit format dropped from consumer-trace mode' "$EVALUATOR" check_evaluator \
  m_sub 'then one `<path>:<line>:<text>` hit' 'then one hit'
mutation_proof 'evaluator: Consumer trace pointer names a heading again' "$EVALUATOR" check_evaluator \
  m_sub 'item 4 of the **Consumer trace (Phase 3 gate)**' '§ Consumer trace'

mutation_proof 'emit.sh: trace-lint dropped from the single-copy tools loop' "$EMIT_BIN" check_emit_pointer \
  m_sub 'for f in log-spawn.sh memory.sh trace-lint.sh' 'for f in log-spawn.sh memory.sh'
mutation_proof 'emit.sh: trace-lint Windows launcher entry dropped' "$EMIT_BIN" check_emit_pointer \
  m_sub '"_kit/trace-lint.cmd"' '"_kit/launcher.cmd"'

# Grouped checks: each mutates a copy of a real template or doc; the clean copy passes, the
# mutated one fails.
mutation_proof_copy 'vocabulary: a stale word inserted into a copied agent template' "$EVALUATOR" check_vocabulary \
  m_append "The LLM $(stale_stem)e reviews the work."
mutation_proof_copy 'frontmatter: colon-space in a copied agent template description' "$EVALUATOR" check_frontmatter_descriptions \
  m_sub 'description: ' 'description: Reviews work: '
mutation_proof_copy 'naming: a sibling-project name inserted into a copied doc' "$DECISION_DOC" check_sibling_names \
  m_append "A sentence naming the $(sibling_name) project."

# Behavioral mutations on copies of the canonical tool.
keys_mutant() { # keys_mutant <name> <from> <to> — a mutated log-spawn.sh must fail the behavior check
  local name="$1" from="$2" to="$3" d bin
  d="$(mktemp -d "$FIXTURE_TMPDIR/lsmut.XXXXXX")" || { report FAIL "mutation-proof $name" "mktemp failed"; return; }
  bin="$d/log-spawn.sh"
  cp "$LOG_SPAWN_CANON" "$bin"
  m_sub "$bin" "$from" "$to"
  if cmp -s "$LOG_SPAWN_CANON" "$bin"; then
    report FAIL "mutation-proof $name" "the mutation changed nothing"
  elif ! bash -n "$bin" 2>/dev/null; then
    report FAIL "mutation-proof $name" "the mutant does not parse"
  elif check_keys_behavior "$bin"; then
    report FAIL "mutation-proof $name" "behavior check still passed on the mutant"
  else
    report PASS "mutation-proof $name" "check failed on: ${MISSING:0:110}"
  fi
  rm -rf "$d"
}
keys_mutant 'log-spawn keys: REPEAT detection disabled' \
  '*"$NL$item_key$NL"*) repeat_lines=' '*"$NL$item_key$NL-never"*) repeat_lines='
keys_mutant 'log-spawn keys: duplicate-KEYS refusal removed' \
  'die 3 "KEYS [#$nn] already present in $log"' ':'
keys_mutant 'log-spawn keys: missing-SPAWN refusal removed' \
  'die 3 "SPAWN [#$nn] not found in $log"' ':'
keys_mutant 'log-spawn keys: uncited old-shape key form dropped' \
  'cit="uncited"; rest="$head"' 'cit="cited"; rest="$head"'

# The originals are untouched: the base run still passes after every mutation.
base_ok=1
while IFS=$'\t' read -r name path fn; do
  "$fn" "$path" || { base_ok=0; echo "base run: $name failed: $MISSING" >&2; }
done < <(canonical_entries)
grouped_checks quiet || base_ok=0
if [[ $base_ok -eq 1 ]]; then
  report PASS 'base fixtures still pass after all mutations'
else
  report FAIL 'base fixtures still pass after all mutations' 'a canonical check failed on the untouched files'
fi

# ===========================================================================
# 4. Fresh emit: the emitted copies carry the floor and citation anchors
# ===========================================================================
if [[ "$HAVE_JQ" -ne 1 ]]; then
  report SKIP 'fresh emit: floor and citation anchors in emitted claude+cursor copies' 'jq not on PATH'
else
  alloc_path ansfile
  answers_for_emit "$EMIT_ALLOC_PATH"
  ans="$EMIT_ALLOC_PATH"
  alloc_root
  root="$EMIT_ALLOC_PATH"
  if emit_cache_copy "$root" "$ans" && check_emitted_gate_anchors "$root"; then
    report PASS 'fresh emit: floor and citation anchors in emitted claude+cursor copies'
    # Mutations on copies of the fresh emit: the emitted goal template and the emitted lint tool.
    emit_mutant 'fresh emit: goal template ## Consumers heading renamed' "$root" \
      .claude/skills/feature/templates/goal.md m_sub '## Consumers' '## Consumer list'
    emit_mutant 'fresh emit: cursor goal template ## Searches heading renamed' "$root" \
      .cursor/skills/feature/templates/goal.md m_sub '## Searches' '## Search list'
    emit_mutant 'fresh emit: _kit/trace-lint.sh removed from the emit' "$root" \
      _kit/trace-lint.sh m_rm
    emit_mutant 'fresh emit: _kit/trace-lint.cmd launcher removed from the emit' "$root" \
      _kit/trace-lint.cmd m_rm
  else
    report FAIL 'fresh emit: floor and citation anchors in emitted claude+cursor copies' "$MISSING"
  fi
fi

emit_cache_verify

echo
echo "=== gate-hardening summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
