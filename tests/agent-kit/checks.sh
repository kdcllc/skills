#!/usr/bin/env bash
# Structural verification suite for the AI Orchestration Kit repo
# (test-ladder rung 3 — cycle end only). No runtime, no network:
# greps, bash -n, and frontmatter validation over the working tree.
#
# Checks:
#   A. Every template token used under skills/agent-kit/templates/ is documented
#      in skills/agent-kit/SKILL.md's placeholder table (wildcards honored).
#      `used` is built after stripping class-d `kit-*` BOOTSTRAP comment
#      bodies (those comments may contain grammar examples such as
#      `{{TOKEN}}` that are not placeholders).
#   B. The emitted instance (.claude/, .cursor/, _loop/) contains no unresolved
#      uppercase double-brace tokens and no leftover bootstrap, IF, or ENDIF
#      comments. Label: "instance fully resolved (tokens, bootstrap, IF)".
#      (Both checks-script twins — checks.sh and checks.ps1 — are excluded:
#      this file contains the patterns themselves, and the twins are one
#      logical unit.
#      `.claude/skills/agent-kit/` and `.cursor/skills/agent-kit/` are also excluded:
#      those are the self-install compiler copies, which are supposed to keep
#      unresolved tokens / bootstrap comments. Pattern notes: unresolved
#      tokens are matched as {{UPPER_CASE}}, so documented literal commands
#      like the targeted grep don't false-positive; leftover markers are
#      matched by `<!-- (BOOTSTRAP|IF|ENDIF)`.)
#   C. The canonical loop driver template AND the canonical breaker.sh helper
#      template both parse (bash -n).
#   D. Frontmatter name == folder (skills) / file name (agents), for BOTH the
#      canonical templates and the emitted instance (.claude/ AND .cursor/).
#      Known mapping exception: templates/loop/SKILL.template.md is named auto-loop
#      (emitted to skills/auto-loop/). The self-install compiler copies at
#      `.claude/skills/agent-kit/` and `.cursor/skills/agent-kit/` are pruned (same
#      reason as B: they are not emitted instance).
#   E. No hardcoded model IDs (claude-*/gpt-*/gemini-*) in canonical templates
#      outside models.map.md.
#   F. Skip-aware pwsh parse check: if pwsh is on PATH, parse the canonical and
#      instance loop.ps1 drivers via the .NET parser API. Parse errors FAIL;
#      an invocation error (pwsh present but something else went wrong) WARNs
#      without failing the suite; pwsh absent SKIPs without failing the suite.
#   G. Parity heuristic (drift tripwire, not a proof): both canonical loop
#      drivers (loop.sh/loop.ps1) contain the sentinel string, all six exit
#      codes (0-5), and a matching default iteration count of 10. Also covers
#      the canonical breaker twins (breaker.sh/breaker.ps1): all three state
#      names present in both, the 600s cooldown literal present in both, and
#      the successes threshold keyed on the ACTUAL transition line in each
#      twin's own identifier spelling -- bash's `_BRK_HALF == 2` and ps1's
#      `HalfOpenSuccesses -eq 2` -- via one regex accepting either spelling
#      (halfOpenSuccesses|_BRK_HALF) compared (-eq|==) to 2, so a real 2->N
#      threshold mutation in the code (not just its comment) fails the check.
#   H. Reference coverage: loop.ps1 is mentioned in all four
#      skills/agent-kit/emitters/*.md, in templates/loop/SKILL.template.md, and in
#      templates/ORCHESTRATION.md.
#   I. H-analog for the breaker helper: breaker.ps1 is mentioned in all four
#      skills/agent-kit/emitters/*.md.
#   J. Manifest hash join (self-excluding, seed-aware): reads
#      CHECKS_MANIFEST (default: orchestration-kit.manifest.json, same override
#      form as the manifest path). Verifier is python3 (json + hashlib): SKIPs
#      "python3 not available" when python3 is not on PATH (mirrors check F's
#      interpreter-missing idiom); if python3 runs but exits non-zero (bad
#      JSON, uncaught exception, etc.) the whole sub-check FAILs "verifier
#      failed (exit N)" with the captured output as detail -- a dead verifier
#      is never silently green. Otherwise: for every entry in the manifest's
#      `files` map, the checks-script twins (`tests/agent-kit/checks.sh` and
#      `tests/agent-kit/checks.ps1`) report "self, excluded" and never fail (deadlock
#      fix — J cannot guard the twins' own in-progress edits);
#      `seedFiles` entries report "seed, exempt" and never fail on
#      drift; every other entry gets its sha256 recomputed against the working
#      tree, and FAILs listing every mismatched/missing path. These per-path
#      self/seed lines print to STDOUT on every passing run (not just on
#      failure) — a consumer capturing evidence must capture stdout, not just
#      stderr. A `files` map that parses to ZERO entries FAILs outright ("empty
#      join is not proof of integrity") rather than vacuously passing. The
#      whole hash-join sub-check SKIPs (mirroring check F) only when the
#      manifest FILE itself is absent. Manifest-independent A4 regression grep
#      (its own SKIP if _loop/ is absent): `skills/agent-kit/templates` must not
#      appear in the header region (first 20 lines) of any of the four `_loop`
#      driver/breaker twins; the Twin: line must use the sibling form.
#      kitVersion==VERSION tripwire (its own report line, plain-text join --
#      no python3 required): reads CHECKS_VERSION_FILE (default:
#      skills/agent-kit/SKILL.md metadata.version) and greps/seds the `"kitVersion":` line out of
#      $MANIFEST (the same manifest path the hash join above uses, so
#      CHECKS_MANIFEST steers both J sub-checks together). SKIPs (never FAILs)
#      when either file is absent; FAILs naming both values on mismatch.
#   K. Ownership-contract shape on the CANONICAL templates only: (a) the task
#      template declares each of the five ownership fields
#      (writes/reads/depends_on/owner/rewrite_semantics) exactly once, anchored
#      at column 0; (b) the literal "Write fence" appears in both worker agent
#      templates (implementer.md, test-writer.md); (c) the goal-criteria
#      template contains the "### Ownership contract" heading, the "Missing
#      ownership block" remedy line, and the "bracket-literal placeholder
#      values" pristine-block literal (presence-only).
#   L. ps1 unbraced-colon interpolation: a line-based tripwire, not proof
#      (here-strings and multi-line constructs are out of scope; check F owns
#      parser-level truth where pwsh exists). Flags "$Var:"-style unbraced
#      colon interpolation inside double-quoted strings (colon not followed by
#      a variable-name character, no backslash exemption) across a target set
#      derived at run time: every *.ps1 under skills/agent-kit/templates/,
#      _loop/, and scripts/, excluding any file named checks.ps1. A missing
#      root is skipped and noted without failing by itself; the empty-set FAIL
#      fires only when the TOTAL derived set across all present roots is
#      empty.
#   M. No `.claude/` path reference exists anywhere under `.cursor/` (excluding
#      the self-install compiler copy at `.cursor/skills/agent-kit/`) — plain
#      ignore-blind `grep -r` (never `rg`, which honors .gitignore and passes
#      vacuously on the gitignored `.cursor/` tree), matching check B's idiom.
#      The single-copy `checks.sh` verification script only exists at
#      `.claude/checks.sh` (no per-harness twin); prose that names it under
#      `.cursor/` refers to it by bare filename ("checks.sh", "the `.claude`
#      directory") rather than the `.claude/checks.sh` path, so this check has
#      no carve-outs — any `.claude/` hit under `.cursor/` is real
#      cross-contamination and FAILs.
#   N. `.cursor/` <-> `.claude/` skill-tree drift: every
#      `.cursor/skills/*/SKILL.md` (excluding `agent-kit/`) must be byte-identical
#      to its `.claude/skills/` twin after normalizing `.cursor/` -> `.claude/`
#      path references (`sed 's|\.cursor/|\.claude/|g'` on the `.cursor` copy,
#      diffed against the `.claude` twin). Converts silent divergence between
#      the two emitted skill trees into an immediate red check. SKIPs if
#      `.cursor/skills/` is absent.
#   O. Emitter twins parse: `bash -n skills/agent-kit/bin/emit.sh` (PASS/FAIL)
#      and skip-aware pwsh parse of `skills/agent-kit/bin/emit.ps1`
#      (PASS / SKIP when pwsh is absent / FAIL).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

