#!/usr/bin/env bash
# Guard: skills/agent-kit/bin/emit.sh emitter speed (fork hot-path patterns removed).
#
# Default: cheap structural checks + in-suite mutation proofs (no timing, no strace).
# Case (c): one pwsh launch site in verify_all (pattern: pwsh[[:space:]]+-), never inside loops.
# Opt-in: EMIT_PERF=1 runs three timed self-answers emits (median wall clock) and,
# when strace works, a fork-budget check.
#
# Environment:
#   EMIT_PERF=1              Enable timing + fork-budget cases (default: skip both).
#   EMIT_PERF_MAX=4.0        Max median seconds for self-answers emit (positive decimal).
#   EMIT_PERF_MAX_FORKS=589  Max clone+clone3+fork+vfork count (positive integer).
#                            Default ceil(471 * 1.25) = 589; measured base:
#                            clone=450 clone3=21 forks_total=471 execve=193.
#
# Usage: bash tests/agent-kit/templates/emit-perf.sh
#        EMIT_PERF=1 bash tests/agent-kit/templates/emit-perf.sh
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/emitperf.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

CANON_EMIT="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
EMIT_SH="${EMIT_SH:-$CANON_EMIT}"
KIT="$REPO_ROOT/skills/agent-kit"
ANSWERS="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

EMIT_PERF_MAX="${EMIT_PERF_MAX:-4.0}"
# EMIT_PERF_MAX_FORKS: ceil(471 * 1.25) = 589 (clone=450 clone3=21 forks_total=471 execve=193)
EMIT_PERF_MAX_FORKS="${EMIT_PERF_MAX_FORKS:-589}"

pass=0
fail=0
skip=0

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2${3:+ -- $3}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $2${3:+ -- $3}" ;;
    *) fail=$((fail + 1)); echo "FAIL: $2${3:+ -- $3}" >&2 ;;
  esac
}

_suite_cleanup() {
  rm -rf "$FIXTURE_TMPDIR"
}
trap _suite_cleanup EXIT

usage_perf_env() {
  printf 'usage: EMIT_PERF=1 [EMIT_PERF_MAX=4.0] [EMIT_PERF_MAX_FORKS=589] %s\n' \
    "bash tests/agent-kit/templates/emit-perf.sh"
}

valid_positive_decimal() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  awk -v x="$v" 'BEGIN { exit !(x + 0 > 0) }'
}

valid_positive_int() {
  local v="$1"
  [[ "$v" =~ ^[1-9][0-9]*$ ]]
}

emit_mut_test() {
  local sedscript="$1" name="$2" canon_fn="$3" expect_n="${4:-}" expect_detail="${5:-}" expect_added="${6:-}"
  local mutsh canon_rc mut_rc changed="" added="" mut_out="" saved_emit="$EMIT_SH"
  mutsh="$(mktemp "$FIXTURE_TMPDIR/emitmut.XXXXXX")"
  sed "$sedscript" "$CANON_EMIT" > "$mutsh"
  chmod +x "$mutsh"
  if [[ -n "$expect_n" ]] || [[ -n "$expect_added" ]]; then
    changed="$(diff -u "$CANON_EMIT" "$mutsh" 2>/dev/null | tail -n +3 | grep -c '^-' || true)"
    added="$(diff -u "$CANON_EMIT" "$mutsh" 2>/dev/null | tail -n +3 | grep -c '^+' || true)"
    if [[ -n "$expect_n" ]] && [[ "$changed" -ne "$expect_n" ]]; then
      report FAIL "mutation-$name" "sed removed/changed $changed line(s), expected $expect_n (added $added)"
      rm -f "$mutsh"
      return
    fi
    if [[ -n "$expect_added" ]] && [[ "$added" -ne "$expect_added" ]]; then
      report FAIL "mutation-$name" "sed added $added line(s), expected $expect_added (removed/changed $changed)"
      rm -f "$mutsh"
      return
    fi
  fi
  if ! bash -n "$mutsh" 2>/dev/null; then
    report FAIL "mutation-$name" "mutant bash -n syntax error"
    rm -f "$mutsh"
    return
  fi
  set +e
  EMIT_SH="$CANON_EMIT" "$canon_fn" >/dev/null 2>&1; canon_rc=$?
  mut_out="$(EMIT_SH="$mutsh" "$canon_fn" 2>&1)"; mut_rc=$?
  EMIT_SH="$saved_emit"
  rm -f "$mutsh"
  if [[ "$canon_rc" -ne 0 ]]; then
    report FAIL "mutation-$name" "canonical rc=$canon_rc (expected 0)"
  elif [[ "$mut_rc" -ne 1 ]]; then
    report FAIL "mutation-$name" "mutant rc=$mut_rc (expected exactly 1 = target assertion failed; 0 = mutation not caught)"
  elif [[ -n "$expect_detail" ]] && [[ "$mut_out" != *"$expect_detail"* ]]; then
    report FAIL "mutation-$name" "mutant detail missing '$expect_detail' (got: $mut_out)"
  else
    report PASS "mutation-$name: canonical rc=0, mutant rc=1 (target assertion failed; bash -n ok${expect_n:+, sed changed $changed line(s)}${expect_added:+, sed added $added line(s)}${expect_detail:+, detail contains '$expect_detail'})"
  fi
}

