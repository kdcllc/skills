#!/usr/bin/env bash
# Guard: emit.sh portability (jq-free PATH, sha256 tools, Bash 3.2 docker, JSON edges).
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

printf 'bash: %s\n' "$BASH_VERSION"

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

. "$HERE/../lib/emit-cache.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
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

RUN_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t ep-run)"

mktemp_root() {
  mktemp -d "$RUN_TMP/root.XXXXXX"
}

mktemp_file() {
  mktemp "$RUN_TMP/file.XXXXXX"
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
      farm="$(mktemp -d "$RUN_TMP/pwf.XXXXXX")"
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
  "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --answers "$ans" >/dev/null 2>&1 || return 1
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
  out="$("$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --force --upgrade 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 1
  [ ! -f "$root/_kit/log-spawn.ps1" ] || return 1
  prune_n="$(printf '%s' "$out" | sed -n 's/.*pruned \([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$prune_n" ] && [ "$prune_n" -ge 1 ]
}

emit_cache_init

# jq hidden from PATH — direct emit (no cache; PATH is part of the emit environment)
root="$(mktemp_root)"
rc=0
PATH="$(path_without jq)" "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || rc=$?
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
  if PATH="$(path_without sha256sum)" "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1; then
    report PASS "shasum-only PATH: emit succeeds"
  else
    report FAIL "shasum-only PATH: emit succeeds"
  fi
fi

# neither sha256 tool
root="$(mktemp_root)"
rc=0
err="$(PATH="$(path_without sha256sum shasum)" "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --answers "$FIXTURE" 2>&1 >/dev/null)" || rc=$?
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

# bash:3.2 docker run of emit-golden.sh
if ! command -v docker >/dev/null 2>&1; then
  report SKIP "bash:3.2 docker emit-golden.sh" "docker not on PATH"
elif ! docker image inspect bash:3.2 >/dev/null 2>&1; then
  report SKIP "bash:3.2 docker emit-golden.sh" "bash:3.2 image not available"
else
  drc=0
  git_common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || echo .git)"
  git_common_abs="$(cd "$REPO_ROOT" && cd "$git_common" && pwd)"
  repo_abs="$(cd "$REPO_ROOT" && pwd)"
  docker_v=( -v "$repo_abs:/w" )
  safe_dirs=( "/w" )
  if [ "$git_common_abs" != "$repo_abs" ] && [ -d "$git_common_abs" ]; then
    docker_v+=( -v "$git_common_abs:$git_common_abs" )
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

echo "SUMMARY: pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
