# shellcheck shell=bash
# Run-scoped emit cache for agent-kit template suites (Bash 3.2).
# Source silently; suites set EMIT_SH, KIT, EMIT_DATE, PAR_REPORT_FAIL before use.

EMIT_CACHE_PRIVATE=""
EMIT_CACHE_WE_OWN=0
EMIT_CACHE_USED=""
EMIT_CACHE_OFF_ROOT=""
EMIT_CACHE_OFF_STAGING=""
EMIT_CACHE_FAILED_STAGING=""
EMIT_CACHE_RC=""
EMIT_CACHE_OUT=""
EMIT_CACHE_ERR=""
EMIT_CACHE_INIT_FAILED=0

_emit_cache_fail_init() {
  EMIT_CACHE_INIT_FAILED=1
  return 1
}

_emit_cache_refuse_if_broken() {
  if [ "${EMIT_CACHE_INIT_FAILED:-0}" -eq 1 ]; then
    echo "emit-cache: init failed; refusing further cache operations" >&2
    return 1
  fi
  return 0
}

_emit_cache_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "emit-cache: need sha256sum or shasum" >&2
    return 1
  fi
}

_emit_cache_file_hash() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

_emit_cache_resolve_dir() {
  local p="${1-}"
  [ -n "$p" ] || return 1
  [ -d "$p" ] || return 1
  (CDPATH='' cd -- "$p" >/dev/null 2>&1 && pwd -P)
}

_emit_cache_repo_root_abs() {
  local rr="${REPO_ROOT:-}"
  [ -n "$rr" ] || return 1
  _emit_cache_resolve_dir "$rr"
}