grep_offenders() {
  local pattern="$1" file="$2"
  grep -nE "$pattern" "$file" 2>/dev/null || true
}

# --- structural checks (rc 0 ok, 1 target fail) ---

struct_a_no_index_of_cmdsub() {
  local hit
  hit="$(grep_offenders '\$\(index_of ' "$EMIT_SH")"
  if [[ -n "$hit" ]]; then
    printf '%s\n' "$hit" >&2
    return 1
  fi
  return 0
}

struct_b_no_awk_end_nr() {
  local hit
  hit="$(grep_offenders "awk 'END\\{print NR\\}'" "$EMIT_SH")"
  if [[ -n "$hit" ]]; then
    printf '%s\n' "$hit" >&2
    return 1
  fi
  return 0
}

struct_c_pwsh_verify_all() {
  awk '
    BEGIN { in_fn = 0; fn_depth = 0; loop_depth = 0; pending_do = 0; seen_fn = 0; launch_n = 0; err = 0 }
    # launch_nr[i] = emit.sh line number of pwsh launch site i
    /^verify_all\(\) \{/ { in_fn = 1; seen_fn = 1 }
    in_fn {
      line = $0
      nr = NR
      if (pending_do && line ~ /^[[:space:]]*do([[:space:];<>|&)]|$)/) {
        loop_depth++
        pending_do = 0
      }
      if (line ~ /(^|[;&|[:space:]])(for|while|until)[[:space:]]/) {
        if (line ~ /[[:space:]]do([[:space:];<>|&)]|$)/) {
          loop_depth++
        } else {
          pending_do = 1
        }
      }
      if (line ~ /(^|[^[:alnum:]_-])pwsh[[:space:]]+-/) {
        launch_n++
        launch_nr[launch_n] = nr
        if (loop_depth > 0) {
          printf "%d: pwsh launch inside loop in verify_all\n", nr > "/dev/stderr"
          err = 1
        }
      }
      if (line ~ /(^|[;[:space:]])done([[:space:];<>|&)]|$)/) {
        if (loop_depth > 0) {
          loop_depth--
        }
        pending_do = 0
      }
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "{") {
          fn_depth++
        } else if (c == "}") {
          fn_depth--
        }
      }
      if (fn_depth <= 0) {
        in_fn = 0
      }
    }
    END {
      if (!seen_fn) {
        print "verify_all() not found" > "/dev/stderr"
        exit 1
      }
      if (launch_n > 1) {
        for (i = 1; i <= launch_n; i++) {
          printf "%d: pwsh launch site in verify_all\n", launch_nr[i] > "/dev/stderr"
        }
        print "expected at most one pwsh launch in verify_all, got " launch_n > "/dev/stderr"
        err = 1
      }
      exit (err ? 1 : 0)
    }
  ' "$EMIT_SH"
}

struct_d1_no_basename_cmdsub() {
  local hit
  hit="$(grep_offenders '\$\(basename ' "$EMIT_SH")"
  if [[ -n "$hit" ]]; then
    printf '%s\n' "$hit" >&2
    return 1
  fi
  return 0
}

