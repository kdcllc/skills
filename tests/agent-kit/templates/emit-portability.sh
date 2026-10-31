#!/usr/bin/env bash
# Guard: emit.sh portability (jq-free PATH, sha256 tools, Bash 3.2 docker, JSON edges).
# AGENT_KIT_DOCKER=1 opt-in runs the bash:3.2 docker emit-golden check; default skips it.
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

printf 'bash: %s\n' "$BASH_VERSION"

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/emitport.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

. "$HERE/../lib/emit-cache.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
case "$EMIT_SH" in /*) ;; *) EMIT_SH="$REPO_ROOT/$EMIT_SH" ;; esac
KIT="$REPO_ROOT/skills/agent-kit"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"
EDGE_PROBE_JSON='{"zz":1,"ascii":"\b\f\/|\u007f|\u0000|\u001f|\"\\|\n\t\r","utf8":"\u00e9|\u20ac|\ud83c\udfad|\udc00x|\u0080|\u07ff|\u0800|\uffff|\ud800\udc00|\udbff\udfff","keys":{"":0,"a\tb":1,"\u00e9":2,"b":3,"B":4,"\ud83c\udfad":5},"empty":{"o":{},"a":[]},"nested":[{"k":[{"x":1,"w":[]},[]]},[[],{}],null,true,false],"nums":[-0,1.0,1e20,-1.5e-7,12345678901234567890,0.1,100,1E2,-0.0,1e1000]}'

pass=0
fail=0
skip=0
RUN_TMP=""
PATH_FARM_DIRS=""

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

_suite_cleanup() {
  local d
  for d in ${PATH_FARM_DIRS}; do
    [ -z "$d" ] && continue
    rm -rf "$d"
  done
  emit_cache_cleanup
  [ -n "$RUN_TMP" ] && rm -rf "$RUN_TMP"
}
trap _suite_cleanup EXIT

RUN_TMP="$FIXTURE_TMPDIR"

mktemp_root() {
  local d
  d="$(mktemp -d "$RUN_TMP/root.XXXXXX")" || exit 1
  assert_fixture_root "$d" || exit 1
  printf '%s' "$d"
}

mktemp_file() {
  local f
  f="$(mktemp "$RUN_TMP/file.XXXXXX")" || exit 1
  printf '%s' "$f"
}

run_emit() {
  assert_fixture_root "$1" || exit 1
  "$BASH" "$EMIT_SH" --root "$1" --kit "$KIT" "${@:2}"
}

path_without() { # cmd...
  local entry farm f base cmd hit result="" old="$PATH" rest
  rest="$old"
  while [ -n "$rest" ]; do
    if [ "${rest#*:}" != "$rest" ]; then
      entry="${rest%%:*}"
      rest="${rest#*:}"
    else
      entry="$rest"
      rest=""
    fi
    [ -n "$entry" ] || continue
    hit=0
    for cmd in "$@"; do
      if [ -e "$entry/$cmd" ] || [ -e "$entry/$cmd.exe" ]; then hit=1; fi
    done
    if [ "$hit" -eq 1 ]; then
      farm="$(mktemp -d "$RUN_TMP/pwf.XXXXXX")" || exit 1
      assert_fixture_root "$farm" || exit 1
      PATH_FARM_DIRS="${PATH_FARM_DIRS} ${farm}"
      for f in "$entry"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        for cmd in "$@"; do
          [ "$base" = "$cmd" ] && continue 2
          [ "$base" = "$cmd.exe" ] && continue 2
        done
        ln -s "$f" "$farm/$base" 2>/dev/null || cp -f "$f" "$farm/$base"
      done
      result="${result:+$result:}$farm"
    else
      result="${result:+$result:}$entry"
    fi
  done
  printf '%s' "$result"
}


edge_expected() {
  local t
  t="$(cat <<'EDGE_EOF'
    "zzedge_probe": {
      "ascii": "\b\f/|\u007f|\u0000|\u001f|\"\\|\n\t\r",
      "empty": {
        "a": [],
        "o": {}
      },
      "keys": {
        "": 0,
        "B": 4,
        "a\tb": 1,
        "b": 3,
        "{U+00E9}": 2,
        "{U+1F3AD}": 5
      },
      "nested": [
        {
          "k": [
            {
              "w": [],
              "x": 1
            },
            []
          ]
        },
        [
          [],
          {}
        ],
        null,
        true,
        false
      ],
      "nums": [
        -0,
        1,
        1e+20,
        -1.5e-07,
        12345678901234567000,
        0.1,
        100,
        100,
        -0,
        1.7976931348623157e+308
      ],
      "utf8": "{U+00E9}|{U+20AC}|{U+1F3AD}|{U+FFFD}x|{U+0080}|{U+07FF}|{U+0800}|{U+FFFF}|{U+10000}|{U+10FFFF}",
      "zz": 1
    }
EDGE_EOF
)"
  t="${t//\{U+00E9\}/$'\303\251'}"
  t="${t//\{U+20AC\}/$'\342\202\254'}"
  t="${t//\{U+1F3AD\}/$'\360\237\216\255'}"
  t="${t//\{U+FFFD\}/$'\357\277\275'}"
  t="${t//\{U+0080\}/$'\302\200'}"
  t="${t//\{U+07FF\}/$'\337\277'}"
  t="${t//\{U+0800\}/$'\340\240\200'}"
  t="${t//\{U+FFFF\}/$'\357\277\277'}"
  t="${t//\{U+10000\}/$'\360\220\200\200'}"
  t="${t//\{U+10FFFF\}/$'\364\217\277\277'}"
  printf '%s' "$t"
}

case_t_json_edges() {
  local ans root got want
  ans="$(mktemp_file)"
  head -n 1 "$FIXTURE" | grep -qx '{' || return 1
  EDGE_PROBE="$EDGE_PROBE_JSON" awk 'NR == 1 { print; print "  \"zzedge_probe\": " ENVIRON["EDGE_PROBE"] ","; next } { print }' "$FIXTURE" > "$ans"
  root="$(mktemp_root)"
  run_emit "$root" --answers "$ans" >/dev/null 2>&1 || return 1
  got="$(sed -n '/^    "zzedge_probe": /,/^    }$/p' "$root/orchestration-kit.manifest.json")"
  want="$(edge_expected)"
  [ -n "$got" ] && [ "$got" = "$want" ]
}

manifest_add_file_entry() { # mf relpath abspath
  local mf="$1" rel="$2" ap="$3" hash ans_line ins_line prev_line
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$ap" | awk '{print $1}')"
  else
    hash="$(shasum -a 256 "$ap" | awk '{print $1}')"
  fi
  ans_line="$(grep -n '^  "answers":' "$mf" | head -1 | cut -d: -f1)"
  [ -n "$ans_line" ] || return 1
  ins_line=$((ans_line - 1))
  prev_line=$((ins_line - 1))
  sed -n "${ins_line}p" "$mf" | grep -qxF '  },' || return 1
  if ! sed -n "${prev_line}p" "$mf" | grep -qE '",'; then
    sed "${prev_line}s/\"$/\",/" "$mf" > "${mf}.comma" && mv "${mf}.comma" "$mf"
  fi
  sed "${ins_line}i\\
    \"$rel\": \"$hash\"
" "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
}

case_upgrade_log_spawn_ps1_prune() {
  local root out rc prune_n
  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  echo '@rem stale twin' > "$root/_kit/log-spawn.ps1"
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_kit/log-spawn.ps1" "$root/_kit/log-spawn.ps1" || return 1
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ ! -f "$root/_kit/log-spawn.ps1" ] || return 1
  prune_n="$(printf '%s' "$out" | sed -n 's/.*pruned \([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$prune_n" ] && [ "$prune_n" -ge 1 ]
}

case_upgrade_loop_ps1_triple_prune() {
  local root out rc prune_n
  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  mkdir -p "$root/_loop" "$root/_kit"
  echo '@rem stale loop twin' > "$root/_loop/loop.ps1"
  echo '@rem stale breaker twin' > "$root/_loop/breaker.ps1"
  echo '@rem stale memory twin' > "$root/_kit/memory.ps1"
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_loop/loop.ps1" "$root/_loop/loop.ps1" || return 1
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_loop/breaker.ps1" "$root/_loop/breaker.ps1" || return 1
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_kit/memory.ps1" "$root/_kit/memory.ps1" || return 1
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ ! -f "$root/_loop/loop.ps1" ] || return 1
  [ ! -f "$root/_loop/breaker.ps1" ] || return 1
  [ ! -f "$root/_kit/memory.ps1" ] || return 1
  prune_n="$(printf '%s' "$out" | sed -n 's/.*pruned \([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$prune_n" ] && [ "$prune_n" -ge 3 ]
}

_upgrade_loop_ps1_triple_setup() { # root
  local root="$1"
  mkdir -p "$root/_loop" "$root/_kit"
  echo '@rem stale loop twin' > "$root/_loop/loop.ps1"
  echo '@rem stale breaker twin' > "$root/_loop/breaker.ps1"
  echo '@rem stale memory twin' > "$root/_kit/memory.ps1"
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_loop/loop.ps1" "$root/_loop/loop.ps1" || return 1
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_loop/breaker.ps1" "$root/_loop/breaker.ps1" || return 1
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "_kit/memory.ps1" "$root/_kit/memory.ps1" || return 1
}

_emit_stdout_warnings() { # stdout
  printf '%s' "$1" | sed -n 's/.*warnings \([0-9][0-9]*\).*/\1/p' | head -1
}

