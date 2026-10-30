#!/usr/bin/env bash
# Guard: tests/agent-kit/run-all.sh fails a suite whose checks all skipped (zero passes, at least one
# skip) across the three summary formats in use, honours the ALL-SKIP-OK marker and the
# AGENT_KIT_ALLOW_ALL_SKIP=1 opt-out, and documents all of it in its header.
# Runs the runner (--no-install) against throwaway suites in a temp dir, selected with
# AGENT_KIT_SUITES; mutation proofs run copies of the runner under FIXTURE_TMPDIR. Never runs the
# real suites, never touches the repository or the self-installed instance. No network.
set -u

export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akrunallrules.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

RUN_ALL="$REPO_ROOT/tests/agent-kit/run-all.sh"
LOOP_WINDOWS="$REPO_ROOT/tests/agent-kit/templates/loop-windows.sh"
SUITES="$FIXTURE_TMPDIR/suites"
OUTS="$FIXTURE_TMPDIR/outs"
mkdir -p "$SUITES" "$OUTS"
assert_fixture_root "$SUITES" || exit 1

trap 'rm -rf "$FIXTURE_TMPDIR"' EXIT

pass=0
fail=0
skip=0

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *) fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

finish_suite() {
  echo
  echo "=== run-all-rules summary ==="
  echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
  if ((fail)); then
    echo "RESULT: $fail assertion(s) FAILED"
    return 1
  fi
  echo "RESULT: all assertions passed"
  return 0
}

mk_suite() { # mk_suite <name>  (suite body on stdin; exits 0 unless the body says otherwise)
  cat >"$SUITES/$1.sh"
}

# --- Throwaway suites -------------------------------------------------------------------------
# Every suite below exits 0 unless noted; only the summary line (and marker) differ.

mk_suite allskip <<'EOF'
#!/usr/bin/env bash
echo "SKIP: a"
echo "SKIP: b"
echo "SKIP: c"
echo "PASS: 0 FAIL: 0 SKIP: 3"
exit 0
EOF

mk_suite mixed <<'EOF'
#!/usr/bin/env bash
echo "PASS: a"
echo "SKIP: b"
echo "SKIP: c"
echo "PASS: 1 FAIL: 0 SKIP: 2"
exit 0
EOF

mk_suite marker <<'EOF'
#!/usr/bin/env bash
echo "SKIP: only runs on another host"
echo "ALL-SKIP-OK: nothing to run on this host"
echo "PASS: 0 FAIL: 0 SKIP: 1"
exit 0
EOF

mk_suite memwire <<'EOF'
#!/usr/bin/env bash
echo "x summary: ok=0 FAIL=0 SKIP=2"
exit 0
EOF

mk_suite sumcaps <<'EOF'
#!/usr/bin/env bash
echo "SUMMARY: pass=0 fail=0 skip=2"
exit 0
EOF

mk_suite nosummary <<'EOF'
#!/usr/bin/env bash
echo "hello from a suite with no summary line"
exit 0
EOF

# Edge shapes.
mk_suite wide <<'EOF'
#!/usr/bin/env bash
echo "PASS: 0   FAIL: 0   SKIP: 3"
exit 0
EOF

mk_suite nofailfield <<'EOF'
#!/usr/bin/env bash
echo "PASS: 0 SKIP: 2"
exit 0
EOF

mk_suite memwire-pass <<'EOF'
#!/usr/bin/env bash
echo "x summary: ok=2 FAIL=0 SKIP=1"
exit 0
EOF

mk_suite sumcaps-pass <<'EOF'
#!/usr/bin/env bash
echo "SUMMARY: pass=3 fail=0 skip=1"
exit 0
EOF

mk_suite noskips <<'EOF'
#!/usr/bin/env bash
echo "PASS: 0 FAIL: 0 SKIP: 0"
exit 0
EOF

mk_suite failing <<'EOF'
#!/usr/bin/env bash
echo "FAIL: broken"
echo "PASS: 0 FAIL: 1 SKIP: 2"
exit 1
EOF

mk_suite last-bad <<'EOF'
#!/usr/bin/env bash
echo "PASS: 4 FAIL: 0 SKIP: 0"
echo "PASS: 0 FAIL: 0 SKIP: 2"
exit 0
EOF

mk_suite last-good <<'EOF'
#!/usr/bin/env bash
echo "PASS: 0 FAIL: 0 SKIP: 2"
echo "PASS: 2 FAIL: 0 SKIP: 0"
exit 0
EOF

