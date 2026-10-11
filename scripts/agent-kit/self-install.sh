#!/usr/bin/env bash
# Kit-repo-only dogfood installer — copies (or symlinks) skills/agent-kit
# from this working tree into the harness destination directories.
# Never emitted to consumers; internal to the kdcllc/skills repo only.
#
# Twin: self-install.ps1 (PowerShell 7+) — behaviorally identical —
# same defaults, guards, and exit codes; any divergence is a bug.
#
# After copying skills, runs skills/agent-kit/bin/emit.sh from
# tests/agent-kit/fixtures/self-answers.json unless --no-emit. Dest paths are the
# definition; this script does not invoke npx or any network tool.
#
# Usage:  scripts/agent-kit/self-install.sh [--dry-run] [--symlink] [--force] [--no-emit] [--force-emit]
#   --dry-run  Print planned dest paths to stdout; write nothing; exit 0.
#              Combined with --symlink, prints the symlink plan. When emit runs,
#              passes --dry-run to emit.sh (action lines only; no writes).
#   --symlink  Canonical real tree at .agents/skills/<name>/;
#              .claude/skills/<name> and .cursor/skills/<name> become symlinks.
#              Fails loudly on symlink failure; never falls back to copy.
#   --force    Accepted and ignored (overwrite is already the default).
#   --no-emit  Copy skills only; skip emit (legacy behaviour).
#   --force-emit  Pass --force to emit.sh (overwrite user-modified instance files).
#
# Exit codes: 0 = success (including dry-run); non-zero = any error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# _usage is printed only on the unknown-flag path; never on missing-skills or
# install-failure paths. Binding decision — ps1 twin must match.
_usage() {
  echo "Usage: $(basename "$0") [--dry-run] [--symlink] [--force] [--no-emit] [--force-emit]" >&2
  echo "  --dry-run  Print planned dest paths; write nothing; exit 0." >&2
  echo "  --symlink  Symlink mode: canonical tree at .agents/skills/<name>/;" >&2
  echo "             .claude/skills/<name> and .cursor/skills/<name> become symlinks." >&2
  echo "  --force    Accepted and ignored (overwrite is already the default)." >&2
  echo "  --no-emit  Copy skills only; skip emit." >&2
  echo "  --force-emit  Pass --force to emit.sh." >&2
}

DRY_RUN=0
SYMLINK=0
NO_EMIT=0
FORCE_EMIT=0

for _arg in "$@"; do
  case "$_arg" in
    --dry-run) DRY_RUN=1 ;;
    --symlink) SYMLINK=1 ;;
    --force)   ;;
    --no-emit) NO_EMIT=1 ;;
    --force-emit) FORCE_EMIT=1 ;;
    *)
      echo "error: unknown argument: $_arg" >&2
      _usage
      exit 1
      ;;
  esac
done

# Install only skills/agent-kit. The other skills in this repo would land in
# .cursor/skills/ too, where their .claude/ references fail emit verify and
# checks M/N. Nested files such as skills/agent-kit/templates/skills/feature/SKILL.md
# are NOT skills.
SKILLS_DIR="$REPO_ROOT/skills"
if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "error: skills/ directory not found: $SKILLS_DIR" >&2
  exit 1
fi

SKILL_NAMES=()
[[ -f "$SKILLS_DIR/agent-kit/SKILL.md" ]] && SKILL_NAMES+=("agent-kit")

