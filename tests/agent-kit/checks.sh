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
#      (tests/agent-kit/checks.sh is excluded: this file contains the patterns
#      themselves.
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
#      outside models.map.md; the usage-format token claude-stream is exempt.
#   F. Canonical kit has no PowerShell scripts: `find skills/agent-kit -name
#      '*.ps1'` must be empty — any hit FAILs listing paths.
#   G. Loop driver heuristic (drift tripwire, not a proof): the canonical
#      loop.sh contains the sentinel string, all six exit codes (0-5), and a
#      default iteration count of 10. The canonical breaker.sh contains all
#      three state names, the 600s cooldown literal, and the successes
#      threshold keyed on `_BRK_HALF == 2`.
#   H. Reference coverage: loop.cmd is mentioned in all four
#      skills/agent-kit/emitters/*.md, in templates/loop/SKILL.template.md, and in
#      templates/ORCHESTRATION.md; loop.ps1 is mentioned in none of them.
#   I. Breaker helper docs: breaker.ps1 is mentioned in none of the four
#      skills/agent-kit/emitters/*.md.
#   J. Manifest hash join (self-excluding, seed-aware): reads
#      CHECKS_MANIFEST (default: orchestration-kit.manifest.json, same override
#      form as the manifest path). Verifier is python3 (json + hashlib): SKIPs
#      "python3 not available" when python3 is not on PATH; if python3 runs
#      but exits non-zero (bad
#      JSON, uncaught exception, etc.) the whole sub-check FAILs "verifier
#      failed (exit N)" with the captured output as detail -- a dead verifier
#      is never silently green. Otherwise: for every entry in the manifest's
#      `files` map, `tests/agent-kit/checks.sh` reports "self, excluded" and never
#      fails (deadlock fix — J cannot guard its own in-progress edits);
#      `seedFiles` entries report "seed, exempt" and never fail on
#      drift; every other entry gets its sha256 recomputed against the working
#      tree, and FAILs listing every mismatched/missing path. These per-path
#      self/seed lines print to STDOUT on every passing run (not just on
#      failure) — a consumer capturing evidence must capture stdout, not just
#      stderr. A `files` map that parses to ZERO entries FAILs outright ("empty
#      join is not proof of integrity") rather than vacuously passing. The
#      whole hash-join sub-check SKIPs only when the
#      manifest FILE itself is absent. Manifest-independent A4 regression grep
#      (its own SKIP if _loop/ is absent): `skills/agent-kit/templates` must not
#      appear in the header region (first 20 lines) of `_loop/loop.sh` or
#      `_loop/breaker.sh`.
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
#   O. Emitter parse: `bash -n skills/agent-kit/bin/emit.sh` (PASS/FAIL).
#   P. Instance Windows launchers: `_kit/memory.cmd` and `_kit/log-spawn.cmd`
#      present; `_kit/log-spawn.ps1` and `_kit/memory.ps1` absent; when `_loop/`
#      exists, `_loop/loop.cmd` present and `_loop/loop.ps1` / `_loop/breaker.ps1`
#      absent; root `.gitattributes` contains `*.cmd -text`.
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
            --exclude='checks.sh' --exclude-dir='agent-kit' 2>/dev/null)"
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
_check_e_filter() {
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    stripped="$(printf '%s\n' "$line" | sed -E 's/claude-stream([^0-9A-Za-z_-]|$)/\1/g')"
    if printf '%s\n' "$stripped" | grep -qE '(claude|gpt|gemini)-[0-9a-z]'; then
      printf '%s\n' "$line"
    fi
  done
}

check_e() {
  local hits
  hits="$(grep -rnE '(claude|gpt|gemini)-[0-9a-z]' skills/agent-kit/templates/ \
            --exclude='models.map.md' 2>/dev/null | _check_e_filter)"
  if [[ -n "$hits" ]]; then
    report FAIL "E: no hardcoded model IDs in templates" "model IDs belong in models.map.md"
    printf '%s\n' "$hits" >&2
  else
    report PASS "E: no hardcoded model IDs in templates"
  fi
}