mk_suite crlf <<'EOF'
#!/usr/bin/env bash
printf 'PASS: 0 FAIL: 0 SKIP: 2\r\n'
exit 0
EOF

mk_suite marker-inline <<'EOF'
#!/usr/bin/env bash
echo "note: ALL-SKIP-OK: not at the start of a line"
echo "PASS: 0 FAIL: 0 SKIP: 2"
exit 0
EOF

# --- Runner helpers -----------------------------------------------------------------------------

suite_path() { # name-or-absolute-path → suite path
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$SUITES/$1.sh" ;;
  esac
}

RR_OUT=""
RR_RC=0
run_runner() { # run_runner <runner> <label> <env assignments or ""> <suite>...
  local runner="$1" label="$2" envs="$3" paths="" n
  shift 3
  for n in "$@"; do
    paths="$paths $(suite_path "$n")"
  done
  RR_OUT="$OUTS/$label.out"
  # $envs is deliberately unquoted: it holds zero or more KEY=VALUE words.
  # shellcheck disable=SC2086
  env -u AGENT_KIT_ALLOW_ALL_SKIP -u AGENT_KIT_SUITES $envs AGENT_KIT_SUITES="$paths" \
    bash "$runner" --no-install -j 2 >"$RR_OUT" 2>&1
  RR_RC=$?
}

result_line() { # suite → the runner's ok/FAIL line for it in RR_OUT
  local p
  p="$(suite_path "$1")"
  grep -E '^(ok|FAIL) ' "$RR_OUT" | grep -F -- " $p (" | head -n 1
}

classify() { # suite → ok | allskip | fail | none
  local p line
  p="$(suite_path "$1")"
  line="$(result_line "$1")"
  case "$line" in
    "ok    $p ("*) echo ok ;;
    "FAIL  $p ("*") -- all checks skipped; log: "*) echo allskip ;;
    "FAIL  $p ("*) echo fail ;;
    *) echo none ;;
  esac
}

expect() { # expect <label> <suite> <ok|allskip|fail>
  local got
  got="$(classify "$2")"
  if [ "$got" = "$3" ]; then
    report PASS "$1: $2 -> $3"
  else
    report FAIL "$1: $2" "expected $3, got $got ($(result_line "$2"))"
  fi
}

expect_rc() { # expect_rc <label> <zero|nonzero>
  if { [ "$2" = "zero" ] && [ "$RR_RC" -eq 0 ]; } || { [ "$2" = "nonzero" ] && [ "$RR_RC" -ne 0 ]; }; then
    report PASS "$1: runner exit is $2 (rc=$RR_RC)"
  else
    report FAIL "$1: runner exit" "expected $2, rc=$RR_RC"
  fi
}

expect_line() { # expect_line <label> <fixed text>
  if grep -qF -- "$2" "$RR_OUT"; then
    report PASS "$1: output has \"$2\""
  else
    report FAIL "$1: output lacks \"$2\"" "$(tr '\n' '|' <"$RR_OUT")"
  fi
}

note_count() { # → how many AGENT_KIT_ALLOW_ALL_SKIP note lines the runner printed
  grep -c '^agent-kit: note: AGENT_KIT_ALLOW_ALL_SKIP=1' "$RR_OUT" 2>/dev/null || true
}

MUT_RUNNER=""
make_mutant() { # make_mutant <name> <old fixed text> <new fixed text>; 1 when nothing changed
  local dir="$FIXTURE_TMPDIR/mut-$1"
  mkdir -p "$dir/tests/agent-kit"
  OLD="$2" NEW="$3" awk '
    BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; n = length(old) }
    {
      line = $0; out = ""
      while ((i = index(line, old)) > 0) {
        out = out substr(line, 1, i - 1) new
        line = substr(line, i + n)
        hit = 1
      }
      print out line
    }
    END { if (hit) exit 0; exit 1 }
  ' "$RUN_ALL" >"$dir/tests/agent-kit/run-all.sh" || return 1
  if cmp -s "$RUN_ALL" "$dir/tests/agent-kit/run-all.sh"; then
    return 1
  fi
  MUT_RUNNER="$dir/tests/agent-kit/run-all.sh"
  return 0
}