case_upgrade_loop_ps1_modified_retain() {
  local root out rc baseline_warn warn_n baseline_out
  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  _upgrade_loop_ps1_triple_setup "$root" || return 1
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  baseline_out="$out"
  baseline_warn="$(_emit_stdout_warnings "$out")"
  [ -n "$baseline_warn" ] || baseline_warn=0

  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  _upgrade_loop_ps1_triple_setup "$root" || return 1
  echo 'user modified' >> "$root/_loop/loop.ps1"
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ -f "$root/_loop/loop.ps1" ] || return 1
  [ ! -f "$root/_loop/breaker.ps1" ] || return 1
  [ ! -f "$root/_kit/memory.ps1" ] || return 1
  warn_n="$(_emit_stdout_warnings "$out")"
  [ -n "$warn_n" ] && [ "$warn_n" -gt "$baseline_warn" ] || return 1
  # The kept file prints its own warning line, and the count rises by exactly that one line.
  [ "$warn_n" -eq $((baseline_warn + 1)) ] || return 1
  printf '%s\n' "$out" | grep -qxF "$_KEPT_LOOP_PS1_LINE" || return 1
  [ "$(printf '%s\n' "$out" | grep -cF 'warning: kept ')" -eq 1 ] || return 1
  # Control: the unmodified run printed no `kept` line.
  ! printf '%s\n' "$baseline_out" | grep -qF 'warning: kept '
}