struct_d2_no_awk_sha256_field() {
  local hit
  hit="$(grep -nF '| awk '"'"'{print $1}'"'"'' "$EMIT_SH" 2>/dev/null || true)"
  if [[ -n "$hit" ]]; then
    printf '%s\n' "$hit" >&2
    return 1
  fi
  return 0
}

struct_d3_no_template_stage_cmdsub() {
  local hit
  hit="$(grep_offenders '\$\(resolve_if |\$\(bootstrap_apply|\$\(replace_tokens' "$EMIT_SH")"
  if [[ -n "$hit" ]]; then
    printf '%s\n' "$hit" >&2
    return 1
  fi
  return 0
}

run_struct() {
  local label="$1"
  shift
  local detail="" rc
  set +e
  detail="$("$@" 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    report PASS "$label"
  else
    report FAIL "$label" "$detail"
  fi
}

mut_a() { struct_a_no_index_of_cmdsub; }
mut_b() { struct_b_no_awk_end_nr; }
mut_c() { struct_c_pwsh_verify_all; }
mut_d1() { struct_d1_no_basename_cmdsub; }
mut_d2() { struct_d2_no_awk_sha256_field; }
mut_d3() { struct_d3_no_template_stage_cmdsub; }
mut_d3_bootstrap() { struct_d3_no_template_stage_cmdsub; }
mut_d3_replace() { struct_d3_no_template_stage_cmdsub; }

measure_emit_once() {
  local d t rc
  d="$(mktemp -d "$FIXTURE_TMPDIR/perfroot.XXXXXX")" || return 2
  assert_fixture_root "$d" || return 2
  git -C "$d" init -q || return 2
  TIMEFORMAT=%R
  t="$( { time bash "$CANON_EMIT" --root "$d" --kit "$KIT" --answers "$ANSWERS" >/dev/null 2>&1; } 2>&1 )"
  rc=$?
  rm -rf "$d"
  [[ "$rc" -eq 0 ]] || return 2
  printf '%s' "$t"
}

strace_fork_total() {
  local d sf total rc
  d="$(mktemp -d "$FIXTURE_TMPDIR/strace.XXXXXX")" || return 2
  assert_fixture_root "$d" || return 2
  git -C "$d" init -q || return 2
  sf="$(mktemp "$FIXTURE_TMPDIR/straceout.XXXXXX")"
  strace -f -c -e trace=clone,clone3,fork,vfork,execve -o "$sf" \
    bash "$CANON_EMIT" --root "$d" --kit "$KIT" --answers "$ANSWERS" >/dev/null 2>&1
  rc=$?
  total="$(awk '$NF ~ /^(clone|clone3|fork|vfork)$/ { c += $4 + 0 } END { print c + 0 }' "$sf")"
  rm -rf "$d" "$sf"
  [[ "$rc" -eq 0 ]] || return 2
  printf '%s' "$total"
}

strace_usable() {
  command -v strace >/dev/null 2>&1 || return 1
  strace -f -c -o /dev/null true >/dev/null 2>&1
}

# --- always-on structural cases ---
run_struct '(a) no index_of command substitution' struct_a_no_index_of_cmdsub
emit_mut_test 's/index_of_into idx "\$hay" "\$needle"/idx="$(index_of "$hay" "$needle")"/' \
  'a-index-of-cmdsub' mut_a 1

run_struct '(b) no awk END{print NR} pipeline' struct_b_no_awk_end_nr
emit_mut_test 's/nr=\$((nl + 1))/nr="$(printf '"'"'%s'"'"' "$s" | awk '"'"'END{print NR}'"'"')"/' \
  'b-awk-end-nr' mut_b 1

run_struct '(c) pwsh verify_all single launch not inside loops' struct_c_pwsh_verify_all
emit_mut_test \
  '/^verify_all() {$/,/^}$/{
s/ps1_out="\$(pwsh -NoProfile -Command /ps1_out="$(: -NoProfile -Command /
s/            \[ -z "\$abs" \] && continue/            pwsh -NoProfile -Command "exit 0" >\/dev\/null 2>\&1 || true; [ -z "$abs" ] \&\& continue/
}' \
  'c-loop-while' mut_c 2 'inside loop'