# --- (0) The runner exists and parses ------------------------------------------------------------
if [ -f "$RUN_ALL" ] && bash -n "$RUN_ALL" 2>/dev/null; then
  report PASS "(0) run-all.sh exists and parses"
else
  report FAIL "(0) run-all.sh exists and parses" "$RUN_ALL"
  finish_suite
  exit 1
fi

# --- (A) The six suites named by the rule, default environment ----------------------------------
SIX="allskip mixed marker memwire sumcaps nosummary"
# shellcheck disable=SC2086
run_runner "$RUN_ALL" six-default "" $SIX
expect "(A) default" allskip allskip
expect "(A) default" mixed ok
expect "(A) default" marker ok
expect "(A) default" memwire allskip
expect "(A) default" sumcaps allskip
expect "(A) default" nosummary ok
expect_rc "(A) default" nonzero
expect_line "(A) default" "agent-kit: 3/6 suite(s) ok"
expect_line "(A) default" "agent-kit: 3 suite(s) failed"
if [ "$(note_count)" = "0" ]; then
  report PASS "(A) default: no opt-out note printed"
else
  report FAIL "(A) default: opt-out note printed without the variable set"
fi
a_line="$(result_line allskip)"
a_log="${a_line##*log: }"
if [ -f "$a_log" ] && grep -qF 'SKIP: 3' "$a_log"; then
  report PASS "(A) default: allskip line names its log, which holds the summary"
else
  report FAIL "(A) default: allskip log path" "line=[$a_line] log=[$a_log]"
fi

# The exit code on its own: one all-skip suite fails the run, one mixed suite does not.
run_runner "$RUN_ALL" allskip-alone "" allskip
expect_rc "(A) allskip alone" nonzero
expect_line "(A) allskip alone" "agent-kit: 1 suite(s) failed"
run_runner "$RUN_ALL" mixed-alone "" mixed
expect_rc "(A) mixed alone" zero
expect_line "(A) mixed alone" "agent-kit: 1 suite(s) passed"

# --- (B) Opt-out: AGENT_KIT_ALLOW_ALL_SKIP=1 ------------------------------------------------------
# shellcheck disable=SC2086
run_runner "$RUN_ALL" six-allow "AGENT_KIT_ALLOW_ALL_SKIP=1" $SIX
for n in $SIX; do
  expect "(B) AGENT_KIT_ALLOW_ALL_SKIP=1" "$n" ok
done
expect_rc "(B) AGENT_KIT_ALLOW_ALL_SKIP=1" zero
expect_line "(B) AGENT_KIT_ALLOW_ALL_SKIP=1" "agent-kit: 6 suite(s) passed"
if [ "$(note_count)" = "1" ]; then
  report PASS "(B) AGENT_KIT_ALLOW_ALL_SKIP=1: exactly one note line"
else
  report FAIL "(B) AGENT_KIT_ALLOW_ALL_SKIP=1: note line count" "got $(note_count)"
fi

# Only the value 1 opts out.
# shellcheck disable=SC2086
run_runner "$RUN_ALL" six-allow0 "AGENT_KIT_ALLOW_ALL_SKIP=0" $SIX
expect "(B) AGENT_KIT_ALLOW_ALL_SKIP=0" allskip allskip
expect "(B) AGENT_KIT_ALLOW_ALL_SKIP=0" memwire allskip
expect_rc "(B) AGENT_KIT_ALLOW_ALL_SKIP=0" nonzero
if [ "$(note_count)" = "0" ]; then
  report PASS "(B) AGENT_KIT_ALLOW_ALL_SKIP=0: no note line"
else
  report FAIL "(B) AGENT_KIT_ALLOW_ALL_SKIP=0: note line printed"
fi

# --- (C) Edge shapes, default environment ---------------------------------------------------------
EDGE_OK="mixed marker nosummary memwire-pass sumcaps-pass noskips last-good"
EDGE_ALLSKIP="allskip memwire sumcaps wide nofailfield last-bad crlf marker-inline"
EDGE_FAIL="failing"
# shellcheck disable=SC2086
run_runner "$RUN_ALL" edge-default "" $EDGE_OK $EDGE_ALLSKIP $EDGE_FAIL
for n in $EDGE_OK; do
  expect "(C) edge" "$n" ok
done
for n in $EDGE_ALLSKIP; do
  expect "(C) edge" "$n" allskip
done
for n in $EDGE_FAIL; do
  expect "(C) edge" "$n" fail