_KEPT_LOOP_PS1_LINE='emit: warning: kept _loop/loop.ps1: kit-owned file from an earlier emit, modified locally, no longer emitted — delete it or keep it as your own'

# A file the previous manifest records is gone and is not kit-owned: emit prints one warning line for it and
# counts it. Control: the same file present is carried, with no such line.
case_upgrade_recorded_file_missing_warns() {
  local root out rc baseline_warn warn_n probe='docs/user-owned-note.md' line
  line="emit: warning: $probe is recorded in the previous manifest but missing — nothing to prune"
  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  mkdir -p "$root/docs"
  echo 'user note' > "$root/$probe"
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "$probe" "$root/$probe" || return 1
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ -f "$root/$probe" ] || return 1
  ! printf '%s\n' "$out" | grep -qF 'but missing' || return 1
  baseline_warn="$(_emit_stdout_warnings "$out")"
  [ -n "$baseline_warn" ] || baseline_warn=0

  root="$(mktemp_root)"
  emit_cache_copy "$root" "$FIXTURE" || return 1
  mkdir -p "$root/docs"
  echo 'user note' > "$root/$probe"
  manifest_add_file_entry "$root/orchestration-kit.manifest.json" "$probe" "$root/$probe" || return 1
  rm -f "$root/$probe"
  rc=0
  out="$(run_emit "$root" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' "$out" | grep -qxF "$line" || return 1
  warn_n="$(_emit_stdout_warnings "$out")"
  [ -n "$warn_n" ] && [ "$warn_n" -eq $((baseline_warn + 1)) ]
}