# Writable emit/copy targets outside the shared cache: refuse empty, relative, repo paths.
_emit_cache_assert_writable_root() {
  local root="${1-}" abs repo_abs cache cache_abs
  if [ -z "$root" ]; then
    echo "emit-cache: empty root" >&2
    return 1
  fi
  case "$root" in
    /*) ;;
    *)
      echo "emit-cache: root is not an absolute path: $root" >&2
      return 1
      ;;
  esac
  if [ ! -d "$root" ]; then
    echo "emit-cache: root is not an existing directory: $root" >&2
    return 1
  fi
  cache="$(_emit_cache_dir 2>/dev/null)" || cache=""
  if [ -n "$cache" ] && [ "$cache" != "off" ]; then
    _emit_cache_assert_cache_dir "$cache" || return 1
    cache_abs="$(_emit_cache_resolve_dir "$cache")" && [ -n "$cache_abs" ] || {
      echo "emit-cache: cannot resolve cache dir: $cache" >&2
      return 1
    }
    abs="$(_emit_cache_resolve_dir "$root")" && [ -n "$abs" ] || {
      echo "emit-cache: cannot resolve root: $root" >&2
      return 1
    }
    case "$abs" in
      "$cache_abs" | "$cache_abs"/*) return 0 ;;
    esac
  fi
  if type assert_fixture_root >/dev/null 2>&1; then
    assert_fixture_root "$root"
    return $?
  fi
  abs="$(_emit_cache_resolve_dir "$root")" && [ -n "$abs" ] || {
    echo "emit-cache: cannot resolve root: $root" >&2
    return 1
  }
  repo_abs="$(_emit_cache_repo_root_abs)" || {
    echo "emit-cache: REPO_ROOT unset or not a directory" >&2
    return 1
  }
  case "$abs" in
    "$repo_abs" | "$repo_abs"/*)
      echo "emit-cache: refused repository root: $abs" >&2
      return 1
      ;;
  esac
  return 0
}

# Shared/per-suite cache directory (may sit outside FIXTURE_TMPDIR, e.g. run-all log dir).
_emit_cache_assert_cache_dir() {
  local cache="${1-}" abs repo_abs
  if [ -z "$cache" ]; then
    echo "emit-cache: empty cache dir" >&2
    return 1
  fi
  case "$cache" in
    /*) ;;
    *)
      echo "emit-cache: cache dir is not an absolute path: $cache" >&2
      return 1
      ;;
  esac
  if [ ! -d "$cache" ]; then
    echo "emit-cache: cache dir is not an existing directory: $cache" >&2
    return 1
  fi
  abs="$(_emit_cache_resolve_dir "$cache")" && [ -n "$abs" ] || {
    echo "emit-cache: cannot resolve cache dir: $cache" >&2
    return 1
  }
  repo_abs="$(_emit_cache_repo_root_abs)" || {
    echo "emit-cache: REPO_ROOT unset or not a directory" >&2
    return 1
  }
  case "$abs" in
    "$repo_abs" | "$repo_abs"/*)
      echo "emit-cache: cache dir is the repository or under it: $abs" >&2
      return 1
      ;;
  esac
  return 0
}

emit_cache_init() {
  EMIT_CACHE_INIT_FAILED=0
  if [ "${AGENT_KIT_EMIT_CACHE:-}" = "off" ]; then
    if [ -n "${EMIT_CACHE_OFF_ROOT:-}" ] && [ -d "${EMIT_CACHE_OFF_ROOT:-}" ]; then
      _emit_cache_assert_writable_root "$EMIT_CACHE_OFF_ROOT" || { _emit_cache_fail_init; return 1; }
    elif [ -z "${EMIT_CACHE_OFF_ROOT:-}" ] || [ ! -d "${EMIT_CACHE_OFF_ROOT:-}" ]; then
      EMIT_CACHE_OFF_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t emit-off-root)"
      EMIT_CACHE_WE_OWN=1
      _emit_cache_assert_writable_root "$EMIT_CACHE_OFF_ROOT" || { _emit_cache_fail_init; return 1; }
    fi
    return 0
  fi
  if [ -n "${AGENT_KIT_EMIT_CACHE:-}" ]; then
    _emit_cache_assert_cache_dir "$AGENT_KIT_EMIT_CACHE" || { _emit_cache_fail_init; return 1; }
    return 0
  fi
  if [ -n "${EMIT_CACHE_PRIVATE:-}" ] && [ -d "${EMIT_CACHE_PRIVATE:-}" ]; then
    _emit_cache_assert_cache_dir "$EMIT_CACHE_PRIVATE" || { _emit_cache_fail_init; return 1; }
    export AGENT_KIT_EMIT_CACHE="$EMIT_CACHE_PRIVATE"
    return 0
  fi
  EMIT_CACHE_PRIVATE="$(mktemp -d 2>/dev/null || mktemp -d -t emit-cache)"
  EMIT_CACHE_WE_OWN=1
  _emit_cache_assert_cache_dir "$EMIT_CACHE_PRIVATE" || { _emit_cache_fail_init; return 1; }
  export AGENT_KIT_EMIT_CACHE="$EMIT_CACHE_PRIVATE"
}

_emit_cache_dir() {
  _emit_cache_refuse_if_broken || return 1
  if [ "${AGENT_KIT_EMIT_CACHE:-}" = "off" ]; then
    echo "off"
    return 0
  fi
  if [ -n "${AGENT_KIT_EMIT_CACHE:-}" ]; then
    _emit_cache_assert_cache_dir "$AGENT_KIT_EMIT_CACHE" || return 1
    echo "$AGENT_KIT_EMIT_CACHE"
    return 0
  fi
  echo "emit-cache: call emit_cache_init in the parent shell before use" >&2
  return 1
}

_emit_cache_reject_args() {
  local a
  for a in "$@"; do
    case "$a" in
      --upgrade | --force | --dry-run | --check-answers | --root)
        echo "emit-cache: rejected emit argument: $a" >&2
        return 2
        ;;
    esac
  done
  return 0
}

_emit_cache_tool_path() {
  command -v "$1" 2>/dev/null || echo ""
}

_emit_cache_compute_key() {
  local answers="$1"
  shift
  local tmp kit_list
  tmp="$(mktemp 2>/dev/null || mktemp -t eck)"
  kit_list="$(mktemp 2>/dev/null || mktemp -t eckit)"
  if [ -d "$KIT" ]; then
    find "$KIT" -type f 2>/dev/null | LC_ALL=C sort >"$kit_list"
  else
    : >"$kit_list"
  fi
  {
    _emit_cache_file_hash "$EMIT_SH"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local rel mode h
      rel="${f#"$KIT"/}"
      rel="${rel#/}"
      if [ -x "$f" ]; then
        mode="x"
      else
        mode="-"
      fi
      h="$(_emit_cache_file_hash "$f")"
      printf '%s %s %s\n' "$rel" "$mode" "$h"
    done <"$kit_list"
    _emit_cache_file_hash "$answers"
    local a
    for a in "$@"; do
      printf '%s\0' "$a"
    done
    printf '%s\n' "${EMIT_DATE:-}"
    printf '%s\n' "${LC_ALL:-}"
    printf '%s\n' "${BASH:-}"
    printf '%s\n' "${BASH_VERSION:-}"
    printf '%s\n' "${PATH:-}"
    printf 'pwsh:%s\n' "$(_emit_cache_tool_path pwsh)"
    printf 'jq:%s\n' "$(_emit_cache_tool_path jq)"
    printf 'awk:%s\n' "$(_emit_cache_tool_path awk)"
    printf 'sha256sum:%s\n' "$(_emit_cache_tool_path sha256sum)"
    printf 'shasum:%s\n' "$(_emit_cache_tool_path shasum)"
  } >"$tmp"
  rm -f "$kit_list"
  _emit_cache_sha256 <"$tmp"
  rm -f "$tmp"
}

_emit_cache_write_manifest() {
  local root="$1"
  local man="$2"
  local list f rel h
  list="$(mktemp 2>/dev/null || mktemp -t ecm)"
  find "$root" -type f 2>/dev/null | LC_ALL=C sort >"$list"
  : >"$man"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    rel="${f#"$root"/}"
    rel="${rel#/}"
    h="$(_emit_cache_file_hash "$f")"
    printf '%s %s\n' "$rel" "$h" >>"$man"
  done <"$list"
  rm -f "$list"
}

_emit_cache_verify_entry() {
  local root="$1"
  local man="$2"
  [ -f "$man" ] || return 1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local rel expect h
    rel="${line%% *}"
    expect="${line#* }"
    [ -f "$root/$rel" ] || return 1
    h="$(_emit_cache_file_hash "$root/$rel")"
    [ "$h" = "$expect" ] || return 1
  done <"$man"
}

_emit_cache_run_emit() {
  local root="$1"
  local answers="$2"
  local rc_path="$3"
  local out_path="$4"
  local err_path="$5"
  shift 5
  _emit_cache_assert_writable_root "$root" || return 1
  mkdir -p "$root"
  local rc=0
  if "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" --answers "$answers" "$@" >"$out_path" 2>"$err_path"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" >"$rc_path"
  echo "$rc"
}

_emit_cache_fill() {
  local key="$1"
  local answers="$2"
  shift 2
  local cache_root lock staging entry rc lock_wait=0
  _emit_cache_refuse_if_broken || return 1
  cache_root="$(_emit_cache_dir)" || return 1
  _emit_cache_assert_cache_dir "$cache_root" || return 1
  entry="$cache_root/entry-${key}"
  if [ -d "$entry/root" ]; then
    return 0
  fi
  lock="$cache_root/lock-${key}"
  while ! mkdir "$lock" 2>/dev/null; do
    if [ -d "$entry/root" ]; then
      return 0
    fi
    if [ ! -d "$cache_root" ]; then
      echo "emit-cache: cache dir disappeared during lock wait (key=${key})" >&2
      return 1
    fi
    lock_wait=$((lock_wait + 1))
    if [ "$lock_wait" -ge 6000 ]; then
      echo "emit-cache: lock wait timeout (key=${key})" >&2
      return 1
    fi
    sleep 0.05
  done
  staging="$cache_root/staging-${key}-$$"
  rm -rf "$staging"
  mkdir -p "$staging/root"
  rc="$(_emit_cache_run_emit "$staging/root" "$answers" "$staging/rc" "$staging/stdout" "$staging/stderr" "$@")"
  if [ "$rc" != "0" ]; then
    EMIT_CACHE_RC="$staging/rc"
    EMIT_CACHE_OUT="$staging/stdout"
    EMIT_CACHE_ERR="$staging/stderr"
    EMIT_CACHE_FAILED_STAGING="${EMIT_CACHE_FAILED_STAGING} ${staging}"
    rmdir "$lock" 2>/dev/null || rm -rf "$lock"
    return "$rc"
  fi
  _emit_cache_write_manifest "$staging/root" "$staging/manifest"
  if [ -d "$entry" ]; then
    rm -rf "$staging"
  else
    mv "$staging" "$entry"
  fi
  rmdir "$lock" 2>/dev/null || rm -rf "$lock"
  return 0
}

_emit_cache_used_keys_file() {
  local cache_root
  cache_root="$(_emit_cache_dir)" || return 1
  if [ "$cache_root" = "off" ]; then
    return 1
  fi
  echo "$cache_root/.used-keys"
}

_emit_cache_note_used() {
  local key="$1" cache_root f
  _emit_cache_refuse_if_broken || return 1
  case " ${EMIT_CACHE_USED} " in
    *" ${key} "*) ;;
    *) EMIT_CACHE_USED="${EMIT_CACHE_USED} ${key}" ;;
  esac
  cache_root="$(_emit_cache_dir)" || return 1
  if [ "$cache_root" = "off" ]; then
    return 0
  fi
  _emit_cache_assert_cache_dir "$cache_root" || return 1
  f="$cache_root/.used-keys"
  if ! grep -qxF "$key" "$f" 2>/dev/null; then
    echo "$key" >>"$f"
  fi
}

emit_cache_root() {
  local var="$1"
  local answers="$2"
  shift 2
  _emit_cache_refuse_if_broken || return 1
  _emit_cache_reject_args "$@" || return $?
  local cache_root key entry root rc
  cache_root="$(_emit_cache_dir)" || return 1
  if [ "$cache_root" = "off" ]; then
    local staging
    if [ -z "${EMIT_CACHE_OFF_ROOT:-}" ] || [ ! -d "${EMIT_CACHE_OFF_ROOT:-}" ]; then
      emit_cache_init || return 1
    fi
    _emit_cache_assert_writable_root "$EMIT_CACHE_OFF_ROOT" || return 1
    staging="$(mktemp -d "$EMIT_CACHE_OFF_ROOT/staging.XXXXXX" 2>/dev/null || mktemp -d -t emit-off-stg)"
    _emit_cache_assert_writable_root "$staging" || return 1
    mkdir -p "$staging/root"
    rc="$(_emit_cache_run_emit "$staging/root" "$answers" "$staging/rc" "$staging/stdout" "$staging/stderr" "$@")"
    EMIT_CACHE_RC="$staging/rc"
    EMIT_CACHE_OUT="$staging/stdout"
    EMIT_CACHE_ERR="$staging/stderr"
    eval "$var=\"$staging/root\""
    EMIT_CACHE_OFF_STAGING="${EMIT_CACHE_OFF_STAGING} ${staging}"
    return "$rc"
  fi
  key="$(_emit_cache_compute_key "$answers" "$@")"
  entry="$cache_root/entry-${key}"
  if [ -d "$entry/root" ]; then
    if _emit_cache_verify_entry "$entry/root" "$entry/manifest"; then
      _emit_cache_note_used "$key"
      eval "$var=\"$entry/root\""
      EMIT_CACHE_RC="$entry/rc"
      EMIT_CACHE_OUT="$entry/stdout"
      EMIT_CACHE_ERR="$entry/stderr"
      return 0
    fi
    if [ -n "${PAR_REPORT_FAIL:-}" ]; then
      ${PAR_REPORT_FAIL} "emit-cache: entry mutated ${key}"
    fi
    return 1
  fi
  _emit_cache_fill "$key" "$answers" "$@" || return $?
  entry="$cache_root/entry-${key}"
  _emit_cache_note_used "$key"
  eval "$var=\"$entry/root\""
  EMIT_CACHE_RC="$entry/rc"
  EMIT_CACHE_OUT="$entry/stdout"
  EMIT_CACHE_ERR="$entry/stderr"
  return 0
}

emit_cache_copy() {
  local dest="$1"
  local answers="$2"
  shift 2
  local src
  _emit_cache_refuse_if_broken || return 1
  _emit_cache_assert_writable_root "$dest" || return 1
  emit_cache_root src "$answers" "$@" || return $?
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -Rp "$src/." "$dest/"
}

emit_cache_verify() {
  local key entry cache_root f seen
  _emit_cache_refuse_if_broken || return 1
  cache_root="$(_emit_cache_dir)" || return 1
  if [ "$cache_root" = "off" ]; then
    return 0
  fi
  _emit_cache_assert_cache_dir "$cache_root" || return 1
  f="$cache_root/.used-keys"
  seen=""
  if [ -f "$f" ]; then
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      case " ${seen} " in
        *" ${key} "*) continue ;;
      esac
      seen="${seen} ${key}"
      entry="$cache_root/entry-${key}"
      if ! _emit_cache_verify_entry "$entry/root" "$entry/manifest"; then
        if [ -n "${PAR_REPORT_FAIL:-}" ]; then
          ${PAR_REPORT_FAIL} "emit-cache: entry mutated ${key}"
        fi
      fi
    done <"$f"
  fi
  for key in ${EMIT_CACHE_USED}; do
    [ -z "$key" ] && continue
    case " ${seen} " in
      *" ${key} "*) continue ;;
    esac
    entry="$cache_root/entry-${key}"
    if ! _emit_cache_verify_entry "$entry/root" "$entry/manifest"; then
      if [ -n "${PAR_REPORT_FAIL:-}" ]; then
        ${PAR_REPORT_FAIL} "emit-cache: entry mutated ${key}"
      fi
    fi
  done
}

emit_cache_cleanup() {
  local d we_own="${EMIT_CACHE_WE_OWN:-0}"
  for d in ${EMIT_CACHE_FAILED_STAGING}; do
    [ -z "$d" ] && continue
    rm -rf "$d"
  done
  EMIT_CACHE_FAILED_STAGING=""
  if [ "$we_own" -eq 1 ] && [ -n "${EMIT_CACHE_PRIVATE:-}" ] && [ -d "${EMIT_CACHE_PRIVATE:-}" ]; then
    rm -rf "$EMIT_CACHE_PRIVATE"
  fi
  if [ "$we_own" -eq 1 ] && [ -n "${EMIT_CACHE_OFF_ROOT:-}" ] && [ -d "${EMIT_CACHE_OFF_ROOT:-}" ]; then
    rm -rf "$EMIT_CACHE_OFF_ROOT"
  fi
  if [ "$we_own" -eq 1 ]; then
    unset AGENT_KIT_EMIT_CACHE
  fi
  EMIT_CACHE_PRIVATE=""
  EMIT_CACHE_OFF_ROOT=""
  EMIT_CACHE_WE_OWN=0
  for d in ${EMIT_CACHE_OFF_STAGING}; do
    [ -z "$d" ] && continue
    rm -rf "$d"
  done
  EMIT_CACHE_OFF_STAGING=""
}