done
n_ok=0
n_all=0
for n in $EDGE_OK; do n_ok=$((n_ok + 1)); n_all=$((n_all + 1)); done
for n in $EDGE_ALLSKIP $EDGE_FAIL; do n_all=$((n_all + 1)); done
expect_line "(C) edge" "agent-kit: ${n_ok}/${n_all} suite(s) ok"
expect_rc "(C) edge" nonzero

# The opt-out never hides a suite that really failed.
# shellcheck disable=SC2086
run_runner "$RUN_ALL" edge-allow "AGENT_KIT_ALLOW_ALL_SKIP=1" $EDGE_OK $EDGE_ALLSKIP
for n in $EDGE_ALLSKIP; do
  expect "(C) edge, opt-out" "$n" ok
done
expect_rc "(C) edge, opt-out" zero
run_runner "$RUN_ALL" failing-allow "AGENT_KIT_ALLOW_ALL_SKIP=1" failing
expect "(C) failing suite, opt-out" failing fail
expect_rc "(C) failing suite, opt-out" nonzero

# --- (D) The real loop-windows suite (intentional all-skip off Windows) ---------------------------
case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) ON_WINDOWS=1 ;;
  *) ON_WINDOWS=0 ;;
esac
if [ "$ON_WINDOWS" -eq 0 ]; then
  lw_out="$OUTS/loop-windows.direct.out"
  bash "$LOOP_WINDOWS" >"$lw_out" 2>&1
  lw_rc=$?
  if [ "$lw_rc" -eq 0 ] && grep -qE '^ALL-SKIP-OK: ' "$lw_out"; then
    report PASS "(D) loop-windows.sh prints ALL-SKIP-OK: and exits 0 off Windows"
  else
    report FAIL "(D) loop-windows.sh marker" "rc=$lw_rc out=$(tr '\n' '|' <"$lw_out")"
  fi
  if grep -qE '^PASS: 0 +FAIL: 0 +SKIP: [1-9]' "$lw_out"; then
    report PASS "(D) loop-windows.sh summary is an all-skip (the marker is what exempts it)"
  else
    report FAIL "(D) loop-windows.sh summary" "$(tr '\n' '|' <"$lw_out")"
  fi
  run_runner "$RUN_ALL" loop-windows "" "$LOOP_WINDOWS"
  expect "(D) runner" "$LOOP_WINDOWS" ok
  expect_rc "(D) runner" zero
else
  report SKIP "(D) loop-windows marker" "Windows host: the suite runs its real cases"
fi

# --- (E) Mutation proofs: each rule's code must be what produces its verdict ----------------------
# Each mutant is a copy of run-all.sh with one fragment changed (the mutation is asserted to apply),
# run against the same throwaway suites as the real runner above.

# E1: the zero-pass-and-one-skip threshold. Without it every all-skip suite is "ok".
if make_mutant threshold '"$ras_s" -ge 1' '"$ras_s" -ge 999999'; then
  run_runner "$MUT_RUNNER" mut-threshold "" allskip memwire sumcaps mixed
  expect "(E1) mutant without the skip threshold" allskip ok
  expect "(E1) mutant without the skip threshold" memwire ok
  expect "(E1) mutant without the skip threshold" sumcaps ok
  expect "(E1) mutant without the skip threshold" mixed ok
else
  report FAIL "(E1) mutant did not apply" "fragment not found in run-all.sh"
fi

# E2: the ALL-SKIP-OK marker exemption.
if make_mutant marker "ALL-SKIP-OK:' \"\$log\"" "NO-SUCH-MARKER:' \"\$log\""; then
  run_runner "$MUT_RUNNER" mut-marker "" marker allskip mixed
  expect "(E2) mutant without the marker exemption" marker allskip
  expect "(E2) mutant without the marker exemption" allskip allskip
  expect "(E2) mutant without the marker exemption" mixed ok
  if [ "$ON_WINDOWS" -eq 0 ]; then
    run_runner "$MUT_RUNNER" mut-marker-lw "" "$LOOP_WINDOWS"
    expect "(E2) mutant without the marker exemption" "$LOOP_WINDOWS" allskip
  fi
else
  report FAIL "(E2) mutant did not apply" "fragment not found in run-all.sh"
fi