# CDPATH hazard: with CDPATH set, `cd <relative-name>` may enter a decoy directory and prints the resolved path
# to stdout, so `$(cd … && pwd)` yields two lines or the wrong directory. emit.sh resolves its script, kit and
# root directories with `CDPATH= cd`. The probe exports CDPATH="<decoy>:." (the decoy holds same-named empty
# directories), then runs emit with a relative --root and --kit, with a relative script path and the default kit,
# and `--check` with a relative root. Each emit run must exit 0, print exactly one `emit: written …` stdout line
# and write only under the intended root; the --check run must exit 0 with `kit-guard: ok …`. <kit-dir> defaults
# to the repository kit.
_cdpath_run() { # <work> <out> <err> emit-args… — run emit.sh from <work> with the hostile CDPATH
  local w="$1" out="$2" err="$3"
  shift 3
  ( cd "$w" && CDPATH="$w/decoy:." "$BASH" "$@" ) >"$out" 2>"$err"
}

case_cdpath_relative_paths() { # [kit-dir]
  local kitdir="${1:-$KIT}" w answers rc out err
  answers="$REPO_ROOT/tests/agent-kit/fixtures/emit-golden/cases/harness-claude-code/answers.json"
  [ -f "$answers" ] || return 1
  w="$(mktemp_root)"
  mkdir -p "$w/decoy/r" "$w/decoy/r2"
  ln -s "$kitdir" "$w/kitlink" 2>/dev/null || cp -R "$kitdir" "$w/kitlink" || return 1
  out="$w/out"
  err="$w/err"

  # Relative --root and --kit, absolute script path.
  rc=0
  _cdpath_run "$w" "$out" "$err" "$kitdir/bin/emit.sh" --root r --kit kitlink --answers "$answers" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ "$(wc -l < "$out" | tr -d ' ')" -eq 1 ] && grep -q '^emit: written ' "$out" || return 1
  [ -f "$w/r/orchestration-kit.manifest.json" ] || return 1
  [ -z "$(ls -A "$w/decoy/r")" ] || return 1

  # Relative script path and the default kit (derived from the script's directory).
  rc=0
  _cdpath_run "$w" "$out" "$err" kitlink/bin/emit.sh --root r2 --answers "$answers" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ "$(wc -l < "$out" | tr -d ' ')" -eq 1 ] && grep -q '^emit: written ' "$out" || return 1
  [ -f "$w/r2/orchestration-kit.manifest.json" ] || return 1
  [ -z "$(ls -A "$w/decoy/r2")" ] || return 1

  # --check with a relative root: checks the emitted tree, not the decoy directory of the same name.
  rc=0
  _cdpath_run "$w" "$out" "$err" kitlink/bin/emit.sh --check --root r || rc=$?
  [ "$rc" -eq 0 ] || return 1
  grep -q '^kit-guard: ok ' "$out" || return 1
  [ -z "$(ls -A "$w/decoy/r")" ]
}

# Failing counterparts: the same probe on a copy of the kit whose emit.sh has ONE `CDPATH= cd` changed back to `cd`
# must fail (exactly one line differs, the copy still parses and still holds the other `CDPATH=` assignments).
# The kit-directory capture from `$SCRIPT_DIR/..` is not probed this way: that path is absolute, so CDPATH is never
# consulted for it; the static check below covers it.
case_cdpath_mutant_fails() { # <sed expression that reverts one site>
  local d mk
  d="$(mktemp_root)"
  mk="$d/kit"
  cp -R "$KIT" "$mk" || return 1
  sed "$1" "$KIT/bin/emit.sh" > "$mk/bin/emit.sh" || return 1
  [ "$(diff "$KIT/bin/emit.sh" "$mk/bin/emit.sh" | grep -c '^>')" -eq 1 ] || return 1
  grep -q 'CDPATH= cd ' "$mk/bin/emit.sh" || return 1
  bash -n "$mk/bin/emit.sh" || return 1
  ! case_cdpath_relative_paths "$mk"
}

# Static pairing: every directory change in emit.sh that feeds a `$( … )` capture is `CDPATH= cd`.
case_no_bare_cd_capture() {
  [ -f "$KIT/bin/emit.sh" ] || return 1
  grep -q 'CDPATH= cd ' "$KIT/bin/emit.sh" || return 1
  ! grep -qE '\$\(cd ' "$KIT/bin/emit.sh"
}

emit_cache_init

# jq hidden from PATH — direct emit (no cache; PATH is part of the emit environment)
root="$(mktemp_root)"
rc=0
PATH="$(path_without jq)" run_emit "$root" --answers "$FIXTURE" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  report PASS "jq-hidden PATH: dogfood fixture emit succeeds"
else
  report FAIL "jq-hidden PATH: dogfood fixture emit succeeds" "rc=$rc"