fail_count=0
declare -a summary=()

report() { # report <PASS|FAIL|WARN|SKIP> <check-name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  if [[ "$status" == "FAIL" ]]; then
    fail_count=$((fail_count + 1))
    echo "FAIL: $name${detail:+ — $detail}" >&2
  fi
  summary+=("$status  $name")
}

# ---------------------------------------------------------------------------
# Check A: every {{TOKEN}} used in templates is documented in SKILL.md's table
# ---------------------------------------------------------------------------
check_a() {
  local used documented tok pat tok_name pat_name ok undocumented=()
  # Class-d kit-* BOOTSTRAP bodies are instruction-only and may contain
  # grammar examples (e.g. {{TOKEN}} in kit-meta) that are not placeholders.
  used="$(
    find skills/agent-kit/templates -type f -print0 |
    while IFS= read -r -d '' f; do
      awk '
        BEGIN { in_kit = 0 }
        {
          if (in_kit) {
            if ($0 ~ /-->/) in_kit = 0
            next
          }
          if ($0 ~ /<!--[[:space:]]*BOOTSTRAP\[kit-[a-z0-9]+(-[a-z0-9]+)*\]:/) {
            if ($0 !~ /-->/) in_kit = 1
            next
          }
          print
        }
      ' "$f"
    done | grep -oE '\{\{[A-Z_]+\}\}' | sort -u
  )"
  documented="$(grep -oE '\{\{[A-Z_*]+\}\}' skills/agent-kit/SKILL.md | sort -u)"
  if [[ -z "$documented" ]]; then
    report FAIL "A: placeholder-table coverage" "no tokens found in skills/agent-kit/SKILL.md"
    return
  fi
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    tok_name="${tok:2:${#tok}-4}"
    ok=0
    while IFS= read -r pat; do
      [[ -z "$pat" ]] && continue
      pat_name="${pat:2:${#pat}-4}"
      # shellcheck disable=SC2053  # unquoted RHS: glob match honors wildcards
      if [[ "$tok_name" == $pat_name ]]; then ok=1; break; fi
    done <<< "$documented"
    ((ok)) || undocumented+=("$tok")
  done <<< "$used"
  if ((${#undocumented[@]})); then
    report FAIL "A: placeholder-table coverage" "undocumented tokens: ${undocumented[*]}"
    for tok in "${undocumented[@]}"; do
      grep -rn --fixed-strings "$tok" skills/agent-kit/templates/ | head -5 >&2
    done
  else
    report PASS "A: placeholder-table coverage"
  fi
}

# ---------------------------------------------------------------------------
# Check B: instance is fully resolved (no tokens, no bootstrap comments)
# ---------------------------------------------------------------------------
check_b() {
  local hits
  hits="$(grep -rnE '\{\{[A-Z_]+\}\}|<!-- (BOOTSTRAP|IF|ENDIF)' .claude/ .cursor/ _loop/ \
            --exclude='checks.sh' --exclude='checks.ps1' --exclude-dir='agent-kit' 2>/dev/null)"
  if [[ -n "$hits" ]]; then
    report FAIL "B: instance fully resolved (tokens, bootstrap, IF)" "leftover tokens/bootstrap/IF comments"
    printf '%s\n' "$hits" >&2
  else
    report PASS "B: instance fully resolved (tokens, bootstrap, IF)"
  fi
}

# ---------------------------------------------------------------------------
# Check C: canonical loop.sh AND breaker.sh templates are valid bash
# ---------------------------------------------------------------------------
check_c() {
  local out bad=()
  if out="$(bash -n skills/agent-kit/templates/loop/loop.sh 2>&1)"; then
    :
  else
    bad+=("loop.sh: $out")
  fi
  if out="$(bash -n skills/agent-kit/templates/loop/breaker.sh 2>&1)"; then
    :
  else
    bad+=("breaker.sh: $out")
  fi
  if ((${#bad[@]})); then
    report FAIL "C: loop.sh + breaker.sh template bash -n" "${bad[*]}"
  else
    report PASS "C: loop.sh + breaker.sh template bash -n"
  fi
}

# ---------------------------------------------------------------------------
# Check D: frontmatter name matches folder/file — canonical AND instance
# ---------------------------------------------------------------------------
check_d() {
  local f name expected bad=()
  local skill_files agent_files

  skill_files=$( {
    find skills/agent-kit -path 'skills/agent-kit/templates' -prune -o -name 'SKILL.md' -print
    find skills/agent-kit/templates -name 'SKILL.template.md'
    find .claude/skills -path '.claude/skills/agent-kit' -prune -o -name 'SKILL.md' -print
    find .cursor/skills -path '.cursor/skills/agent-kit' -prune -o -name 'SKILL.md' -print
  } 2>/dev/null | sort)
  agent_files=$(find skills/agent-kit/templates/agents .claude/agents .cursor/agents -name '*.md' 2>/dev/null | sort)

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    name="$(awk -F': *' 'NR>1 && /^---$/{exit} /^name:/{print $2; exit}' "$f")"
    if [[ "$f" == "skills/agent-kit/templates/loop/SKILL.template.md" ]]; then
      expected="auto-loop"   # emitter maps templates/loop/ -> .claude/skills/auto-loop/
    else
      expected="$(basename "$(dirname "$f")")"
    fi
    if [[ -z "$name" ]]; then
      bad+=("$f: missing frontmatter name")
    elif [[ "$name" != "$expected" ]]; then
      bad+=("$f: name '$name' != expected '$expected'")
    fi
  done <<< "$skill_files"

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    name="$(awk -F': *' 'NR>1 && /^---$/{exit} /^name:/{print $2; exit}' "$f")"
    expected="$(basename "$f" .md)"
    if [[ -z "$name" ]]; then
      bad+=("$f: missing frontmatter name")
    elif [[ "$name" != "$expected" ]]; then
      bad+=("$f: name '$name' != expected '$expected'")
    fi
  done <<< "$agent_files"

  if ((${#bad[@]})); then
    report FAIL "D: frontmatter name==folder/file" "${#bad[@]} mismatch(es)"
    printf '%s\n' "${bad[@]}" >&2
  else
    report PASS "D: frontmatter name==folder/file"
  fi
}

# ---------------------------------------------------------------------------
# Check E: no hardcoded model IDs in canonical templates outside models.map.md
# ---------------------------------------------------------------------------
check_e() {
  local hits
  hits="$(grep -rnE '(claude|gpt|gemini)-[0-9a-z]' skills/agent-kit/templates/ \
            --exclude='models.map.md' 2>/dev/null)"
  if [[ -n "$hits" ]]; then
    report FAIL "E: no hardcoded model IDs in templates" "model IDs belong in models.map.md"
    printf '%s\n' "$hits" >&2
  else
    report PASS "E: no hardcoded model IDs in templates"
  fi
}


# ---------------------------------------------------------------------------
# Check F: skip-aware pwsh parse of loop.ps1 (canonical + instance)
# ---------------------------------------------------------------------------
check_f() {
  if ! command -v pwsh >/dev/null 2>&1; then
    report SKIP "F: pwsh not available"
    return
  fi

  local targets=(
    "skills/agent-kit/templates/loop/loop.ps1"
    "_loop/loop.ps1"
    "skills/agent-kit/templates/loop/breaker.ps1"
    "_loop/breaker.ps1"
  )
  local f out rc parse_errors=0 invocation_errors=0 detail=""

  for f in "${targets[@]}"; do
    if [[ ! -f "$f" ]]; then
      invocation_errors=1
      detail+=$'\n'"$f: file not found"
      continue
    fi
    out="$(PWSH_TARGET_FILE="$f" pwsh -NoProfile -Command '
      $ErrorActionPreference = "Stop"
      $path = $env:PWSH_TARGET_FILE
      try {
        $tokens = $null
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs) | Out-Null
        if ($errs.Count -gt 0) {
          $errs | ForEach-Object { Write-Output $_.ToString() }
          exit 2
        }
        exit 0
      } catch {
        Write-Output $_.Exception.Message
        exit 3
      }
    ' 2>&1)"
    rc=$?
    if ((rc == 2)); then
      parse_errors=1
      detail+=$'\n'"$f: parse errors:"$'\n'"$out"
    elif ((rc != 0)); then
      invocation_errors=1
      detail+=$'\n'"$f: pwsh invocation error (exit $rc): $out"
    fi
  done

  if ((parse_errors)); then
    report FAIL "F: pwsh parse (skip-aware)" "parse errors found"
    printf '%s\n' "$detail" >&2
  elif ((invocation_errors)); then
    report WARN "F: pwsh parse (skip-aware)" "invocation error, not a parse failure"
    printf '%s\n' "$detail" >&2
  else
    report PASS "F: pwsh parse (skip-aware)"
  fi
}

# ---------------------------------------------------------------------------
# Check G: parity heuristic — sentinel, all six exit codes, matching default
# iteration count between the two canonical drivers (drift tripwire, not proof)
# ---------------------------------------------------------------------------
check_g() {
  local sh="skills/agent-kit/templates/loop/loop.sh"
  local ps1="skills/agent-kit/templates/loop/loop.ps1"
  local sentinel='<promise>COMPLETE</promise>'
  local bad=() f n sh_default ps1_default

  for f in "$sh" "$ps1"; do
    if [[ ! -f "$f" ]]; then
      bad+=("$f: file not found")
      continue
    fi
    grep -qF "$sentinel" "$f" || bad+=("$f: missing sentinel string")
    for n in 0 1 2 3 4 5; do
      grep -qE "exit $n([^0-9]|\$)" "$f" || bad+=("$f: missing exit $n")
    done
  done

  # Note: extracting the default digits requires anchoring on the closing brace —
  # a naive [0-9]+ over the whole ${1:-10} match would also pick up the "1" in
  # the positional-parameter index and corrupt the comparison below.
  sh_default="$(grep -oE '\{1:-[0-9]+\}' "$sh" 2>/dev/null | grep -oE '[0-9]+\}' | tr -d '}')"
  ps1_default="$(grep -oE '\$MaxIterations = [0-9]+' "$ps1" 2>/dev/null | grep -oE '[0-9]+$')"
  if [[ -z "$sh_default" ]]; then
    bad+=("$sh: no default iteration count found")
  elif [[ "$sh_default" != "10" ]]; then
    bad+=("$sh: default iteration count is $sh_default, expected 10")
  fi
  if [[ -z "$ps1_default" ]]; then
    bad+=("$ps1: no default iteration count found")
  elif [[ "$ps1_default" != "10" ]]; then
    bad+=("$ps1: default iteration count is $ps1_default, expected 10")
  fi
  if [[ -n "$sh_default" && -n "$ps1_default" && "$sh_default" != "$ps1_default" ]]; then
    bad+=("default iteration counts differ: loop.sh=$sh_default loop.ps1=$ps1_default")
  fi

  # Breaker twins: state names, cooldown literal, successes threshold keyed on
  # the ACTUAL transition line (not a bare digit, and not merely a comment
  # that could drift from the code) -- one regex accepting either twin's own
  # identifier spelling (bash: _BRK_HALF, ps1: HalfOpenSuccesses) compared via
  # -eq/== to the literal 2, so a real threshold mutation in the code fails.
  local brk_sh="skills/agent-kit/templates/loop/breaker.sh"
  local brk_ps1="skills/agent-kit/templates/loop/breaker.ps1"
  for f in "$brk_sh" "$brk_ps1"; do
    if [[ ! -f "$f" ]]; then
      bad+=("$f: file not found")
      continue
    fi
    grep -qF "CLOSED" "$f" || bad+=("$f: missing state name CLOSED")
    grep -qF "OPEN" "$f" || bad+=("$f: missing state name OPEN")
    grep -qF "HALF-OPEN" "$f" || bad+=("$f: missing state name HALF-OPEN")
    grep -qF "600" "$f" || bad+=("$f: missing cooldown literal 600")
    grep -qiE '(halfOpenSuccesses|_BRK_HALF)[^0-9]*(-eq|==)[^0-9]*2' "$f" || \
      bad+=("$f: successes threshold ACTUAL transition line (halfOpenSuccesses/_BRK_HALF compared -eq/== 2) not found")
  done

  if ((${#bad[@]})); then
    report FAIL "G: loop driver parity heuristic" "${#bad[@]} issue(s)"
    printf '%s\n' "${bad[@]}" >&2
  else
    report PASS "G: loop driver parity heuristic"
  fi
}

# ---------------------------------------------------------------------------
# Check H: loop.ps1 reference coverage across setup docs
# ---------------------------------------------------------------------------
check_h() {
  local files=(
    "skills/agent-kit/emitters/claude-code.md"
    "skills/agent-kit/emitters/codex.md"
    "skills/agent-kit/emitters/copilot.md"
    "skills/agent-kit/emitters/cursor.md"
    "skills/agent-kit/templates/loop/SKILL.template.md"
    "skills/agent-kit/templates/ORCHESTRATION.md"
  )
  local f missing=()
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing+=("$f: file not found")
    elif ! grep -qF 'loop.ps1' "$f"; then
      missing+=("$f: no mention of loop.ps1")
    fi
  done
  if ((${#missing[@]})); then
    report FAIL "H: loop.ps1 reference coverage" "${#missing[@]} file(s) missing mention"
    printf '%s\n' "${missing[@]}" >&2
  else
    report PASS "H: loop.ps1 reference coverage"
  fi
}

# ---------------------------------------------------------------------------
# Check I: H-analog for the breaker helper -- breaker.ps1 mentioned in all
# four skills/agent-kit/emitters/*.md
# ---------------------------------------------------------------------------
check_i() {
  local files=(
    "skills/agent-kit/emitters/claude-code.md"
    "skills/agent-kit/emitters/codex.md"
    "skills/agent-kit/emitters/copilot.md"
    "skills/agent-kit/emitters/cursor.md"
  )
  local f missing=()
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing+=("$f: file not found")
    elif ! grep -qF 'breaker.ps1' "$f"; then
      missing+=("$f: no mention of breaker.ps1")
    fi
  done
  if ((${#missing[@]})); then
    report FAIL "I: breaker.ps1 reference coverage" "${#missing[@]} file(s) missing mention"
    printf '%s\n' "${missing[@]}" >&2
  else
    report PASS "I: breaker.ps1 reference coverage"
  fi
}

# ---------------------------------------------------------------------------
# Check J: manifest + seed-class hash integrity (self-excluding), the
# manifest-independent A4 regression grep over the four _loop driver/breaker
# twins, and the kitVersion==VERSION tripwire. Three independently gated
# sub-checks, each with its own report() line.
# ---------------------------------------------------------------------------
check_j() {
  local MANIFEST="${CHECKS_MANIFEST:-orchestration-kit.manifest.json}"

  if [[ ! -f "$MANIFEST" ]]; then
    report SKIP "J: manifest hash join" "$MANIFEST not found"
  elif ! command -v python3 >/dev/null 2>&1; then
    report SKIP "J: manifest hash join" "python3 not available"
  else
    # Verifier output goes to a temp file (never a pipe) so the exit status of
    # python3 itself is captured directly via $? in THIS shell, and the
    # while-read loop below (fed via plain input redirection, not a pipe)
    # populates the `bad`/`entry_count` arrays/vars in this same shell too --
    # a dead or misbehaving verifier must fail closed, not vanish silently.
    local tmp_out rc line status path bad=() entry_count=""
    tmp_out="$(mktemp)"
    python3 - "$MANIFEST" >"$tmp_out" 2>&1 <<'PY'
import hashlib, json, sys

manifest_path = sys.argv[1]
with open(manifest_path) as f:
    data = json.load(f)

files = data.get("files", {})
seed = set(data.get("seedFiles", []))
print(f"COUNT {len(files)}")
for path, expected in files.items():
    if path in ("tests/agent-kit/checks.sh", "tests/agent-kit/checks.ps1"):
        print(f"SELF {path}")
        continue
    if path in seed:
        print(f"SEED {path}")
        continue
    try:
        with open(path, "rb") as fh:
            actual = hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        print(f"MISSING {path}")
        continue
    if actual != expected:
        print(f"MISMATCH {path}")
    else:
        print(f"OK {path}")
PY
    rc=$?

    if ((rc != 0)); then
      report FAIL "J: manifest hash join" "verifier failed (exit $rc)"
      sed 's/^/    /' "$tmp_out" >&2
    else
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        status="${line%% *}"
        path="${line#* }"
        case "$status" in
          COUNT) entry_count="$path" ;;
          SELF) echo "J: self, excluded -- $path" ;;
          SEED) echo "J: seed, exempt -- $path" ;;
          MISMATCH) bad+=("$path: sha256 mismatch") ;;
          MISSING) bad+=("$path: file missing") ;;
        esac
      done < "$tmp_out"

      if [[ -z "$entry_count" || "$entry_count" -eq 0 ]]; then
        report FAIL "J: manifest hash join" "manifest 'files' map has zero entries -- empty join is not proof of integrity"
      elif ((${#bad[@]})); then
        report FAIL "J: manifest hash join" "${#bad[@]} path(s) mismatched/missing"
        printf '%s\n' "${bad[@]}" >&2
      else
        report PASS "J: manifest hash join"
      fi
    fi
    rm -f "$tmp_out"
  fi

  if [[ ! -d "_loop" ]]; then
    report SKIP "J: A4 regression grep" "_loop/ not found"
  else
    local a4_targets=(
      "_loop/loop.sh"
      "_loop/loop.ps1"
      "_loop/breaker.sh"
      "_loop/breaker.ps1"
    )
    local f a4_bad=()
    for f in "${a4_targets[@]}"; do
      if [[ ! -f "$f" ]]; then
        a4_bad+=("$f: file not found")
      elif head -n 20 "$f" | grep -qF 'skills/agent-kit/templates'; then
        a4_bad+=("$f: header (first 20 lines) contains 'skills/agent-kit/templates' — Twin: line must use sibling form (A4 regression)")
      fi
    done
    if ((${#a4_bad[@]})); then
      report FAIL "J: A4 regression grep" "${#a4_bad[@]} issue(s)"
      printf '%s\n' "${a4_bad[@]}" >&2
    else
      report PASS "J: A4 regression grep"
    fi
  fi

  # kitVersion==VERSION tripwire: a plain-text join (grep/sed the
  # `"kitVersion":` line) so it runs even where the hash-join sub-check above
  # SKIPs on a missing python3. SKIPs (never FAILs) when either file is
  # absent, mirroring the manifest-absent idiom above.
  local VERSION_FILE="${CHECKS_VERSION_FILE:-skills/agent-kit/SKILL.md}"
  if [[ ! -f "$VERSION_FILE" ]]; then
    report SKIP "J: kitVersion==VERSION join" "$VERSION_FILE not found"
  elif [[ ! -f "$MANIFEST" ]]; then
    report SKIP "J: kitVersion==VERSION join" "$MANIFEST not found"
  else
    local version_val manifest_val
    # A SKILL.md yields metadata.version; a bare version file (mutation
    # fixtures) yields its whitespace-stripped content.
    if [[ "$(head -n 1 "$VERSION_FILE")" == "---" ]]; then
      version_val="$(awk '
        NR == 1 { next }
        /^---$/ { exit }
        /^metadata:/ { m = 1; next }
        m && /^[^ \t]/ { exit }
        m && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
      ' "$VERSION_FILE")"
    else
      version_val="$(tr -d '[:space:]' < "$VERSION_FILE")"
    fi
    manifest_val="$(grep -m1 '"kitVersion"' "$MANIFEST" | \
      sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
    if [[ -z "$manifest_val" ]]; then
      report FAIL "J: kitVersion==VERSION join" "could not extract kitVersion from $MANIFEST"
    elif [[ "$version_val" != "$manifest_val" ]]; then
      report FAIL "J: kitVersion==VERSION join" "VERSION=$version_val kitVersion=$manifest_val"
    else
      report PASS "J: kitVersion==VERSION join"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Check K: ownership-contract shape on the CANONICAL templates only
# ---------------------------------------------------------------------------
check_k() {
  local bad=()
  local task_tpl="skills/agent-kit/templates/skills/feature/templates/task.md"
  local impl_tpl="skills/agent-kit/templates/agents/implementer.md"
  local tw_tpl="skills/agent-kit/templates/agents/test-writer.md"
  local criteria_tpl="skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md"

  if [[ ! -f "$task_tpl" ]]; then
    bad+=("$task_tpl: file not found")
  else
    local field n
    for field in '^writes:' '^reads:' '^depends_on:' '^owner:' '^rewrite_semantics:'; do
      n="$(grep -cE "$field" "$task_tpl")"
      if [[ "$n" -ne 1 ]]; then
        bad+=("$task_tpl: $field count is $n, expected 1")
      fi
    done
  fi

  local f
  for f in "$impl_tpl" "$tw_tpl"; do
    if [[ ! -f "$f" ]]; then
      bad+=("$f: file not found")
    elif ! grep -qF 'Write fence' "$f"; then
      bad+=("$f: missing 'Write fence'")
    fi
  done

  if [[ ! -f "$criteria_tpl" ]]; then
    bad+=("$criteria_tpl: file not found")
  else
    grep -qF '### Ownership contract' "$criteria_tpl" || \
      bad+=("$criteria_tpl: missing '### Ownership contract'")
    grep -qF 'Missing ownership block' "$criteria_tpl" || \
      bad+=("$criteria_tpl: missing 'Missing ownership block'")
    grep -qF 'bracket-literal placeholder values' "$criteria_tpl" || \
      bad+=("$criteria_tpl: missing 'bracket-literal placeholder values'")
  fi

  if ((${#bad[@]})); then
    report FAIL "K: ownership-contract shape" "${#bad[@]} issue(s)"
    printf '%s\n' "${bad[@]}" >&2
  else
    report PASS "K: ownership-contract shape"
  fi
}

# ---------------------------------------------------------------------------
# Check L: ps1 unbraced-colon interpolation (accepted-limitation line-based
# scan, not a parser -- here-strings/multi-line constructs are out of scope;
# check F owns parser-level truth where pwsh exists). Derived target set
# computed at run time: every *.ps1 under skills/agent-kit/templates/, _loop/,
# and scripts/, excluding any file named checks.ps1. A missing root is
# skipped and noted without failing by itself; the empty-set FAIL fires only
# when the TOTAL derived set across all present roots is empty.
# ---------------------------------------------------------------------------
check_l() {
  local roots=("skills/agent-kit/templates" "_loop" "scripts")
  local root f targets=() hits=()

  for root in "${roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      echo "L: root not found, skipped -- $root"
      continue
    fi
    while IFS= read -r -d '' f; do
      targets+=("$f")
    done < <(find "$root" -type f -name '*.ps1' ! -name 'checks.ps1' -print0)
  done

  if ((${#targets[@]} == 0)); then
    report FAIL "L: ps1 unbraced-colon interpolation" "empty target set is not proof"
    return
  fi

  for f in "${targets[@]}"; do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      hits+=("$f:$line")
    done < <(grep -nE '"' "$f" 2>/dev/null | \
              grep -E '\$[A-Za-z_][A-Za-z0-9_]*:([^A-Za-z0-9_]|$)' | \
              grep -vE '^[0-9]+:[[:space:]]*#')
  done

  if ((${#hits[@]})); then
    report FAIL "L: ps1 unbraced-colon interpolation" "unbraced colon interpolation found"
    printf '%s\n' "${hits[@]}" >&2
  else
    report PASS "L: ps1 unbraced-colon interpolation"
  fi
}

# ---------------------------------------------------------------------------
# Check M: no .claude/ path reference exists under .cursor/ (excluding the
# self-install compiler copy at .cursor/skills/agent-kit/) -- plain ignore-blind
# grep -r, matching check B's existing idiom (never rg, which would honor
# .gitignore and pass vacuously on the gitignored .cursor/ tree). No
# carve-outs: any `.claude/` reference under .cursor/ (skills/agents/rules
# pointing at `.claude/skills/...`, `.claude/agents/...`,
# `.claude/ORCHESTRATION.md`, etc.) is real cross-contamination and FAILs.
# Exclusion is anchored to the .cursor/skills/agent-kit/ subtree specifically
# (not "any directory named setup" anywhere), mirroring the ps1 twin's
# `-notmatch '/\.cursor/skills/agent-kit(/|$)'`.
# ---------------------------------------------------------------------------
check_m() {
  local hits
  hits="$(grep -rn '\.claude/' .cursor/ 2>/dev/null | grep -v '^\.cursor/skills/agent-kit/')"
  if [[ -n "$hits" ]]; then
    report FAIL "M: no .claude/ references under .cursor/" "stray .claude/ path reference(s) found"
    printf '%s\n' "$hits" >&2
  else
    report PASS "M: no .claude/ references under .cursor/"
  fi
}

# ---------------------------------------------------------------------------
# Check N: .cursor/<->.claude/ skill-tree drift. Every .cursor/skills/*/SKILL.md
# (excluding agent-kit/) must be byte-identical to its .claude/skills/ twin after
# normalizing .cursor/ -> .claude/ path references (sed 's|\.cursor/|\.claude/|g'
# on the .cursor copy, diffed against the .claude twin). Converts silent
# divergence between the two emitted skill trees into an immediate red check.
# ---------------------------------------------------------------------------
check_n() {
  local f name twin bad=()
  local cursor_skills
  cursor_skills=$(find .cursor/skills -path '.cursor/skills/agent-kit' -prune -o -name 'SKILL.md' -print 2>/dev/null | sort)
  if [[ -z "$cursor_skills" ]]; then
    report SKIP "N: .cursor/↔.claude/ skill-tree drift" ".cursor/skills/ not found"
    return
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    name="$(basename "$(dirname "$f")")"
    twin=".claude/skills/$name/SKILL.md"
    if [[ ! -f "$twin" ]]; then
      bad+=("$f: no twin at $twin")
      continue
    fi
    if ! diff -q <(sed 's|\.cursor/|\.claude/|g' "$f") "$twin" >/dev/null 2>&1; then
      bad+=("$f: differs from $twin after .cursor/ -> .claude/ normalization")
    fi
  done <<< "$cursor_skills"
  if ((${#bad[@]})); then
    report FAIL "N: .cursor/↔.claude/ skill-tree drift" "${#bad[@]} mismatch(es)"
    printf '%s\n' "${bad[@]}" >&2
  else
    report PASS "N: .cursor/↔.claude/ skill-tree drift"
  fi
}

# ---------------------------------------------------------------------------
# Check O: emitter twins parse — bash -n of skills/agent-kit/bin/emit.sh and
# skip-aware pwsh parse of skills/agent-kit/bin/emit.ps1.
# ---------------------------------------------------------------------------
check_o() {
  local out rc
  if [[ ! -f skills/agent-kit/bin/emit.sh ]]; then
    report FAIL "O: emit.sh bash -n" "skills/agent-kit/bin/emit.sh not found"
  elif out="$(bash -n skills/agent-kit/bin/emit.sh 2>&1)"; then
    report PASS "O: emit.sh bash -n"
  else
    report FAIL "O: emit.sh bash -n" "$out"
  fi

  if ! command -v pwsh >/dev/null 2>&1; then
    report SKIP "O: emit.ps1 pwsh parse" "pwsh not available"
    return
  fi
  if [[ ! -f skills/agent-kit/bin/emit.ps1 ]]; then
    report FAIL "O: emit.ps1 pwsh parse" "skills/agent-kit/bin/emit.ps1 not found"
    return
  fi
  out="$(PWSH_TARGET_FILE="skills/agent-kit/bin/emit.ps1" pwsh -NoProfile -Command '
      $ErrorActionPreference = "Stop"
      $path = $env:PWSH_TARGET_FILE
      try {
        $tokens = $null
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs) | Out-Null
        if ($errs.Count -gt 0) {
          $errs | ForEach-Object { Write-Output $_.ToString() }
          exit 2
        }
        exit 0
      } catch {
        Write-Output $_.Exception.Message
        exit 3
      }
    ' 2>&1)"
  rc=$?
  if ((rc == 2)); then
    report FAIL "O: emit.ps1 pwsh parse" "parse errors found"
    printf '%s\n' "$out" >&2
  elif ((rc != 0)); then
    report FAIL "O: emit.ps1 pwsh parse" "pwsh invocation error (exit $rc): $out"
  else
    report PASS "O: emit.ps1 pwsh parse"
  fi
}

check_a
check_b
check_c
check_d
check_e
check_f
check_g
check_h
check_i
check_j
check_k
check_l
check_m
check_n
check_o

echo
echo "=== checks.sh summary ==="
printf '%s\n' "${summary[@]}"
if ((fail_count)); then
  echo "RESULT: $fail_count check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
exit 0