# E3: the opt-out. The note line and the rule's own check both read the variable.
if make_mutant optout '"${AGENT_KIT_ALLOW_ALL_SKIP:-}" = "1"' '"${AGENT_KIT_ALLOW_ALL_SKIP:-}" = "never"'; then
  run_runner "$MUT_RUNNER" mut-optout "AGENT_KIT_ALLOW_ALL_SKIP=1" allskip memwire sumcaps
  expect "(E3) mutant without the opt-out" allskip allskip
  expect "(E3) mutant without the opt-out" memwire allskip
  expect "(E3) mutant without the opt-out" sumcaps allskip
  expect_rc "(E3) mutant without the opt-out" nonzero
else
  report FAIL "(E3) mutant did not apply" "fragment not found in run-all.sh"
fi

# E4: the "PASS: <p> ... SKIP: <s>" format.
if make_mutant fmt-pass '/^[ \t]*PASS:[ \t]*[0-9]+(' '/^[ \t]*PASX:[ \t]*[0-9]+('; then
  run_runner "$MUT_RUNNER" mut-fmt-pass "" allskip wide nofailfield memwire
  expect "(E4) mutant without the PASS: format" allskip ok
  expect "(E4) mutant without the PASS: format" wide ok
  expect "(E4) mutant without the PASS: format" nofailfield ok
  expect "(E4) mutant without the PASS: format" memwire allskip
else
  report FAIL "(E4) mutant did not apply" "fragment not found in run-all.sh"
fi

# E5: the "summary: ok=<p> FAIL=<f> SKIP=<s>" format.
if make_mutant fmt-ok '/summary: ok=[0-9]+[ \t]+FAIL=' '/summary: nope=[0-9]+[ \t]+FAIL='; then
  run_runner "$MUT_RUNNER" mut-fmt-ok "" memwire allskip sumcaps
  expect "(E5) mutant without the summary: ok= format" memwire ok
  expect "(E5) mutant without the summary: ok= format" allskip allskip
  expect "(E5) mutant without the summary: ok= format" sumcaps allskip
else
  report FAIL "(E5) mutant did not apply" "fragment not found in run-all.sh"
fi

# E6: the "SUMMARY: pass=<p> fail=<f> skip=<s>" format.
if make_mutant fmt-caps '/^[ \t]*SUMMARY:[ \t]*pass=' '/^[ \t]*SUMMARY:[ \t]*nope='; then
  run_runner "$MUT_RUNNER" mut-fmt-caps "" sumcaps allskip memwire
  expect "(E6) mutant without the SUMMARY: pass= format" sumcaps ok
  expect "(E6) mutant without the SUMMARY: pass= format" allskip allskip
  expect "(E6) mutant without the SUMMARY: pass= format" memwire allskip
else
  report FAIL "(E6) mutant did not apply" "fragment not found in run-all.sh"
fi

# E7: the verdict only applies to a suite that exited 0. The real runner leaves the failing suite
# with its plain FAIL line; a mutant that also applies the verdict to exit code 1 relabels it.
if make_mutant rc-gate 'if [ "$rc" = "0" ]; then' 'if [ "$rc" = "0" ] || [ "$rc" = "1" ]; then'; then
  run_runner "$MUT_RUNNER" mut-rc-gate "" failing
  expect "(E7) mutant that applies the verdict to rc=1 as well" failing allskip
else
  report FAIL "(E7) mutant did not apply" "fragment not found in run-all.sh"
fi

# --- (F) The header documents the rule, the marker, the opt-out and the selection variable -------
header_documents() { # header_documents <file> → 0 when the comment header names all four
  local head t
  head="$(awk '/^set -u/ { exit } { print }' "$1")"
  for t in 'all checks skipped' 'ALL-SKIP-OK' 'AGENT_KIT_ALLOW_ALL_SKIP' 'AGENT_KIT_SUITES'; do
    case "$head" in
      *"$t"*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}
if header_documents "$RUN_ALL"; then
  report PASS "(F) run-all.sh header documents the rule, marker, opt-out and AGENT_KIT_SUITES"
else
  report FAIL "(F) run-all.sh header documentation"
fi
awk '/^set -u/ { f = 1 } f { print }' "$RUN_ALL" >"$FIXTURE_TMPDIR/run-all.noheader.sh"
if header_documents "$FIXTURE_TMPDIR/run-all.noheader.sh"; then
  report FAIL "(F) header check passes on a header-stripped copy"
else
  report PASS "(F) header check fails on a header-stripped copy"
fi

finish_suite