fi

# shasum-only PATH
if ! command -v shasum >/dev/null 2>&1; then
  report SKIP "shasum-only PATH: emit succeeds" "shasum not installed"
else
  root="$(mktemp_root)"
  if PATH="$(path_without sha256sum)" run_emit "$root" --answers "$FIXTURE" >/dev/null 2>&1; then
    report PASS "shasum-only PATH: emit succeeds"
  else
    report FAIL "shasum-only PATH: emit succeeds"
  fi
fi

# neither sha256 tool
root="$(mktemp_root)"
rc=0
err="$(PATH="$(path_without sha256sum shasum)" run_emit "$root" --answers "$FIXTURE" 2>&1 >/dev/null)" || rc=$?
if [ "$rc" -eq 2 ] && [[ "$err" == emit:* ]] && [[ "$err" == *sha256sum* ]] && [[ "$err" == *shasum* ]]; then
  report PASS "no sha256 tool on PATH: exit 2 with emit: message"
else
  report FAIL "no sha256 tool on PATH: exit 2 with emit: message" "rc=$rc err=[$err]"
fi

# Task 03 case (t): JSON \\u edges under default awk
if case_t_json_edges; then
  report PASS "(t) JSON edge probe byte-exact under default awk"
else
  report FAIL "(t) JSON edge probe byte-exact under default awk"
fi

# Upgrade: prior _kit/log-spawn.ps1 pruned
if case_upgrade_log_spawn_ps1_prune; then
  report PASS "upgrade: _kit/log-spawn.ps1 from prior manifest is pruned (stdout count)"
else
  report FAIL "upgrade: _kit/log-spawn.ps1 from prior manifest is pruned (stdout count)"
fi

if case_upgrade_loop_ps1_triple_prune; then
  report PASS "upgrade: unmodified loop.ps1/breaker.ps1/memory.ps1 pruned (stdout count)"
else
  report FAIL "upgrade: unmodified loop.ps1/breaker.ps1/memory.ps1 pruned (stdout count)"
fi

if case_upgrade_loop_ps1_modified_retain; then
  report PASS "upgrade: modified loop.ps1 retained; warnings count"
else
  report FAIL "upgrade: modified loop.ps1 retained; warnings count"
fi

if case_upgrade_recorded_file_missing_warns; then
  report PASS "upgrade: a recorded non-kit file that is missing prints one warning line and is counted"
else
  report FAIL "upgrade: a recorded non-kit file that is missing prints one warning line and is counted"
fi

# CDPATH: relative --root/--kit/script paths and --check behave the same with a hostile exported CDPATH.
if case_cdpath_relative_paths; then
  report PASS "CDPATH=<decoy>:. exported: relative --root, --kit, script path and --check resolve to the intended root"
else
  report FAIL "CDPATH=<decoy>:. exported: relative --root, --kit, script path and --check resolve to the intended root"
fi

if case_no_bare_cd_capture; then
  report PASS "emit.sh: every directory capture uses CDPATH= cd (no bare \$(cd …) left)"
else
  report FAIL "emit.sh: every directory capture uses CDPATH= cd (no bare \$(cd …) left)"
fi

_cdpath_mutant_report() { # <name> <sed expression>
  if case_cdpath_mutant_fails "$2"; then
    report PASS "mutation-proof: emit.sh with the $1 reverted to a bare cd fails the CDPATH probe"
  else
    report FAIL "mutation-proof: emit.sh with the $1 reverted to a bare cd fails the CDPATH probe"
  fi
}

_cdpath_mutant_report 'script-directory capture' 's/^SCRIPT_DIR="[$](CDPATH= cd /SCRIPT_DIR="$(cd /'
_cdpath_mutant_report 'explicit --kit capture' 's/^  KIT="[$](CDPATH= cd "[$]KIT"/  KIT="$(cd "$KIT"/'
_cdpath_mutant_report '--check root capture' 's/_check_root="[$](CDPATH= cd /_check_root="$(cd /'
_cdpath_mutant_report 'root capture' 's/^  ROOT="[$](CDPATH= cd /  ROOT="$(cd /'