# ---------------------------------------------------------------------------
# Check F: no .ps1 files under skills/agent-kit (Bash-only canonical kit)
# ---------------------------------------------------------------------------
check_f() {
  local found=() f
  [[ -d skills/agent-kit ]] || { report FAIL "F: no .ps1 under skills/agent-kit" "skills/agent-kit not found"; return; }
  while IFS= read -r -d '' f; do
    found+=("$f")
  done < <(find skills/agent-kit -type f -name '*.ps1' -print0 2>/dev/null)
  if ((${#found[@]})); then
    report FAIL "F: no .ps1 under skills/agent-kit" "${#found[@]} file(s)"
    printf '%s\n' "${found[@]}" >&2
  else
    report PASS "F: no .ps1 under skills/agent-kit"
  fi
}

# ---------------------------------------------------------------------------
# Check G: loop.sh + breaker.sh heuristic (drift tripwire, not proof)
# ---------------------------------------------------------------------------
check_g() {
  local sh="skills/agent-kit/templates/loop/loop.sh"
  local brk_sh="skills/agent-kit/templates/loop/breaker.sh"
  local sentinel='<promise>COMPLETE</promise>'
  local bad=() f n sh_default

  if [[ ! -f "$sh" ]]; then
    bad+=("$sh: file not found")
  else
    grep -qF "$sentinel" "$sh" || bad+=("$sh: missing sentinel string")
    for n in 0 1 2 3 4 5; do
      grep -qE "exit $n([^0-9]|\$)" "$sh" || bad+=("$sh: missing exit $n")
    done
    sh_default="$(grep -oE '\{1:-[0-9]+\}' "$sh" 2>/dev/null | grep -oE '[0-9]+\}' | tr -d '}')"
    if [[ -z "$sh_default" ]]; then
      bad+=("$sh: no default iteration count found")
    elif [[ "$sh_default" != "10" ]]; then
      bad+=("$sh: default iteration count is $sh_default, expected 10")
    fi
  fi

  if [[ ! -f "$brk_sh" ]]; then
    bad+=("$brk_sh: file not found")
  else
    grep -qF "CLOSED" "$brk_sh" || bad+=("$brk_sh: missing state name CLOSED")
    grep -qF "OPEN" "$brk_sh" || bad+=("$brk_sh: missing state name OPEN")
    grep -qF "HALF-OPEN" "$brk_sh" || bad+=("$brk_sh: missing state name HALF-OPEN")
    grep -qF "600" "$brk_sh" || bad+=("$brk_sh: missing cooldown literal 600")
    grep -qE '_BRK_HALF[^0-9]*==[^0-9]*2' "$brk_sh" || \
      bad+=("$brk_sh: successes threshold _BRK_HALF == 2 transition not found")
  fi

  if ((${#bad[@]})); then
    report FAIL "G: loop driver heuristic (bash)" "${#bad[@]} issue(s)"
    printf '%s\n' "${bad[@]}" >&2
  else
    report PASS "G: loop driver heuristic (bash)"
  fi
}

# ---------------------------------------------------------------------------
# Check H: loop.cmd reference coverage; loop.ps1 must not appear
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
    elif ! grep -qF 'loop.cmd' "$f"; then
      missing+=("$f: no mention of loop.cmd")
    elif grep -qF 'loop.ps1' "$f"; then
      missing+=("$f: must not mention loop.ps1")
    fi
  done
  if ((${#missing[@]})); then
    report FAIL "H: loop.cmd reference coverage" "${#missing[@]} file(s) wrong"
    printf '%s\n' "${missing[@]}" >&2
  else
    report PASS "H: loop.cmd reference coverage"
  fi
}

# ---------------------------------------------------------------------------
# Check I: breaker.ps1 must not appear in emitter docs
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
    elif grep -qF 'breaker.ps1' "$f"; then
      missing+=("$f: must not mention breaker.ps1")
    fi
  done
  if ((${#missing[@]})); then
    report FAIL "I: no breaker.ps1 in emitters" "${#missing[@]} file(s) mention breaker.ps1"
    printf '%s\n' "${missing[@]}" >&2
  else
    report PASS "I: no breaker.ps1 in emitters"
  fi
}

# ---------------------------------------------------------------------------
# Check J: manifest + seed-class hash integrity (self-excluding), the
# manifest-independent A4 regression grep over _loop/loop.sh and
# _loop/breaker.sh, and the kitVersion==VERSION tripwire. Three independently gated
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
    if path == "tests/agent-kit/checks.sh":
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
      "_loop/breaker.sh"
    )
    local f a4_bad=()
    for f in "${a4_targets[@]}"; do
      if [[ ! -f "$f" ]]; then
        a4_bad+=("$f: file not found")
      elif head -n 20 "$f" | grep -qF 'skills/agent-kit/templates'; then
        a4_bad+=("$f: header (first 20 lines) contains 'skills/agent-kit/templates' (A4 regression)")
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
# Check M: no .claude/ path reference exists under .cursor/ (excluding the
# self-install compiler copy at .cursor/skills/agent-kit/) -- plain ignore-blind
# grep -r, matching check B's existing idiom (never rg, which would honor
# .gitignore and pass vacuously on the gitignored .cursor/ tree). No
# carve-outs: any `.claude/` reference under .cursor/ (skills/agents/rules
# pointing at `.claude/skills/...`, `.claude/agents/...`,
# `.claude/ORCHESTRATION.md`, etc.) is real cross-contamination and FAILs.
# Exclusion is anchored to the .cursor/skills/agent-kit/ subtree specifically
# (not "any directory named setup" anywhere).
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
# Check O: emitter parse — bash -n of skills/agent-kit/bin/emit.sh.
# ---------------------------------------------------------------------------
check_o() {
  local out
  if [[ ! -f skills/agent-kit/bin/emit.sh ]]; then
    report FAIL "O: emit.sh bash -n" "skills/agent-kit/bin/emit.sh not found"
  elif out="$(bash -n skills/agent-kit/bin/emit.sh 2>&1)"; then
    report PASS "O: emit.sh bash -n"
  else
    report FAIL "O: emit.sh bash -n" "$out"
  fi
}

# ---------------------------------------------------------------------------
# Check P: instance Windows launchers present; retired .ps1 twins absent.
# ---------------------------------------------------------------------------
check_p() {
  local bad=()
  [[ -f _kit/memory.cmd ]] || bad+=("_kit/memory.cmd missing")
  [[ -f _kit/log-spawn.cmd ]] || bad+=("_kit/log-spawn.cmd missing")
  [[ ! -f _kit/memory.ps1 ]] || bad+=("_kit/memory.ps1 must be absent")
  [[ ! -f _kit/log-spawn.ps1 ]] || bad+=("_kit/log-spawn.ps1 must be absent (pruned on upgrade)")
  if [[ -d _loop ]]; then
    [[ -f _loop/loop.cmd ]] || bad+=("_loop/loop.cmd missing")
    [[ ! -f _loop/loop.ps1 ]] || bad+=("_loop/loop.ps1 must be absent")
    [[ ! -f _loop/breaker.ps1 ]] || bad+=("_loop/breaker.ps1 must be absent")
  fi
  if [[ -f .gitattributes ]]; then
    grep -qxF '*.cmd -text' .gitattributes || bad+=(".gitattributes missing '*.cmd -text'")
  else
    bad+=(".gitattributes missing")
  fi
  if ((${#bad[@]})); then
    report FAIL "P: instance Windows launchers (.cmd), no ps1 twins" "${bad[*]}"
  else
    report PASS "P: instance Windows launchers (.cmd), no ps1 twins"
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
check_m
check_n
check_o
check_p

echo
echo "=== checks.sh summary ==="
printf '%s\n' "${summary[@]}"
if ((fail_count)); then
  echo "RESULT: $fail_count check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
exit 0