emit_mut_test \
  '/^        export PS1_VERIFY_LIST$/a\
        pwsh -NoProfile -Command "exit 0" >/dev/null 2>&1 || true' \
  'c-count-second' mut_c '' 'at most one' 1
emit_mut_test \
  '/^verify_all() {$/a\
  for _ep_mut in x\
  do\
    pwsh -NoProfile -Command "exit 0" >\/dev\/null 2>\&1 || true\
  done' \
  'c-for-nextline-do' mut_c '' 'inside loop' 4

run_struct '(d1) no basename command substitution' struct_d1_no_basename_cmdsub
emit_mut_test 's@expected="\${p##\*/}"@expected="$(basename "$p")"@' \
  'd1-basename-cmdsub' mut_d1 1

run_struct '(d2) no awk print-first-field sha256 parsing' struct_d2_no_awk_sha256_field
emit_mut_test 's@  h="\$(printf '"'"'%s'"'"' "\$2" | \$SHA256_CMD | sha256_digest_field)"@  h="$(printf '"'"'%s'"'"' "$2" | $SHA256_CMD | awk '"'"'{print $1}'"'"')"@' \
  'd2-awk-sha256' mut_d2 1

run_struct '(d3) no resolve_if bootstrap replace_tokens cmdsub' struct_d3_no_template_stage_cmdsub
emit_mut_test 's/resolve_if_into content "\$content" "\$rel"/content="$(resolve_if "$content" "$rel")"/' \
  'd3-resolve-if-cmdsub' mut_d3 1
emit_mut_test \
  's/_bootstrap_apply_with_bs_into stripped "\$content" "\$rel" strip/stripped="$(bootstrap_apply "$content" "$rel")"/' \
  'd3-bootstrap-cmdsub' mut_d3_bootstrap 1
emit_mut_test 's/replace_tokens_into content "\$content"/content="$(replace_tokens "$content")"/' \
  'd3-replace-tokens-cmdsub' mut_d3_replace 1

# --- opt-in performance ---
if [[ "${EMIT_PERF:-0}" = 1 ]]; then
  if ! valid_positive_decimal "$EMIT_PERF_MAX"; then
    report FAIL "EMIT_PERF_MAX" "$(usage_perf_env)"
  elif ! valid_positive_int "$EMIT_PERF_MAX_FORKS"; then
    report FAIL "EMIT_PERF_MAX_FORKS" "$(usage_perf_env)"
  else
    t1=""
    t2=""
    t3=""
    med=""
    for i in 1 2 3; do
      t="$(measure_emit_once)" || t=""
      if [[ -z "$t" ]]; then
        report FAIL "(perf) emit self-answers timing" "measure run $i failed"
        t1=""; break
      fi
      case "$i" in
        1) t1="$t" ;;
        2) t2="$t" ;;
        3) t3="$t" ;;
      esac
    done
    if [[ -n "$t1" && -n "$t2" && -n "$t3" ]]; then
      med="$(printf '%s\n' "$t1" "$t2" "$t3" | LC_ALL=C sort -n | sed -n '2p')"
      if awk -v m="$med" -v max="$EMIT_PERF_MAX" 'BEGIN { exit !(m + 0 <= max + 0) }'; then
        report PASS "(perf) emit self-answers timing" "times=${t1},${t2},${t3} median=${med} max=${EMIT_PERF_MAX}"
      else
        report FAIL "(perf) emit self-answers timing" "times=${t1},${t2},${t3} median=${med} max=${EMIT_PERF_MAX}"
      fi
    fi

    if strace_usable; then
      forks="$(strace_fork_total)" || forks=""
      if [[ -z "$forks" ]]; then
        report FAIL "(perf) emit fork budget" "strace run failed"
      elif [[ "$forks" -le "$EMIT_PERF_MAX_FORKS" ]]; then
        report PASS "(perf) emit fork budget" "forks=${forks} max=${EMIT_PERF_MAX_FORKS}"
      else
        report FAIL "(perf) emit fork budget" "forks=${forks} max=${EMIT_PERF_MAX_FORKS}"
      fi
    else
      report SKIP "(perf) emit fork budget" "strace not available"
    fi
  fi
else
  report SKIP "(perf) emit self-answers timing" "EMIT_PERF not set"
  report SKIP "(perf) emit fork budget" "EMIT_PERF not set"
fi

echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