# bash:3.2 docker run of emit-golden.sh
case "${AGENT_KIT_DOCKER:-}" in
  ''|0)
    report SKIP "bash:3.2 docker emit-golden.sh" "set AGENT_KIT_DOCKER=1 to run"
    ;;
  1)
    if ! command -v docker >/dev/null 2>&1; then
      report FAIL "bash:3.2 docker emit-golden.sh" "AGENT_KIT_DOCKER=1 but docker not on PATH"
    elif ! docker image inspect bash:3.2 >/dev/null 2>&1; then
      report FAIL "bash:3.2 docker emit-golden.sh" "AGENT_KIT_DOCKER=1 but bash:3.2 image not available (docker pull bash:3.2)"
    else
      drc=0
      git_common="$(git -C "$REPO_ROOT_ABS" rev-parse --git-common-dir 2>/dev/null || echo .git)"
      case "$git_common" in
        /*) git_common_abs="$git_common" ;;
        *) git_common_abs="$REPO_ROOT_ABS/$git_common" ;;
      esac
      if [ -d "$git_common_abs" ]; then
        git_common_abs="$( (CDPATH='' cd -- "$git_common_abs" && pwd -P) )"
      fi
      docker_v=( -v "$REPO_ROOT_ABS:/w:ro" )
      safe_dirs=( "/w" )
      if [ "$git_common_abs" != "$REPO_ROOT_ABS" ] && [ -d "$git_common_abs" ]; then
        docker_v+=( -v "$git_common_abs:$git_common_abs:ro" )
        safe_dirs+=( "$git_common_abs" )
      fi
      safe_cfg=""
      for sd in "${safe_dirs[@]}"; do
        safe_cfg="${safe_cfg}git config --global --add safe.directory '$sd' && "
      done
      dout="$(docker run --rm "${docker_v[@]}" -w /w bash:3.2 sh -c \
        "apk add --no-cache git >/dev/null && ${safe_cfg}bash tests/agent-kit/templates/emit-golden.sh" 2>&1)" || drc=$?
      if [ "$drc" -eq 0 ]; then
        report PASS "bash:3.2 docker emit-golden.sh"
      else
        report FAIL "bash:3.2 docker emit-golden.sh" "rc=$drc"
      fi
    fi
    ;;
  *)
    report FAIL "bash:3.2 docker emit-golden.sh" "AGENT_KIT_DOCKER must be 0 or 1"
    ;;
esac

if ( assert_fixture_root "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects repository root"
else
  report PASS "fixture-root guard rejects repository root"
fi
if ( assert_fixture_root "" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects empty root"
else
  report PASS "fixture-root guard rejects empty root"
fi
# Helper-level negative that can fail: EMIT_SH is an `exit 0` stub that drops a marker, so an
# unguarded run_emit would succeed and leave the marker. The control run proves the stub is live.
_emit_stub="$FIXTURE_TMPDIR/emit-stub.sh"
_emit_marker="$FIXTURE_TMPDIR/emit-stub-ran"
printf '%s\n' ': > "$EMIT_STUB_MARKER"' 'exit 0' > "$_emit_stub"
rm -f "$_emit_marker"
_emit_ctrl_root="$(mktemp_root)"
_emit_ctrl_rc=0
( EMIT_STUB_MARKER="$_emit_marker" EMIT_SH="$_emit_stub" run_emit "$_emit_ctrl_root" --answers "$FIXTURE" >/dev/null 2>&1 ) || _emit_ctrl_rc=$?
_emit_ctrl_ran=0
[ -e "$_emit_marker" ] && _emit_ctrl_ran=1
rm -f "$_emit_marker"
_emit_empty_rc=0
( EMIT_STUB_MARKER="$_emit_marker" EMIT_SH="$_emit_stub" run_emit "" --answers "$FIXTURE" >/dev/null 2>&1 ) || _emit_empty_rc=$?
if [ "$_emit_ctrl_rc" -eq 0 ] && [ "$_emit_ctrl_ran" -eq 1 ] \
  && [ "$_emit_empty_rc" -ne 0 ] && [ ! -e "$_emit_marker" ]; then
  report PASS "run_emit refuses empty root before emit"
else
  report FAIL "run_emit refuses empty root before emit" "control_rc=$_emit_ctrl_rc control_ran=$_emit_ctrl_ran empty_rc=$_emit_empty_rc marker=$([ -e "$_emit_marker" ] && echo present || echo absent)"
fi

echo "SUMMARY: pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