if (( ${#SKILL_NAMES[@]} == 0 )); then
  echo "error: skill not found: $SKILLS_DIR/agent-kit/SKILL.md" >&2
  exit 1
fi

_run_emit() {
  local _emit_args=(--root "$REPO_ROOT" --kit "$REPO_ROOT/skills/agent-kit"
    --answers "$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json" --upgrade)
  if (( FORCE_EMIT == 1 )); then
    _emit_args+=(--force)
  fi
  if (( DRY_RUN == 1 )); then
    _emit_args+=(--dry-run)
  fi
  bash "$REPO_ROOT/skills/agent-kit/bin/emit.sh" "${_emit_args[@]}"
  local _rc=$?
  if (( _rc == 4 )); then
    echo "re-run with --force-emit to overwrite user-modified instance files" >&2
  fi
  return "$_rc"
}

# Dry-run: print the plan; optionally print emit dry-run lines; write nothing.
if (( DRY_RUN == 1 )); then
  for _name in "${SKILL_NAMES[@]}"; do
    if (( SYMLINK == 1 )); then
      echo "[dry-run] real tree:  $REPO_ROOT/.agents/skills/$_name/"
      echo "[dry-run] symlink:    $REPO_ROOT/.claude/skills/$_name -> $REPO_ROOT/.agents/skills/$_name"
      echo "[dry-run] symlink:    $REPO_ROOT/.cursor/skills/$_name -> $REPO_ROOT/.agents/skills/$_name"
    else
      echo "[dry-run] copy: $REPO_ROOT/.claude/skills/$_name/"
      echo "[dry-run] copy: $REPO_ROOT/.cursor/skills/$_name/"
    fi
  done
  if (( NO_EMIT == 0 )); then
    _run_emit || exit $?
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Snapshot / rollback infrastructure.
#
# Take a snapshot of every dest this run will touch BEFORE any mutation.
# The EXIT trap restores all snapshotted paths on non-zero exit, after
# the first dest has been written (_WROTE_SOMETHING=1).  Because .claude is
# always written before .cursor (copy mode) / before symlinks (symlink mode),
# a failure mid-run correctly restores .claude too.
# ---------------------------------------------------------------------------
_SNAPSHOT_DIR=""
_SNAP_COUNT=0
_SNAP_PATH=()
_WROTE_SOMETHING=0
_RESTORE_FAIL_PATHS=()

_snapshot() {
  local _dest="$1"
  local _idx="$_SNAP_COUNT"
  _SNAP_PATH+=("$_dest")
  _SNAP_COUNT=$((_SNAP_COUNT + 1))
  mkdir -p "$_SNAPSHOT_DIR/$_idx"
  if [[ -L "$_dest" ]]; then
    readlink "$_dest" > "$_SNAPSHOT_DIR/$_idx/link_target"
  elif [[ -f "$_dest" ]]; then
    cp -a "$_dest" "$_SNAPSHOT_DIR/$_idx/file_backup"
  elif [[ -d "$_dest" ]]; then
    cp -a "$_dest" "$_SNAPSHOT_DIR/$_idx/dir_backup"
  fi
  # absent path: no backup file written — restore will only rm, not re-create
}

_do_restore() {
  local _i _dest _fail
  for ((_i = _SNAP_COUNT - 1; _i >= 0; _i--)); do
    _dest="${_SNAP_PATH[$_i]:-}"
    [[ -z "$_dest" ]] && continue
    _fail=0
    if ! rm -rf "$_dest" 2>/dev/null; then
      echo "error: rollback: could not remove: $_dest" >&2
      _RESTORE_FAIL_PATHS+=("$_dest")
      continue
    fi
    if [[ -f "$_SNAPSHOT_DIR/$_i/link_target" ]]; then
      local _tgt
      _tgt="$(cat "$_SNAPSHOT_DIR/$_i/link_target")"
      if ! ln -sf "$_tgt" "$_dest"; then
        echo "error: rollback: could not restore symlink: $_dest" >&2
        _fail=1
      fi
    elif [[ -f "$_SNAPSHOT_DIR/$_i/file_backup" ]]; then
      if ! cp -a "$_SNAPSHOT_DIR/$_i/file_backup" "$_dest"; then
        echo "error: rollback: could not restore file: $_dest" >&2
        _fail=1
      fi
    elif [[ -d "$_SNAPSHOT_DIR/$_i/dir_backup" ]]; then
      if ! cp -a "$_SNAPSHOT_DIR/$_i/dir_backup" "$_dest"; then
        echo "error: rollback: could not restore directory: $_dest" >&2
        _fail=1
      fi
    fi
    # absent-before dest: rm-only is the correct restore; no re-create needed
    if (( _fail == 1 )); then
      _RESTORE_FAIL_PATHS+=("$_dest")
    fi
  done
}

_on_exit() {
  local _rc=$?
  if (( _rc != 0 )) && (( _WROTE_SOMETHING == 1 )); then
    echo "error: install failed (exit $_rc); rolling back changes..." >&2
    _do_restore
    if (( ${#_RESTORE_FAIL_PATHS[@]} == 0 )); then
      echo "rollback complete" >&2
    else
      echo "error: PARTIAL ROLLBACK — the following paths could not be restored:" >&2
      local _p
      for _p in "${_RESTORE_FAIL_PATHS[@]}"; do
        echo "  $_p" >&2
      done
    fi
  fi
  if [[ -n "$_SNAPSHOT_DIR" ]]; then
    rm -rf "$_SNAPSHOT_DIR" 2>/dev/null || true
  fi
}
trap _on_exit EXIT

_SNAPSHOT_DIR="$(mktemp -d)"

# Parent dirs (.claude/skills/, .cursor/skills/, .agents/skills/) created during
# a rolled-back run may remain — no parent-dir cleanup is performed. Twin must match.

# Snapshot all dest paths before any mutation.
if (( SYMLINK == 1 )); then
  for _name in "${SKILL_NAMES[@]}"; do
    _snapshot "$REPO_ROOT/.agents/skills/$_name"
    _snapshot "$REPO_ROOT/.claude/skills/$_name"
    _snapshot "$REPO_ROOT/.cursor/skills/$_name"
  done
else
  for _name in "${SKILL_NAMES[@]}"; do
    _snapshot "$REPO_ROOT/.claude/skills/$_name"
    _snapshot "$REPO_ROOT/.cursor/skills/$_name"
  done
fi

# Install each skill.
for _name in "${SKILL_NAMES[@]}"; do
  _src="$SKILLS_DIR/$_name"

  if (( SYMLINK == 1 )); then
    _agents_dest="$REPO_ROOT/.agents/skills/$_name"
    _claude_dest="$REPO_ROOT/.claude/skills/$_name"
    _cursor_dest="$REPO_ROOT/.cursor/skills/$_name"

    # Real tree at .agents/skills/<name>/
    mkdir -p "$REPO_ROOT/.agents/skills"
    _WROTE_SOMETHING=1
    rm -rf "$_agents_dest"
    cp -a "$_src" "$_agents_dest"

    # .claude/skills/<name> symlink (fail-loud, never fall back to copy)
    mkdir -p "$REPO_ROOT/.claude/skills"
    rm -rf "$_claude_dest"
    if ! ln -s "$_agents_dest" "$_claude_dest"; then
      echo "error: failed to create symlink: $_claude_dest -> $_agents_dest" >&2
      exit 1
    fi

    # .cursor/skills/<name> symlink
    mkdir -p "$REPO_ROOT/.cursor/skills"
    rm -rf "$_cursor_dest"
    if ! ln -s "$_agents_dest" "$_cursor_dest"; then
      echo "error: failed to create symlink: $_cursor_dest -> $_agents_dest" >&2
      exit 1
    fi

  else
    _claude_dest="$REPO_ROOT/.claude/skills/$_name"
    _cursor_dest="$REPO_ROOT/.cursor/skills/$_name"

    # .claude/skills/<name>/ first — copy mode must never write through a
    # leftover symlink; rm -rf removes the symlink itself, not its target.
    mkdir -p "$REPO_ROOT/.claude/skills"
    _WROTE_SOMETHING=1
    rm -rf "$_claude_dest"
    cp -a "$_src" "$_claude_dest"

    # .cursor/skills/<name>/ second
    mkdir -p "$REPO_ROOT/.cursor/skills"
    rm -rf "$_cursor_dest"
    cp -a "$_src" "$_cursor_dest"
  fi

  echo "installed: $_name"
done

echo "done: ${#SKILL_NAMES[@]} skill(s) installed"

if (( NO_EMIT == 0 )); then
  _run_emit || exit $?
fi
