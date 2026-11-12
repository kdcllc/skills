#!/usr/bin/env bash
# Fixture-based tests for skills/agent-composer scripts (validate.sh, manifest.sh).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures"
SKILL_DIR="${AGENT_COMPOSER_SKILL_DIR:-$REPO/skills/agent-composer}"
VALIDATE="bash $SKILL_DIR/scripts/validate.sh"
MANIFEST="bash $SKILL_DIR/scripts/manifest.sh"
SCHEMA="$SKILL_DIR/references/spec-schema.md"

PASS=0
FAIL=0
SKIP=0
declare -A CODES_HIT=()
SCRATCH_DIRS=()
SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/agent-composer.XXXXXX")"
SCRATCH_DIRS+=("$SCRATCH_ROOT")

cleanup() {
  local d
  for d in "${SCRATCH_DIRS[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

marker_template_from_schema() {
  awk '/^### Generated-by marker/,0 {
    if ($0 ~ /^```text$/) { getline; print; exit }
  }' "$SCHEMA"
}

marker_line() {
  local crew="$1" t
  t="$(marker_template_from_schema)"
  if [[ -z "$t" ]] || [[ "$t" != *"—"* ]]; then
    return 1
  fi
  printf '%s' "${t//<name>/$crew}"
}

have_pyyaml() {
  python3 -c "import yaml" >/dev/null 2>&1
}

record_codes() {
  local out="$1"
  local line code
  while IFS= read -r line; do
    if [[ "$line" =~ ^(error|warn):\ (S[0-9]{3}|T[0-9]{3})\  ]]; then
      code="${BASH_REMATCH[2]}"
      CODES_HIT["$code"]=1
    fi
  done <<<"$out"
}

assert_no_crash() {
  local out="$1"
  if grep -qE '^error: internal:' <<<"$out" || grep -q Traceback <<<"$out"; then
    return 1
  fi
  return 0
}

assert_summary_last() {
  local out="$1"
  local last
  last="$(awk 'NF { line=$0 } END { print line }' <<<"$out")"
  [[ "$last" =~ ^validate:\ [0-9]+\ error\(s\),\ [0-9]+\ warning\(s\)$ ]]
}

case_pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
case_fail() { FAIL=$((FAIL + 1)); echo "FAIL $1: $2" >&2; }
case_skip() { SKIP=$((SKIP + 1)); echo "SKIP $1: $2"; }

need_yaml_or_skip() {
  local name="$1"
  if ! have_pyyaml; then
    case_skip "$name" "PyYAML not installed"
    return 1
  fi
  return 0
}

mktemp_project() {
  local d
  d="$(mktemp -d "$SCRATCH_ROOT/p.XXXXXX")"
  printf '%s' "$d"
}

install_spec() {
  local project="$1"
  local spec_src="$2"
  local dest_name="${3:-$(basename "$spec_src")}"
  mkdir -p "$project/.agent-composer"
  cp "$spec_src" "$project/.agent-composer/$dest_name"
  printf '%s' "$project/.agent-composer/$dest_name"
}

materialize_tree() {
  local tree_dir="$1"
  local project="$2"
  local f rel dest
  while IFS= read -r -d '' f; do
    rel="${f#"$tree_dir"/}"
    rel="${rel%.fixture}"
    case "$rel" in
      claude/*) rel=".${rel}" ;;
      cursor/*) rel=".${rel}" ;;
    esac
    dest="$project/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
  done < <(find "$tree_dir" -name '*.fixture' -print0 2>/dev/null || true)
}

run_validate_spec() {
  local name="$1"
  local spec_path="$2"
  local want_rc="$3"
  local want_code="${4:-}"
  need_yaml_or_skip "$name" || return 0
  local out rc
  out="$($VALIDATE spec "$spec_path" 2>&1)" || rc=$?
  rc="${rc:-0}"
  record_codes "$out"
  if ! assert_no_crash "$out"; then
    case_fail "$name" "internal error or Traceback in output"
    return 0
  fi
  if ! assert_summary_last "$out"; then
    case_fail "$name" "missing validate summary line"
    return 0
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $rc want $want_rc"
    return 0
  fi
  if [[ -n "$want_code" ]] && ! grep -qE "(error|warn): ${want_code} " <<<"$out"; then
    case_fail "$name" "expected code $want_code"
    return 0
  fi
  case_pass "$name"
}

run_validate_spec_expect_s040() {
  local name="$1"
  local spec_path="$2"
  local want_rc="${3:-0}"
  need_yaml_or_skip "$name" || return 0
  local out rc
  out="$($VALIDATE spec "$spec_path" 2>&1)" || rc=$?
  rc="${rc:-0}"
  record_codes "$out"
  if ! assert_no_crash "$out"; then
    case_fail "$name" "internal error or Traceback in output"
    return 0
  fi
  if ! assert_summary_last "$out"; then
    case_fail "$name" "missing validate summary line"
    return 0
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $rc want $want_rc"
    return 0
  fi
  if ! grep -qE '^warn: S040 ' <<<"$out"; then
    case_fail "$name" "expected warn: S040 line"
    return 0
  fi
  case_pass "$name"
}

run_validate_spec_no_s040() {
  local name="$1"
  local spec_path="$2"
  local want_rc="${3:-0}"
  need_yaml_or_skip "$name" || return 0
  local out rc
  out="$($VALIDATE spec "$spec_path" 2>&1)" || rc=$?
  rc="${rc:-0}"
  record_codes "$out"
  if ! assert_no_crash "$out"; then
    case_fail "$name" "internal error or Traceback"
    return 0
  fi
  if ! assert_summary_last "$out"; then
    case_fail "$name" "missing validate summary"
    return 0
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $rc want $want_rc"
    return 0
  fi
  if grep -qE '^warn: S040 ' <<<"$out"; then
    case_fail "$name" "unexpected S040 warning"
    return 0
  fi
  case_pass "$name"
}

run_validate_tree() {
  local name="$1"
  local project="$2"
  local spec_rel="$3"
  local want_rc="$4"
  local want_code="${5:-}"
  need_yaml_or_skip "$name" || return 0
  local out rc
  out="$($VALIDATE tree "$project" "$project/$spec_rel" 2>&1)" || rc=$?
  rc="${rc:-0}"
  record_codes "$out"
  if ! assert_no_crash "$out"; then
    case_fail "$name" "internal error or Traceback"
    return 0
  fi
  if [[ "$want_rc" -eq 2 ]]; then
    if grep -q Traceback <<<"$out"; then
      case_fail "$name" "Traceback on exit 2 path"
      return 0
    fi
  else
    if ! assert_summary_last "$out"; then
      case_fail "$name" "missing validate summary"
      return 0
    fi
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $rc want $want_rc"
    return 0
  fi
  if [[ -n "$want_code" ]] && ! grep -qE "(error|warn): ${want_code} " <<<"$out"; then
    case_fail "$name" "expected $want_code"
    return 0
  fi
  case_pass "$name"
}

run_manifest() {
  local name="$1"
  local sub="$2"
  local project="$3"
  local spec_rel="$4"
  local want_rc="$5"
  local want_substr="${6:-}"
  need_yaml_or_skip "$name" || return 0
  local out rc
  out="$($MANIFEST "$sub" "$project" "$project/$spec_rel" 2>&1)" || rc=$?
  rc="${rc:-0}"
  if ! assert_no_crash "$out"; then
    case_fail "$name" "internal error or Traceback"
    return 0
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $rc want $want_rc"
    return 0
  fi
  if [[ -n "$want_substr" ]] && ! grep -qF "$want_substr" <<<"$out"; then
    case_fail "$name" "missing expected substring"
    return 0
  fi
  case_pass "$name"
}

# --- Positive spec cases ---
run_positive_specs() {
  local ex spec
  for ex in coding-crew content-crew triage-crew; do
    run_validate_spec_expect_s040 "spec/positive-example-$ex" \
      "$SKILL_DIR/assets/examples/$ex.crew.yaml" 0
  done
  run_validate_spec "spec/positive-research-write-check" \
    "$FIXTURES/specs/research-write-check.crew.yaml" 0
  run_validate_spec "spec/positive-pipeline" \
    "$FIXTURES/specs/positive-pipeline.crew.yaml" 0
  run_validate_spec "spec/positive-fan-out" \
    "$FIXTURES/specs/fanout-mini.crew.yaml" 0
  run_validate_spec "spec/positive-step-reuses-agent-id" \
    "$FIXTURES/specs/step-id-reuse.crew.yaml" 0
}

# --- Example content cases (bash, grep and awk only; never skipped) ---
# Prints the agent entry <id>: the lines from "  - id: <id>" up to, not
# including, the next "  - id: " line or the line "steps:".
example_agent_entry() {
  local file="$1"
  local id="$2"
  awk -v start="  - id: $id" '
    $0 == start { on = 1; print; next }
    on && (index($0, "  - id: ") == 1 || $0 == "steps:") { on = 0 }
    on { print }
  ' "$file"
}

run_example_content_cases() {
  local name="example/coding-crew-no-shared-output"
  local file="$SKILL_DIR/assets/examples/coding-crew.crew.yaml"
  local impl rev
  local failed=()
  if [[ ! -f "$file" ]]; then
    case_fail "$name" "precondition: example file not found: $file"
    return 0
  fi
  impl="$(example_agent_entry "$file" implementer)"
  if [[ -z "$impl" ]]; then
    case_fail "$name" "precondition: no implementer agent entry in $file"
    return 0
  fi
  rev="$(example_agent_entry "$file" reviewer)"
  if [[ -z "$rev" ]]; then
    case_fail "$name" "precondition: no reviewer agent entry in $file"
    return 0
  fi
  if grep -qF 'implementation-summary' "$file"; then
    failed+=("(a) the file has a line with the text implementation-summary")
  fi
  if grep -qE '^[[:space:]]*outputs:' <<<"$impl"; then
    failed+=("(b) the implementer entry has an outputs: line")
  fi
  if ! grep -qE '^[[:space:]]*inputs: \[tasks\.yaml, task-brief\.md\][[:space:]]*$' <<<"$rev"; then
    failed+=("(c) the reviewer entry has no line 'inputs: [tasks.yaml, task-brief.md]'")
  fi
  if ((${#failed[@]} > 0)); then
    local msg
    msg="$(printf '%s; ' "${failed[@]}")"
    case_fail "$name" "${msg%; }"
    return 0
  fi
  case_pass "$name"
}

# --- Negative spec cases (one per S### except S034) ---
run_negative_specs() {
  local p="$FIXTURES/specs"
  run_validate_spec "spec/S001-invalid-yaml" "$p/S001-invalid-yaml.crew.yaml" 1 S001
  run_validate_spec "spec/S002-unknown-top" "$p/S002-unknown-top.crew.yaml" 1 S002
  run_validate_spec "spec/S003-unknown-agent-key" "$p/S003-unknown-agent-key.crew.yaml" 1 S003
  run_validate_spec "spec/S004-unknown-step-key" "$p/S004-unknown-step-key.crew.yaml" 1 S004
  run_validate_spec "spec/S005-missing-instructions" "$p/S005-missing-instructions.crew.yaml" 1 S005
  run_validate_spec "spec/S005-gate-missing-max" "$p/S005-gate-missing-max.crew.yaml" 1 S005
  run_validate_spec "spec/S006-bad-schema" "$p/S006-bad-schema.crew.yaml" 1 S006
  run_validate_spec "spec/S007-bad-name" "$p/S007-bad-name.crew.yaml" 1 S007
  run_validate_spec "spec/S008-dup-agent" "$p/S008-dup-agent.crew.yaml" 1 S008
  run_validate_spec "spec/S009-unknown-agent" "$p/S009-unknown-agent.crew.yaml" 1 S009
  run_validate_spec "spec/S010-unknown-step-need" "$p/S010-unknown-step-need.crew.yaml" 1 S010
  run_validate_spec "spec/S011-needs-cycle" "$p/S011-needs-cycle.crew.yaml" 1 S011
  run_validate_spec "spec/S012-eval-no-gate" "$p/S012-eval-no-gate.crew.yaml" 1 S012
  run_validate_spec "spec/S013-gate-non-eval" "$p/S013-gate-non-eval.crew.yaml" 1 S013
  run_validate_spec "spec/S014-router-no-routes" "$p/S014-router-no-routes.crew.yaml" 1 S014
  run_validate_spec "spec/S015-routes-non-router" "$p/S015-routes-non-router.crew.yaml" 1 S015
  run_validate_spec "spec/S016-planner-no-dispatch" "$p/S016-planner-no-dispatch.crew.yaml" 1 S016
  run_validate_spec "spec/S017-dispatch-non-planner" "$p/S017-dispatch-non-planner.crew.yaml" 1 S017
  run_validate_spec "spec/S018-max-cycles" "$p/S018-max-cycles.crew.yaml" 1 S018
  run_validate_spec "spec/S019-max-tasks" "$p/S019-max-tasks.crew.yaml" 1 S019
  run_validate_spec "spec/S020-on-fail-not-upstream" "$p/S020-on-fail-not-upstream.crew.yaml" 1 S020
  run_validate_spec "spec/S021-route-target-needs" "$p/S021-route-target-needs.crew.yaml" 1 S021
  run_validate_spec "spec/S022-pipeline-parallel" "$p/S022-pipeline-parallel.crew.yaml" 1 S022
  run_validate_spec "spec/S022-pipeline-two-roots" "$p/s022-pipeline-two-roots.crew.yaml" 1 S022
  run_validate_spec "spec/S022-pipeline-routes" "$p/s022-pipeline-routes.crew.yaml" 1 S022
  run_validate_spec "spec/S022-router-not-one-routes" "$p/s022-router-two-routes.crew.yaml" 1 S022
  run_validate_spec "spec/S022-fan-out-no-parallel" "$p/s022-fan-out-no-parallel.crew.yaml" 1 S022
  run_validate_spec "spec/S022-fan-out-no-need-parallel" "$p/s022-fan-out-no-need.crew.yaml" 1 S022
  run_validate_spec "spec/S022-evaluator-no-gate" "$p/s022-evaluator-no-gate.crew.yaml" 1 S022
  run_validate_spec "spec/S022-orchestrator-not-one-dispatch" "$p/s022-orchestrator-no-dispatch.crew.yaml" 1 S022
  run_validate_spec "spec/S023-unused-agent" "$p/S023-unused-agent.crew.yaml" 1 S023
  run_validate_spec "spec/S024-eval-edit" "$p/S024-eval-edit.crew.yaml" 1 S024
  run_validate_spec "spec/S025-eval-shell" "$p/s025.crew.yaml" 0 S025
  run_validate_spec "spec/S026-spawn-tool" "$p/S026-spawn-tool.crew.yaml" 1 S026
  run_validate_spec "spec/S027-missing-models" "$p/S027-missing-models.crew.yaml" 1 S027
  run_validate_spec "spec/S028-seven-agents" "$p/s028.crew.yaml" 0 S028
  local proj spec
  proj="$(mktemp_project)"
  spec="$(install_spec "$proj" "$p/S029-name-mismatch.crew.yaml" "foo.crew.yaml")"
  run_validate_spec "spec/S029-name-mismatch" "$spec" 1 S029
  run_validate_spec "spec/S030-agent-and-parallel" "$p/S030-agent-and-parallel.crew.yaml" 1 S030
  run_validate_spec "spec/S031-parallel-one" "$p/S031-parallel-one.crew.yaml" 1 S031
  run_validate_spec "spec/S032-no-agents" "$p/S032-no-agents.crew.yaml" 1 S032
  run_validate_spec "spec/S033-dup-harness" "$p/S033-dup-harness.crew.yaml" 1 S033
  run_validate_spec "spec/S035-unknown-gate-key" "$p/S035-unknown-gate-key.crew.yaml" 1 S035
  run_validate_spec "spec/S036-unknown-dispatch-key" "$p/S036-unknown-dispatch-key.crew.yaml" 1 S036
  run_validate_spec "spec/S037-unknown-models-key" "$p/S037-unknown-models-key.crew.yaml" 1 S037
  run_validate_spec "spec/S038-non-worker-parallel" "$p/S038-non-worker-parallel.crew.yaml" 1 S038
  run_validate_spec "spec/S039-outputs-no-edit" "$p/S039-outputs-no-edit.crew.yaml" 1 S039
  run_validate_spec "spec/S039-planner-no-edit" "$p/S039-planner-no-edit.crew.yaml" 1 S039
  run_validate_spec "spec/S040-placeholder-models" "$p/s040.crew.yaml" 0 S040
}

run_s040_and_spec_changed_cases() {
  run_validate_spec_no_s040 "spec/positive-fake-models-no-s040" \
    "$FIXTURES/specs/positive-fake-models.crew.yaml" 0

  local proj spec out rc
  if ! have_pyyaml; then
    case_skip "manifest/spec-changed-write" "PyYAML not installed"
    case_skip "manifest/spec-changed-clean-status" "PyYAML not installed"
    case_skip "manifest/spec-changed-after-edit" "PyYAML not installed"
    return 0
  fi
  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/spec-changed-write" write "$proj" "$spec" 0
  out="$($MANIFEST status "$proj" "$proj/$spec" 2>&1)" || rc=$?
  rc="${rc:-0}"
  if [[ "$rc" -ne 0 ]] || grep -qF 'spec-changed' <<<"$out"; then
    case_fail "manifest/spec-changed-clean-status" "rc=$rc or unexpected spec-changed"
    return 0
  fi
  case_pass "manifest/spec-changed-clean-status"
  sed -i 's/^description: .*$/description: "Edited for spec-changed test."/' "$proj/$spec"
  out="$($MANIFEST status "$proj" "$proj/$spec" 2>&1)" || rc=$?
  rc="${rc:-0}"
  if [[ "$rc" -ne 1 ]] || [[ "$(sed -n '1p' <<<"$out")" != "spec-changed .agent-composer/mini.crew.yaml" ]]; then
    case_fail "manifest/spec-changed-after-edit" "rc=$rc first=$(sed -n '1p' <<<"$out")"
    return 0
  fi
  case_pass "manifest/spec-changed-after-edit"
}

tree_project_mini() {
  local proj spec
  proj="$(mktemp_project)"
  spec="$(install_spec "$proj" "$FIXTURES/specs/mini.crew.yaml")"
  materialize_tree "$FIXTURES/trees/base-mini" "$proj"
  printf '%s\n.agent-composer/mini.crew.yaml' "$proj"
}

tree_project_fanout() {
  local proj spec
  proj="$(mktemp_project)"
  spec="$(install_spec "$proj" "$FIXTURES/specs/fanout-mini.crew.yaml")"
  materialize_tree "$FIXTURES/trees/fanout-mini" "$proj"
  printf '%s\n.agent-composer/fanout-mini.crew.yaml' "$proj"
}

run_tree_cases() {
  local proj spec mk
  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_validate_tree "tree/valid-pipeline-mini" "$proj" "$spec" 0

  read -r proj spec <<<"$(tree_project_fanout | tr '\n' ' ')"
  run_validate_tree "tree/valid-fan-out-cursor-rule" "$proj" "$spec" 0

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  rm "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T001-missing-file" "$proj" "$spec" 1 T001

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  printf '\xff\xfe' > "$proj/.cursor/agents/w.md"
  run_validate_tree "tree/T002-non-utf8" "$proj" "$spec" 1 T002

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i 's/^name: w$/name: wrong/' "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T003-name-mismatch" "$proj" "$spec" 1 T003

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i '/^model: inherit$/d' "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T004-claude-missing-model" "$proj" "$spec" 1 T004

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i 's/^model: inherit$/model: "inherit"/' "$proj/.cursor/agents/w.md"
  run_validate_tree "tree/T005-quoted-cursor-model" "$proj" "$spec" 1 T005

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i '/^readonly: true$/a tools: Read' "$proj/.cursor/agents/w.md"
  run_validate_tree "tree/T006-cursor-tools-line" "$proj" "$spec" 1 T006

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i 's/^model: inherit$/model: fake-frontier-model/' "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T007-model-mismatch" "$proj" "$spec" 1 T007

  proj="$(mktemp_project)"
  install_spec "$proj" "$FIXTURES/specs/eval-mini.crew.yaml" >/dev/null
  mk="$(marker_line eval-mini)"
  mkdir -p "$proj/.claude/agents" "$proj/.claude/skills/eval-mini"
  printf '%s\n' "---" "name: ev" "description: \"Evaluator agent.\"" "tools: Read, Edit, Write" "model: inherit" "---" "$mk" "" "Check." > "$proj/.claude/agents/ev.md"
  printf '%s\n' "---" "name: eval-mini" "description: \"Mini crew with evaluator for T008 tree test. Use in tests only.\"" "disable-model-invocation: true" "---" "$mk" "" "Run." > "$proj/.claude/skills/eval-mini/SKILL.md"
  run_validate_tree "tree/T008-evaluator-write-tools" "$proj" ".agent-composer/eval-mini.crew.yaml" 1 T008

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  echo '{{token}}' >> "$proj/.claude/skills/mini/SKILL.md"
  run_validate_tree "tree/T009-leftover-token" "$proj" "$spec" 1 T009

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  echo '<!-- block: x -->' >> "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T009-block-delimiter" "$proj" "$spec" 1 T009

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  sed -i '/^<!-- generated by agent-composer/d' "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T010-missing-marker" "$proj" "$spec" 1 T010

  read -r proj spec <<<"$(tree_project_fanout | tr '\n' ' ')"
  sed -i 's/alwaysApply: true/alwaysApply: false/' "$proj/.cursor/rules/fanout-mini.mdc"
  run_validate_tree "tree/T011-cursor-rule" "$proj" "$spec" 1 T011

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  rm -f "$proj/.agent-composer/mini.manifest.json"
  printf -- '---\nname: w\ndescription: "Other."\ntools: Read\nmodel: inherit\n---\nhand\n' > "$proj/.claude/agents/w.md"
  run_validate_tree "tree/T012-unmarked-collision" "$proj" "$spec" 1 T012

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  mk="$(marker_line other-crew)"
  sed -i "s|^<!-- generated.*|$mk|" "$proj/.cursor/agents/w.md"
  rm -f "$proj/.agent-composer/mini.manifest.json"
  run_validate_tree "tree/T012-other-crew-marker" "$proj" "$spec" 1 T012

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  {
    cat "$proj/.claude/skills/mini/SKILL.md"
    for ((i=0; i<520; i++)); do echo "padding line $i"; done
  } > "$proj/.claude/skills/mini/SKILL.md.tmp"
  mv "$proj/.claude/skills/mini/SKILL.md.tmp" "$proj/.claude/skills/mini/SKILL.md"
  run_validate_tree "tree/T013-skill-too-long" "$proj" "$spec" 1 T013
}

run_manifest_cases() {
  local proj spec
  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/write-then-unchanged" write "$proj" "$spec" 0
  run_manifest "manifest/status-all-unchanged" status "$proj" "$spec" 0 "unchanged"

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/write-baseline" write "$proj" "$spec" 0
  echo x >> "$proj/.cursor/agents/w.md"
  run_manifest "manifest/status-edited" status "$proj" "$spec" 1 "edited"

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/write-baseline2" write "$proj" "$spec" 0
  rm "$proj/.claude/agents/w.md"
  run_manifest "manifest/status-missing" status "$proj" "$spec" 1 "missing"

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/status-no-manifest-new" status "$proj" "$spec" 1 "new"

  proj="$(mktemp_project)"
  spec="$(install_spec "$proj" "$FIXTURES/specs/two-agent-mini.crew.yaml")"
  materialize_tree "$FIXTURES/trees/two-agent-mini" "$proj"
  run_manifest "manifest/write-for-orphan" write "$proj" ".agent-composer/two-agent-mini.crew.yaml" 0
  cat > "$proj/.agent-composer/two-agent-mini.crew.yaml" <<'YAML'
schema: 1
name: two-agent-mini
description: "Two-agent pipeline for manifest orphan test. Use in tests only."
pattern: pipeline
harnesses: [claude-code, cursor]
agents:
  - id: w
    description: "First worker."
    instructions: Work one.
steps:
  - id: s1
    agent: w
YAML
  run_manifest "manifest/status-orphan" status "$proj" ".agent-composer/two-agent-mini.crew.yaml" 1 "orphan"

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  rm "$proj/.claude/agents/w.md"
  run_manifest "manifest/write-missing-file" write "$proj" "$spec" 1 "missing generated file"

  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "manifest/write-json-fields" write "$proj" "$spec" 0
  if need_yaml_or_skip "manifest/json-schema-fields"; then
    local mf="$proj/.agent-composer/mini.manifest.json"
    if grep -q '"schema": 1' "$mf" && grep -q '"crew": "mini"' "$mf" && \
       grep -q '"generator":' "$mf" && grep -q '"spec_sha256"' "$mf" && \
       grep -q '"harnesses"' "$mf" && grep -q '"files"' "$mf"; then
      case_pass "manifest/json-schema-fields"
    else
      case_fail "manifest/json-schema-fields" "manifest JSON missing required fields"
    fi
  fi
}

run_contract_cases() {
  local out rc stub d
  if need_yaml_or_skip "contract/validate-no-args"; then
    rc=0
    out="$($VALIDATE 2>&1)" || rc=$?
    if [[ "$rc" -eq 2 ]] && assert_no_crash "$out"; then
      case_pass "contract/validate-no-args"
    else
      case_fail "contract/validate-no-args" "exit $rc"
    fi
  fi

  if need_yaml_or_skip "contract/unreadable-spec"; then
    rc=0
    out="$($VALIDATE spec /nonexistent/path.crew.yaml 2>&1)" || rc=$?
    if [[ "$rc" -eq 2 ]] && assert_no_crash "$out"; then
      case_pass "contract/unreadable-spec"
    else
      case_fail "contract/unreadable-spec" "exit $rc"
    fi
  fi

  rc=0
  out="$(AGENT_COMPOSER_PYTHON=/nonexistent $VALIDATE spec "$FIXTURES/specs/mini.crew.yaml" 2>&1)" || rc=$?
  if [[ "$rc" -eq 3 ]] && grep -qF 'python3 -m pip install pyyaml' <<<"$out" && assert_no_crash "$out"; then
    case_pass "contract/missing-python"
  else
    case_fail "contract/missing-python" "exit $rc or missing hint"
  fi

  d="$(mktemp -d "$SCRATCH_ROOT/stub.XXXXXX")"
  cat > "$d/stub-python" <<'STUB'
#!/usr/bin/env bash
exec env PYTHONPATH= python3 -S "$@"
STUB
  chmod +x "$d/stub-python"
  rc=0
  out="$(AGENT_COMPOSER_PYTHON="$d/stub-python" $VALIDATE spec "$FIXTURES/specs/mini.crew.yaml" 2>&1)" || rc=$?
  if [[ "$rc" -eq 3 ]] && grep -qF 'python3 -m pip install pyyaml' <<<"$out" && assert_no_crash "$out"; then
    case_pass "contract/missing-pyyaml-stub"
  else
    case_fail "contract/missing-pyyaml-stub" "exit $rc (stub uses python3 -S with empty PYTHONPATH)"
  fi

  run_validate_spec "contract/summary-format" "$FIXTURES/specs/mini.crew.yaml" 0
}

run_bytes_cases() {
  local proj spec out rc last out2 rc2 c
  if ! have_pyyaml; then for c in bytes/manifest-write bytes/non-utf8-generated-file bytes/non-utf8-manifest; do case_skip "$c" "PyYAML not installed"; done; return 0; fi
  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  run_manifest "bytes/manifest-write" write "$proj" "$spec" 0
  cp "$proj/.cursor/agents/w.md" "$proj/.cursor/agents/w.md.bak"
  printf '\xff\xfe\x00' > "$proj/.cursor/agents/w.md"
  out="$($VALIDATE tree "$proj" "$proj/$spec" 2>&1)" || rc=$?
  rc="${rc:-0}"
  last="$(awk 'NF { line=$0 } END { print line }' <<<"$out")"
  record_codes "$out"
  if [[ "$rc" -eq 1 ]] && assert_no_crash "$out" && [[ "$last" == validate:* ]]; then
    case_pass "bytes/non-utf8-generated-file"
  else
    case_fail "bytes/non-utf8-generated-file" "rc=$rc last=$last"
  fi
  cp "$proj/.cursor/agents/w.md.bak" "$proj/.cursor/agents/w.md"
  printf '\xff\xfe\x00' > "$proj/.agent-composer/mini.manifest.json"
  rc=0
  out="$($VALIDATE tree "$proj" "$proj/$spec" 2>&1)" || rc=$?
  rc2=0
  out2="$($MANIFEST status "$proj" "$proj/$spec" 2>&1)" || rc2=$?
  if [[ "$rc" -eq 2 ]] && [[ "$rc2" -eq 2 ]] && assert_no_crash "$out" && assert_no_crash "$out2" && \
     grep -qF 'error: manifest is unreadable:' <<<"$out" && grep -qF 'error: manifest is unreadable:' <<<"$out2"; then
    case_pass "bytes/non-utf8-manifest"
  else
    case_fail "bytes/non-utf8-manifest" "tree=$rc status=$rc2"
  fi
}

run_marker_cases() {
  local proj spec mk wrong
  if ! mk="$(marker_line mini)"; then
    case_fail "marker/schema-extraction" "could not extract marker from spec-schema.md"
    return 0
  fi
  read -r proj spec <<<"$(tree_project_mini | tr '\n' ' ')"
  wrong="${mk%%— *}— edit the spec and rerun -->"
  python3 - "$proj/.claude/agents/w.md" "$mk" "$wrong" <<'PY'
import pathlib, sys
path, mk, wrong = sys.argv[1:4]
text = pathlib.Path(path).read_text(encoding="utf-8")
if mk not in text:
    sys.exit(2)
pathlib.Path(path).write_text(text.replace(mk, wrong, 1), encoding="utf-8")
PY
  run_validate_tree "marker/wrong-tail-rejected-T010" "$proj" "$spec" 1 T010
  python3 - "$proj/.claude/agents/w.md" "$mk" "$wrong" <<'PY'
import pathlib, sys
path, mk, wrong = sys.argv[1:4]
text = pathlib.Path(path).read_text(encoding="utf-8")
pathlib.Path(path).write_text(text.replace(wrong, mk, 1), encoding="utf-8")
PY
  run_validate_tree "marker/exact-marker-passes" "$proj" "$spec" 0
}

tree_project_inline() {
  local proj spec
  proj="$(mktemp_project)"
  spec="$(install_spec "$proj" "$FIXTURES/specs/inline-mini.crew.yaml")"
  materialize_tree "$FIXTURES/trees/inline-mini" "$proj"
  printf '%s\n.agent-composer/inline-mini.crew.yaml' "$proj"
}

# Runs validate spec; sets SPEC_OUT and SPEC_RC. Returns 1 (after case_fail) on crash or missing summary.
spec_output_or_fail() {
  local name="$1" spec_path="$2"
  SPEC_RC=0
  SPEC_OUT="$($VALIDATE spec "$spec_path" 2>&1)" || SPEC_RC=$?
  record_codes "$SPEC_OUT"
  if ! assert_no_crash "$SPEC_OUT" || ! assert_summary_last "$SPEC_OUT"; then
    case_fail "$name" "internal error or missing validate summary"
    return 1
  fi
  return 0
}

# Passes when exit code is want_rc and no S044 line is present (optionally only none located at the given locations).
run_validate_spec_no_s044() {
  local name="$1" spec_path="$2" want_rc="$3" loc_regex="${4:-}"
  need_yaml_or_skip "$name" || return 0
  spec_output_or_fail "$name" "$spec_path" || return 0
  if [[ "$SPEC_RC" -ne "$want_rc" ]]; then
    case_fail "$name" "exit $SPEC_RC want $want_rc"
    return 0
  fi
  if [[ -z "$loc_regex" ]] && grep -qE '^warn: S044 ' <<<"$SPEC_OUT"; then
    case_fail "$name" "unexpected S044 warning"
    return 0
  fi
  if [[ -n "$loc_regex" ]] && grep -qE "^warn: S044 .*:${loc_regex}:" <<<"$SPEC_OUT"; then
    case_fail "$name" "unexpected S044 warning at $loc_regex"
    return 0
  fi
  case_pass "$name"
}

run_inline_spec_cases() {
  local p="$FIXTURES/specs" ex bad=""
  run_validate_spec "spec/S041-inline-non-worker" "$p/s041-inline-non-worker.crew.yaml" 1 S041
  run_validate_spec "spec/S042-inline-tier" "$p/s042-inline-tier.crew.yaml" 1 S042
  run_validate_spec "spec/S043-inline-parallel" "$p/s043-inline-parallel.crew.yaml" 1 S043
  run_validate_spec "spec/S043-inline-dispatch" "$p/s043-inline-dispatch.crew.yaml" 1 S043
  run_validate_spec "spec/S044-knowledge-only-worker" "$p/s044-knowledge-only-worker.crew.yaml" 0 S044
  if need_yaml_or_skip "spec/S044-knowledge-only-worker-is-warn"; then
    spec_output_or_fail "spec/S044-knowledge-only-worker-is-warn" "$p/s044-knowledge-only-worker.crew.yaml" && \
      if grep -qE '^warn: S044 .*agent .k. looks knowledge-only' <<<"$SPEC_OUT"; then
        case_pass "spec/S044-knowledge-only-worker-is-warn"
      else
        case_fail "spec/S044-knowledge-only-worker-is-warn" "no 'warn: S044' line for agent k"
      fi
  fi
  run_validate_spec_no_s044 "spec/S044-not-for-parallel-member" "$p/fanout-mini.crew.yaml" 0 'agents\[[01]\]'
  run_validate_spec_no_s044 "spec/S044-not-for-single-agent" "$p/s044-not-for-single-agent.crew.yaml" 0
  run_validate_spec_no_s044 "spec/S044-not-for-gated-producer" "$p/s044-not-for-gated-producer.crew.yaml" 0
  run_validate_spec "spec/S006-bad-run" "$p/s006-bad-run.crew.yaml" 1 S006
  run_validate_spec_no_s044 "spec/inline-positive" "$p/inline-mini.crew.yaml" 0
  if need_yaml_or_skip "example/no-S044"; then
    for ex in coding-crew content-crew triage-crew; do
      spec_output_or_fail "example/no-S044" "$SKILL_DIR/assets/examples/$ex.crew.yaml" || return 0
      if grep -qE '^warn: S044 ' <<<"$SPEC_OUT"; then bad="$bad $ex"; fi
    done
    if [[ -z "$bad" ]]; then
      case_pass "example/no-S044"
    else
      case_fail "example/no-S044" "S044 printed for:$bad"
    fi
  fi
}

run_inline_tree_cases() {
  local proj spec mk out rc mf
  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  need_yaml_or_skip "tree/inline-valid" || return 0
  rc=0
  out="$($VALIDATE tree "$proj" "$proj/$spec" 2>&1)" || rc=$?
  record_codes "$out"
  if [[ "$rc" -eq 0 ]] && grep -qxF 'validate: 0 error(s), 0 warning(s)' <<<"$out"; then
    case_pass "tree/inline-valid"
  else
    case_fail "tree/inline-valid" "rc=$rc out=$(tr '\n' '|' <<<"$out")"
  fi

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  rm "$proj/.cursor/skills/inline-mini/roles/k.md"
  run_validate_tree "tree/T001-role-file-missing" "$proj" "$spec" 1 T001

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  sed -i '1d' "$proj/.claude/skills/inline-mini/roles/k.md"
  run_validate_tree "tree/T010-role-file-marker" "$proj" "$spec" 1 T010

  mk="$(marker_line inline-mini)"
  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  printf '%s\n\nstale\n' "$mk" > "$proj/.claude/agents/k.md"
  run_validate_tree "tree/T014-stale-agent-file" "$proj" "$spec" 1 T014

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  printf 'hand-written agent\n' > "$proj/.cursor/agents/k.md"
  rc=0
  out="$($VALIDATE tree "$proj" "$proj/$spec" 2>&1)" || rc=$?
  record_codes "$out"
  if [[ "$rc" -eq 0 ]] && ! grep -qE '(error|warn): T014 ' <<<"$out"; then
    case_pass "tree/T014-unmarked-agent-file-ok"
  else
    case_fail "tree/T014-unmarked-agent-file-ok" "rc=$rc or unexpected T014"
  fi

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  echo '{{x}}' >> "$proj/.cursor/skills/inline-mini/roles/k.md"
  run_validate_tree "tree/T009-role-file-token" "$proj" "$spec" 1 T009

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  mk="$(marker_line other-crew)"
  sed -i "1s|.*|$mk|" "$proj/.claude/skills/inline-mini/roles/k.md"
  rm -f "$proj/.agent-composer/inline-mini.manifest.json"
  run_validate_tree "tree/T012-role-file-collision" "$proj" "$spec" 1 T012

  read -r proj spec <<<"$(tree_project_inline | tr '\n' ' ')"
  if need_yaml_or_skip "manifest/inline-write-status"; then
    rc=0
    out="$($MANIFEST write "$proj" "$proj/$spec" 2>&1)" || rc=$?
    mf="$proj/.agent-composer/inline-mini.manifest.json"
    if [[ "$rc" -ne 0 ]]; then
      case_fail "manifest/inline-write-status" "write rc=$rc"
    elif ! grep -qF '.claude/skills/inline-mini/roles/k.md' "$mf" || ! grep -qF '.cursor/skills/inline-mini/roles/k.md' "$mf"; then
      case_fail "manifest/inline-write-status" "manifest lacks role file paths"
    elif grep -qF '.claude/agents/k.md' "$mf"; then
      case_fail "manifest/inline-write-status" "manifest lists an agent file for the inline agent"
    else
      rc=0
      out="$($MANIFEST status "$proj" "$proj/$spec" 2>&1)" || rc=$?
      if [[ "$rc" -eq 0 ]] && grep -qF 'unchanged .claude/skills/inline-mini/roles/k.md' <<<"$out" && ! grep -qE '^(new|edited|missing|orphan|spec-changed) ' <<<"$out"; then
        case_pass "manifest/inline-write-status"
      else
        case_fail "manifest/inline-write-status" "status rc=$rc out=$(tr '\n' '|' <<<"$out")"
      fi
    fi
  fi
}

run_coverage_case() {
  need_yaml_or_skip "coverage/all-codes-exercised" || return 0
  local missing=() code
  while IFS= read -r code; do
    [[ -z "$code" ]] && continue
    [[ "$code" == S034 ]] && continue
    if [[ -z "${CODES_HIT[$code]:-}" ]]; then
      missing+=("$code")
    fi
  done < <(grep -oE '(S|T)[0-9]{3}' "$SCHEMA" | sort -u)
  if ((${#missing[@]} == 0)); then
    case_pass "coverage/all-codes-exercised"
  else
    case_fail "coverage/all-codes-exercised" "uncovered: ${missing[*]}"
  fi
}

run_guard_model_ids() {
  local hits
  hits="$(grep -rEn '(claude|gpt|gemini|composer|opus|sonnet|haiku)-[0-9]' "$HERE" 2>/dev/null || true)"
  if [[ -z "$hits" ]]; then
    case_pass "guard/no-concrete-model-ids"
  else
    case_fail "guard/no-concrete-model-ids" "forbidden model id pattern in tests"
  fi
}

main() {
  run_positive_specs
  run_example_content_cases
  run_negative_specs
  run_tree_cases
  run_manifest_cases
  run_s040_and_spec_changed_cases
  run_contract_cases
  run_bytes_cases
  run_marker_cases
  run_inline_spec_cases
  run_inline_tree_cases
  run_coverage_case
  run_guard_model_ids
  echo "PASS: $PASS FAIL: $FAIL SKIP: $SKIP"
  [[ "$FAIL" -eq 0 ]]
}

main "$@"
