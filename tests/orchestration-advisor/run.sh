#!/usr/bin/env bash
# Tests for skills/orchestration-advisor/scripts/inspect.sh (the output contract
# in references/signals.md) and for scripts/checks/orchestration-advisor.sh.
#
# Every fixture tree is built at run time under one `mktemp -d` directory that
# is removed on exit. This folder ships one markdown scenario,
# fixtures/audit-scenario.md, and never a SKILL.md or a harness folder: a
# committed file named SKILL.md under tests/ would be published by the Skills
# CLI. Trees are still built at run time.
#
# Offline. Cases that need `jq` or `git` print SKIP when the tool is absent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SKILL_DIR="${ORCHESTRATION_ADVISOR_SKILL_DIR:-$REPO/skills/orchestration-advisor}"
INSPECT="$SKILL_DIR/scripts/inspect.sh"
SIGNALS="$SKILL_DIR/references/signals.md"
GUARD="$REPO/scripts/checks/orchestration-advisor.sh"
# The bash that is executing this suite, so inspect.sh and the guard run under
# the same version (bash 3.2 when the suite is started with macOS /bin/bash).
BASH_BIN="${BASH:-$(type -P bash)}"

PASS=0
FAIL=0
SKIP=0
SUMMARY_PRINTED=0

SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/orchestration-advisor.XXXXXX")"
SCRATCH_ROOT="$(cd "$SCRATCH_ROOT" && pwd -P)"
cleanup() {
  chmod -R u+rwx "$SCRATCH_ROOT" 2>/dev/null || true
  rm -rf "$SCRATCH_ROOT"
}

print_summary() {
  echo "PASS: $PASS FAIL: $FAIL SKIP: $SKIP"
  SUMMARY_PRINTED=1
}

# Exit trap. When the suite stops before main printed the summary (a set-up
# command failed under `set -e`), say so on stderr, still print the summary
# line, and never exit 0.
on_exit() {
  local rc=$?
  if [ "$SUMMARY_PRINTED" -eq 0 ]; then
    echo "ABORTED: suite stopped before all cases ran" >&2
    print_summary
    if [ "$rc" -eq 0 ]; then
      rc=1
    fi
  fi
  cleanup
  exit "$rc"
}
trap on_exit EXIT

# --- ambient conditions, pinned ------------------------------------------------

# Expected values assume the C locale unless a case says otherwise: every
# fixture is ASCII there, so characters equal bytes for `wc -m`.
export LC_ALL=C

# Keep git from discovering a repository above the scratch directory (a TMPDIR
# inside a work tree) and from reading the caller's git environment or config.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CDPATH
export GIT_CEILING_DIRECTORIES="$SCRATCH_ROOT"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null

# --- runner helpers ------------------------------------------------------------

case_pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
case_fail() { FAIL=$((FAIL + 1)); echo "FAIL $1: $2" >&2; }
case_skip() { SKIP=$((SKIP + 1)); echo "SKIP $1: $2"; }

have() { type -P "$1" >/dev/null 2>&1; }

# A new empty project root under the scratch directory.
new_root() {
  mktemp -d "$SCRATCH_ROOT/p.XXXXXX"
}

# put <file> [content]: create a file (and its parent directories).
put() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "${2-}" >"$1"
}

# The contract's key list: the backticked first cell of each row of the table
# under "## Keys" in references/signals.md, in file order.
keys_from_contract() {
  awk '
    /^## Keys[ \t]*$/ { inkeys = 1; next }
    /^## / { inkeys = 0 }
    inkeys && /^\|[ \t]*`[a-z0-9_]+`[ \t]*\|/ {
      k = $0
      sub(/^\|[ \t]*`/, "", k)
      sub(/`.*$/, "", k)
      print k
    }
  ' "$SIGNALS" 2>/dev/null || true
}

# run_inspect [args...]: runs inspect.sh; sets OUT (stdout), ERR (stderr), RC.
# INSPECT_PATH and INSPECT_LC, when set, replace PATH and LC_ALL for the run.
OUT=""
ERR=""
RC=0
INSPECT_PATH=""
INSPECT_LC=""
run_inspect() {
  local errf="$SCRATCH_ROOT/stderr.txt"
  RC=0
  OUT="$(LC_ALL="${INSPECT_LC:-$LC_ALL}" PATH="${INSPECT_PATH:-$PATH}" \
    "$BASH_BIN" "$INSPECT" "$@" 2>"$errf")" || RC=$?
  ERR="$(cat "$errf")"
}

# Value of one key in OUT; empty when the key is not printed.
value_of() {
  printf '%s\n' "$OUT" | awk -v k="$1" '
    index($0, k "=") == 1 && !seen { print substr($0, length(k) + 2); seen = 1 }
  '
}

# Empty when OUT is exactly the contract's keys, in order, each with an integer
# or `unknown` value; otherwise a reason.
shape_problem() {
  local got_keys bad_lines
  got_keys="$(printf '%s\n' "$OUT" | sed 's/=.*$//')"
  if [ "$got_keys" != "$KEYS" ]; then
    echo "printed keys differ from references/signals.md: $(echo $got_keys)"
    return 0
  fi
  bad_lines="$(printf '%s\n' "$OUT" | grep -vE '^[a-z0-9_]+=([0-9]+|unknown)$' || true)"
  if [ -n "$bad_lines" ]; then
    echo "malformed line(s): $bad_lines"
  fi
}

# assert_out <case> key=value...: exit 0, contract-shaped output, exact values.
assert_out() {
  local name="$1" pair key want got bad
  shift
  if [ "$RC" -ne 0 ]; then
    case_fail "$name" "exit $RC want 0"
    return 0
  fi
  bad="$(shape_problem)"
  for pair in "$@"; do
    key="${pair%%=*}"
    want="${pair#*=}"
    got="$(value_of "$key")"
    if [ "$got" != "$want" ]; then
      bad="${bad}${bad:+; }${key}=${got:-<missing>} want ${want}"
    fi
  done
  if [ -n "$bad" ]; then
    case_fail "$name" "$bad"
  else
    case_pass "$name"
  fi
}

# expect <case> <root> key=value...
expect() {
  local name="$1" root="$2"
  shift 2
  run_inspect "$root"
  assert_out "$name" "$@"
}

# expect_usage_error <case> [args...]: exit 2, nothing on stdout, usage on stderr.
expect_usage_error() {
  local name="$1"
  shift
  run_inspect "$@"
  if [ "$RC" -ne 2 ]; then
    case_fail "$name" "exit $RC want 2"
  elif [ -n "$OUT" ]; then
    case_fail "$name" "stdout not empty: $OUT"
  elif ! printf '%s\n' "$ERR" | grep -q 'Usage:'; then
    case_fail "$name" "no usage line on stderr"
  else
    case_pass "$name"
  fi
}

# Checksum listing of a tree: every path, plus a checksum of every file.
tree_listing() {
  (
    cd "$1"
    find . -print | LC_ALL=C sort
    find . -type f -exec cksum {} + | LC_ALL=C sort
    find . -type l -exec ls -l {} + | awk '{ print $(NF - 2), $(NF - 1), $NF }' | LC_ALL=C sort
  )
}

# make_stub_path <dir> <tool>...: a PATH directory holding only the named tools.
# Fails when one of them cannot be resolved to an absolute path.
make_stub_path() {
  local dir="$1" tool path
  shift
  mkdir -p "$dir"
  for tool in "$@"; do
    path="$(type -P "$tool" 2>/dev/null || true)"
    case "$path" in
      /*) ln -s "$path" "$dir/$tool" ;;
      *) return 1 ;;
    esac
  done
}

# The tools inspect.sh needs besides the optional jq and git.
CORE_TOOLS="find awk wc tr sort"

git_fixture() {
  git -C "$1" init -q
}

# --- contract and empty directory ----------------------------------------------

run_contract_cases() {
  local root pairs key
  root="$(new_root)"

  run_inspect "$root"
  if [ "$RC" -ne 0 ]; then
    case_fail "contract/keys-match-signals-md" "exit $RC want 0"
  elif [ -n "$(shape_problem)" ]; then
    case_fail "contract/keys-match-signals-md" "$(shape_problem)"
  elif [ -n "$ERR" ]; then
    case_fail "contract/keys-match-signals-md" "unexpected stderr: $ERR"
  else
    case_pass "contract/keys-match-signals-md"
  fi

  # Every key except tracked_files is a count (or a 0/1 flag) and is 0 here.
  pairs=""
  for key in $KEYS; do
    if [ "$key" != "tracked_files" ]; then
      pairs="$pairs $key=0"
    fi
  done
  # shellcheck disable=SC2086
  expect "empty/all-counts-zero" "$root" $pairs

  if have git && [ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
    case_skip "empty/tracked-files-unknown" "scratch directory is inside a git work tree"
  else
    expect "empty/tracked-files-unknown" "$root" tracked_files=unknown
  fi

  # No argument means the current directory.
  root="$(new_root)"
  put "$root/CLAUDE.md"
  put "$root/package.json" '{}'
  RC=0
  OUT="$(cd "$root" && "$BASH_BIN" "$INSPECT" 2>/dev/null)" || RC=$?
  assert_out "args/default-is-current-directory" harness_claude=1 package_manifests=1 harness_codex=0
}

# --- harness keys, agent-kit, composer -----------------------------------------

run_harness_cases() {
  local root

  root="$(new_root)"
  mkdir "$root/.claude"
  expect "harness_claude/dot-claude-dir" "$root" \
    harness_claude=1 harness_cursor=0 harness_copilot=0 harness_codex=0

  root="$(new_root)"
  put "$root/CLAUDE.md" "# rules"
  expect "harness_claude/claude-md-file" "$root" \
    harness_claude=1 harness_cursor=0 harness_copilot=0 harness_codex=0

  root="$(new_root)"
  mkdir "$root/.cursor"
  expect "harness_cursor/dot-cursor-dir" "$root" \
    harness_claude=0 harness_cursor=1 harness_copilot=0 harness_codex=0

  root="$(new_root)"
  put "$root/.github/copilot-instructions.md" "# rules"
  expect "harness_copilot/copilot-instructions" "$root" \
    harness_claude=0 harness_cursor=0 harness_copilot=1 harness_codex=0

  root="$(new_root)"
  mkdir -p "$root/.github/agents"
  expect "harness_copilot/github-agents-dir" "$root" \
    harness_claude=0 harness_cursor=0 harness_copilot=1 harness_codex=0

  # .github alone (workflows only) is not Copilot.
  root="$(new_root)"
  put "$root/.github/workflows/ci.yml"
  expect "harness_copilot/github-dir-alone-is-zero" "$root" \
    harness_copilot=0 ci_workflows=1

  root="$(new_root)"
  mkdir "$root/.codex"
  expect "harness_codex/dot-codex-dir" "$root" \
    harness_claude=0 harness_cursor=0 harness_copilot=0 harness_codex=1

  root="$(new_root)"
  put "$root/AGENTS.md" "# rules"
  expect "harness_codex/agents-md-file" "$root" \
    harness_claude=0 harness_cursor=0 harness_copilot=0 harness_codex=1

  root="$(new_root)"
  put "$root/orchestration-kit.manifest.json" '{}'
  expect "agent_kit_installed/manifest-at-root" "$root" agent_kit_installed=1

  # The manifest only counts at the root.
  root="$(new_root)"
  put "$root/sub/orchestration-kit.manifest.json" '{}'
  expect "agent_kit_installed/nested-manifest-is-zero" "$root" agent_kit_installed=0

  root="$(new_root)"
  put "$root/.agent-composer/one.crew.yaml"
  put "$root/.agent-composer/two.crew.yaml"
  put "$root/.agent-composer/one.manifest.json" '{}'
  put "$root/.agent-composer/notes.yaml"
  put "$root/.agent-composer/three.crew.yml"
  put "$root/.agent-composer/sub/four.crew.yaml"
  put "$root/five.crew.yaml"
  expect "composer_crews/counts-crew-yaml-only" "$root" composer_crews=2
}

# --- agents --------------------------------------------------------------------

run_agent_cases() {
  local root

  # .md and .toml count; other extensions and nested folders do not.
  root="$(new_root)"
  put "$root/.claude/agents/alpha.md"
  put "$root/.codex/agents/beta.toml"
  put "$root/.claude/agents/gamma.txt"
  put "$root/.claude/agents/delta.json"
  put "$root/.claude/agents/sub/epsilon.md"
  put "$root/.codex/agents/sub/zeta.toml"
  expect "agent_files/md-and-toml-only-not-nested" "$root" agent_files=2

  # All four harness folders are read.
  root="$(new_root)"
  put "$root/.claude/agents/a.md"
  put "$root/.cursor/agents/b.md"
  put "$root/.github/agents/c.agent.md"
  put "$root/.codex/agents/d.toml"
  expect "agent_files/four-harness-folders" "$root" agent_files=4

  root="$(new_root)"
  put "$root/.claude/agents/reviewer.md"
  put "$root/.cursor/agents/reviewer.md"
  expect "agent_files/same-name-two-harnesses-once" "$root" agent_files=1

  root="$(new_root)"
  put "$root/.claude/agents/x.md"
  put "$root/.github/agents/x.agent.md"
  expect "agent_files/md-and-agent-md-once" "$root" agent_files=1

  root="$(new_root)"
  put "$root/.claude/agents/x.md"
  put "$root/.github/agents/x.agent.md"
  put "$root/.codex/agents/x.toml"
  put "$root/.cursor/agents/y.md"
  expect "agent_files/md-agent-md-toml-once" "$root" agent_files=2

  # Only .md files directly inside .claude/agents.
  root="$(new_root)"
  put "$root/.claude/agents/one.md"
  put "$root/.claude/agents/two.md"
  put "$root/.claude/agents/three.toml"
  put "$root/.claude/agents/sub/four.md"
  put "$root/.cursor/agents/five.md"
  put "$root/.github/agents/six.agent.md"
  expect "claude_agent_files/direct-md-in-claude-agents" "$root" \
    claude_agent_files=2 agent_files=5
}

run_description_cases() {
  local root loc candidate probe

  # Expected values assume LC_ALL=C (pinned at the top): the text is ASCII, so
  # `wc -m` counts one character per byte.
  #   unquoted, padded  "Reviews code"   12
  #   double-quoted     "Writes tests."  13
  #   single-quoted     "abcde"           5
  #   no description, no frontmatter, description after the frontmatter: 0
  # Total 30; 30 / 4 rounds down to 7.
  root="$(new_root)"
  put "$root/.claude/agents/unquoted.md" "$(printf '%s\n' '---' 'name: unquoted' 'description:   Reviews code  ' 'tools: Read' '---' 'Body.')"
  put "$root/.claude/agents/double.md" "$(printf '%s\n' '---' 'name: double' 'description: "Writes tests."' '---' 'Body.')"
  put "$root/.claude/agents/single.md" "$(printf '%s\n' '---' "description: 'abcde'" 'name: single' '---')"
  put "$root/.claude/agents/none.md" "$(printf '%s\n' '---' 'name: none' 'model: inherit' '---' 'Body.')"
  put "$root/.claude/agents/nofm.md" "$(printf '%s\n' '# Heading' 'description: not frontmatter, twenty-nine')"
  put "$root/.claude/agents/after.md" "$(printf '%s\n' '---' 'name: after' '---' 'description: body text after the frontmatter')"
  put "$root/.claude/agents/ignored.toml" 'description = "a toml agent in the claude folder"'
  expect "claude_agent_description/quoted-unquoted-missing" "$root" \
    claude_agent_files=6 \
    claude_agent_description_chars=30 \
    claude_agent_description_tokens_est=7

  # Descriptions outside .claude/agents are not measured.
  root="$(new_root)"
  put "$root/.claude/agents/mine.md" "$(printf '%s\n' '---' 'description: twelve chars' '---')"
  put "$root/.cursor/agents/other.md" "$(printf '%s\n' '---' 'description: a cursor agent description that must not be counted' '---')"
  put "$root/.github/agents/third.agent.md" "$(printf '%s\n' '---' 'description: a copilot agent description that must not be counted' '---')"
  expect "claude_agent_description/other-harness-folders-not-counted" "$root" \
    agent_files=3 \
    claude_agent_files=1 \
    claude_agent_description_chars=12 \
    claude_agent_description_tokens_est=3

  root="$(new_root)"
  put "$root/.cursor/agents/only.md" "$(printf '%s\n' '---' 'description: cursor only' '---')"
  expect "claude_agent_description/no-claude-agents-is-zero" "$root" \
    agent_files=1 \
    claude_agent_files=0 \
    claude_agent_description_chars=0 \
    claude_agent_description_tokens_est=0

  # A block value counts only the indicator on the description line.
  root="$(new_root)"
  put "$root/.claude/agents/folded.md" "$(printf '%s\n' '---' 'description: >' '  A long folded description' '  over two lines.' '---')"
  expect "claude_agent_description/block-indicator-counts-one" "$root" \
    claude_agent_files=1 \
    claude_agent_description_chars=1 \
    claude_agent_description_tokens_est=0

  # Exactly at the divide-by-4 boundary: 8 characters give 2, 7 give 1.
  root="$(new_root)"
  put "$root/.claude/agents/eight.md" "$(printf '%s\n' '---' 'description: 12345678' '---')"
  expect "claude_agent_description/tokens-at-boundary-8" "$root" \
    claude_agent_description_chars=8 claude_agent_description_tokens_est=2
  put "$root/.claude/agents/eight.md" "$(printf '%s\n' '---' 'description: 1234567' '---')"
  expect "claude_agent_description/tokens-below-boundary-7" "$root" \
    claude_agent_description_chars=7 claude_agent_description_tokens_est=1

  # Multibyte text. Expected values assume a UTF-8 locale, where `wc -m` counts
  # characters: "h<e-acute>llo w<o-umlaut>rld" is 11 characters in 13 bytes.
  # Skipped when no UTF-8 locale is installed.
  loc=""
  for candidate in C.UTF-8 en_US.UTF-8 C.utf8 en_US.utf8; do
    probe="$(printf '\303\251' | env LC_ALL="$candidate" wc -m 2>/dev/null | tr -d '[:space:]' || true)"
    if [ "$probe" = "1" ]; then
      loc="$candidate"
      break
    fi
  done
  if [ -z "$loc" ]; then
    case_skip "claude_agent_description/multibyte-utf8-locale" "no UTF-8 locale available"
  else
    root="$(new_root)"
    put "$root/.claude/agents/accent.md" "$(printf '%s\n' '---' "$(printf 'description: "h\303\251llo w\303\266rld"')" '---')"
    INSPECT_LC="$loc"
    run_inspect "$root"
    INSPECT_LC=""
    assert_out "claude_agent_description/multibyte-utf8-locale" \
      claude_agent_description_chars=11 claude_agent_description_tokens_est=2
  fi
}

# `wc -m` failing (BSD wc does on bytes that are not valid in the locale): the
# bytes of the same text are counted instead.
run_wc_fallback_cases() {
  local name="claude_agent_description/wc-m-failure-falls-back-to-bytes"
  local root stub real_wc probe

  # A `wc` that exits 1 for `wc -m` and is the real one otherwise.
  real_wc="$(type -P wc 2>/dev/null || true)"
  case "$real_wc" in
    /*) ;;
    *)
      case_skip "$name" "cannot resolve wc to an absolute path"
      return 0
      ;;
  esac
  stub="$SCRATCH_ROOT/path-wc-no-m"
  mkdir -p "$stub"
  printf '%s\n' '#!/bin/sh' 'if [ "${1-}" = "-m" ]; then' '  exit 1' 'fi' \
    "exec '$real_wc' \"\$@\"" >"$stub/wc"
  chmod +x "$stub/wc"

  # "Reviews pull requests" is 21 ASCII characters; 21 / 4 rounds down to 5.
  root="$(new_root)"
  put "$root/.claude/agents/reviewer.md" "$(printf '%s\n' '---' 'name: reviewer' 'description: Reviews pull requests' '---' 'Body.')"

  # Preconditions: the stub fails for -m, still counts bytes, and is the wc
  # that a run with the stub directory first on PATH resolves.
  probe="$(printf 'abc' | "$stub/wc" -c 2>/dev/null | tr -d '[:space:]' || true)"
  if printf 'abc' | "$stub/wc" -m >/dev/null 2>&1; then
    case_fail "$name" "precondition: the stub wc does not fail for -m"
  elif [ "$probe" != "3" ]; then
    case_fail "$name" "precondition: the stub wc -c printed '$probe' want 3"
  elif [ "$(PATH="$stub:$PATH" && type -P wc)" != "$stub/wc" ]; then
    case_fail "$name" "precondition: the stub wc is not first on PATH"
  else
    INSPECT_PATH="$stub:$PATH"
    run_inspect "$root"
    INSPECT_PATH=""
    assert_out "$name" \
      claude_agent_files=1 \
      claude_agent_description_chars=21 \
      claude_agent_description_tokens_est=5
  fi
}

# Both `wc -m` and `wc -c` failing: nothing can count the description text, so
# the script exits 1 with a message and prints no key.
run_wc_failure_cases() {
  local name="claude_agent_description/wc-m-and-wc-c-failure-exits-1"
  local root stub real_wc probe

  real_wc="$(type -P wc 2>/dev/null || true)"
  case "$real_wc" in
    /*) ;;
    *)
      case_skip "$name" "cannot resolve wc to an absolute path"
      return 0
      ;;
  esac
  # A `wc` that prints a line on standard error and exits 1 for `wc -m` and
  # `wc -c`, and is the real one otherwise.
  stub="$SCRATCH_ROOT/path-wc-no-m-no-c"
  if ! mkdir -p "$stub" ||
    ! printf '%s\n' '#!/bin/sh' 'case "${1-}" in' \
      '  -m | -c) echo "wc: stub failure" >&2; exit 1 ;;' 'esac' \
      "exec '$real_wc' \"\$@\"" >"$stub/wc" ||
    ! chmod +x "$stub/wc"; then
    case_skip "$name" "cannot build a stub wc"
    return 0
  fi

  # "Reviews pull requests" is 21 ASCII characters.
  root="$(new_root)"
  put "$root/.claude/agents/reviewer.md" "$(printf '%s\n' '---' 'name: reviewer' 'description: Reviews pull requests' '---' 'Body.')"

  # Preconditions: the stub fails for -m and for -c, still counts lines, and is
  # the wc that a run with the stub directory first on PATH resolves; with the
  # real wc the same tree is counted (the run reaches the description count).
  probe="$(printf 'a\nb\n' | "$stub/wc" -l 2>/dev/null | tr -d '[:space:]' || true)"
  run_inspect "$root"
  if printf 'abc' | "$stub/wc" -m >/dev/null 2>&1; then
    case_fail "$name" "precondition: the stub wc does not fail for -m"
  elif printf 'abc' | "$stub/wc" -c >/dev/null 2>&1; then
    case_fail "$name" "precondition: the stub wc does not fail for -c"
  elif [ -z "$(printf 'abc' | "$stub/wc" -m 2>&1 >/dev/null || true)" ] ||
    [ -z "$(printf 'abc' | "$stub/wc" -c 2>&1 >/dev/null || true)" ]; then
    case_fail "$name" "precondition: the stub wc prints nothing on stderr for -m or -c"
  elif [ "$probe" != "2" ]; then
    case_fail "$name" "precondition: the stub wc -l printed '$probe' want 2"
  elif [ "$(PATH="$stub:$PATH" && type -P wc)" != "$stub/wc" ]; then
    case_fail "$name" "precondition: the stub wc is not first on PATH"
  elif [ "$RC" -ne 0 ] || [ "$(value_of claude_agent_description_chars)" != "21" ]; then
    case_fail "$name" "precondition: with the real wc exit $RC, chars=$(value_of claude_agent_description_chars) want 0 and 21"
  else
    INSPECT_PATH="$stub:$PATH"
    run_inspect "$root"
    INSPECT_PATH=""
    if [ "$RC" -ne 1 ]; then
      case_fail "$name" "exit $RC want 1"
    elif [ -n "$OUT" ]; then
      case_fail "$name" "stdout not empty: $OUT"
    elif ! printf '%s\n' "$ERR" | grep -qF "cannot count the description text"; then
      case_fail "$name" "stderr does not say 'cannot count the description text': $ERR"
    elif [ "$ERR" != "inspect.sh: cannot count the description text" ]; then
      case_fail "$name" "stderr is not exactly the one line 'inspect.sh: cannot count the description text': $ERR"
    else
      case_pass "$name"
    fi
  fi
}

# --- skills --------------------------------------------------------------------

run_skill_cases() {
  local root

  root="$(new_root)"
  put "$root/.claude/skills/top/SKILL.md"
  put "$root/.claude/skills/group/deeper/nested/SKILL.md"
  put "$root/.claude/skills/empty/README.md"
  put "$root/.claude/skills/SKILL.md"
  put "$root/skills/outside/SKILL.md"
  expect "skill_files/nested-depth" "$root" skill_files=2

  root="$(new_root)"
  put "$root/.claude/skills/a/SKILL.md"
  put "$root/.cursor/skills/b/SKILL.md"
  put "$root/.github/skills/c/SKILL.md"
  put "$root/.agents/skills/d/SKILL.md"
  put "$root/.codex/skills/e/SKILL.md"
  expect "skill_files/five-roots" "$root" skill_files=5

  root="$(new_root)"
  put "$root/.claude/skills/deploy/SKILL.md"
  put "$root/.cursor/skills/deploy/SKILL.md"
  put "$root/.cursor/skills/other/SKILL.md"
  expect "skill_files/same-name-two-roots-once" "$root" skill_files=2

  # A skill folder linked from one root into another counts once.
  root="$(new_root)"
  put "$root/.agents/skills/shared/SKILL.md"
  mkdir -p "$root/.claude/skills"
  ln -s ../../.agents/skills/shared "$root/.claude/skills/shared"
  expect "skill_files/symlinked-into-second-root-once" "$root" skill_files=1

  # The link is followed: the real folder is outside every root here, so the
  # skill is only found through the two links.
  root="$(new_root)"
  put "$root/store/linked/SKILL.md"
  mkdir -p "$root/.claude/skills" "$root/.cursor/skills"
  ln -s ../../store/linked "$root/.claude/skills/linked"
  ln -s ../../store/linked "$root/.cursor/skills/linked"
  expect "skill_files/symlink-is-followed" "$root" skill_files=1

  # A link back to the skill root itself must not fail the script. The cycle
  # sits in the first and in the last root the script walks, so a walk error
  # that is not ignored surfaces whichever walk decides the exit status.
  root="$(new_root)"
  put "$root/.claude/skills/real/SKILL.md"
  ln -s ../skills "$root/.claude/skills/loop"
  put "$root/.codex/skills/other/SKILL.md"
  ln -s ../skills "$root/.codex/skills/loop"
  expect "skill_files/symlink-cycle" "$root" skill_files=2
}

# An unreadable skill folder must not fail the script. It sits in the last root
# the script walks, so a walk error that is not ignored decides the exit status.
run_unreadable_skill_cases() {
  local name="skill_files/unreadable-folder-in-last-root"
  local root locked uid

  uid="$(id -u 2>/dev/null || true)"
  if [ "$uid" = "0" ]; then
    case_skip "$name" "running as user id 0, which reads through the mode"
    return 0
  fi

  root="$(new_root)"
  put "$root/.claude/skills/readable/SKILL.md"
  locked="$root/.codex/skills/locked"
  put "$locked/SKILL.md"

  # Precondition: while the folder is readable the walk reaches it.
  run_inspect "$root"
  if [ "$RC" -ne 0 ] || [ "$(value_of skill_files)" != "2" ]; then
    case_fail "$name" "precondition: before chmod exit $RC, skill_files=$(value_of skill_files) want 0 and 2"
    return 0
  fi

  if ! chmod 000 "$locked" 2>/dev/null; then
    case_skip "$name" "chmod 000 is not supported here"
    return 0
  fi
  if [ -r "$locked" ] || [ -x "$locked" ]; then
    chmod 755 "$locked" 2>/dev/null || true
    case_skip "$name" "mode 000 does not stop reads here"
    return 0
  fi

  run_inspect "$root"
  # Restore the mode at once, so the scratch root can be removed on exit.
  if ! chmod 755 "$locked"; then
    case_fail "$name" "could not restore the mode of $locked"
    return 0
  fi
  assert_out "$name" skill_files=1
}

# A copy of this suite that stops (an injected `exit 1`) while the folder of the
# case above still has mode 000 must still remove its scratch folder: its own
# TMPDIR is empty afterwards. The copy runs with ORCHESTRATION_ADVISOR_NESTED=1,
# and this case returns at once under that marker, so a copy never runs it.
run_interrupted_run_cases() {
  local name="summary/interrupted-run-leaves-no-scratch-folder"
  local uid self dir copy restored outf errf at rc err left

  if [ -n "${ORCHESTRATION_ADVISOR_NESTED:-}" ]; then
    return 0
  fi
  uid="$(id -u 2>/dev/null || true)"
  if [ "$uid" = "0" ]; then
    case_skip "$name" "running as user id 0: the unreadable-folder case skips, so the copy never reaches the injected stop"
    return 0
  fi

  self="$HERE/${BASH_SOURCE[0]##*/}"
  dir="$SCRATCH_ROOT/suite-interrupted"
  copy="$dir/tests/orchestration-advisor/run.sh"
  restored="$dir/restored.sh"
  outf="$dir/stdout.txt"
  errf="$dir/stderr.txt"
  if ! mkdir -p "$dir/tests/orchestration-advisor" "$dir/tmp" 2>/dev/null; then
    case_fail "$name" "precondition: cannot create a folder for the suite copy"
    return 0
  fi

  # The stop goes after the `fi` that closes the `chmod 000` test, three lines
  # below its `if` line, and so before the mode is restored.
  at="$(awk '$0 == "  if ! chmod 000 \"$locked\" 2>/dev/null; then" { print NR; exit }' "$self" 2>/dev/null || true)"
  if [ -z "$at" ]; then
    case_fail "$name" "precondition: no 'if ! chmod 000 \"\$locked\"' line in $self"
    return 0
  fi
  at=$((at + 3))
  if [ "$(awk -v n="$at" 'NR == n { print }' "$self")" != "  fi" ]; then
    case_fail "$name" "precondition: line $at of $self does not close the chmod 000 test"
    return 0
  fi
  awk -v at="$at" '{ print } NR == at { print "  exit 1" }' "$self" >"$copy"

  # Precondition: the copy is the suite plus exactly one line, `exit 1`.
  awk -v skip="$((at + 1))" 'NR != skip { print }' "$copy" >"$restored"
  if [ "$(($(lines_of "$copy") - $(lines_of "$self")))" -ne 1 ] ||
    [ "$(awk -v n="$((at + 1))" 'NR == n { print }' "$copy")" != "  exit 1" ] ||
    ! cmp -s "$restored" "$self"; then
    case_fail "$name" "precondition: the copy does not differ from the suite by exactly one line"
    return 0
  fi

  # The copy gets its own, empty TMPDIR under the scratch root.
  rc=0
  ORCHESTRATION_ADVISOR_NESTED=1 TMPDIR="$dir/tmp" \
    ORCHESTRATION_ADVISOR_SKILL_DIR="$SKILL_DIR" \
    "$BASH_BIN" "$copy" >"$outf" 2>"$errf" || rc=$?
  err="$(cat "$errf")"
  left="$(find "$dir/tmp" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)"
  # Whatever the copy left behind must not stop the removal of the scratch root.
  chmod -R u+rwx "$dir/tmp" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then
    case_fail "$name" "exit 0 want non-zero"
  elif ! printf '%s\n' "$err" | grep -qF "ABORTED: suite stopped before all cases ran"; then
    case_fail "$name" "stderr does not say 'ABORTED: suite stopped before all cases ran': $err"
  elif [ -n "$left" ]; then
    case_fail "$name" "the copy left a scratch folder in its TMPDIR: $left"
  else
    case_pass "$name"
  fi
}

run_skip_list_cases() {
  local root

  # The counted controls show the walks do reach this tree.
  root="$(new_root)"
  put "$root/.claude/skills/real/SKILL.md"
  put "$root/.claude/skills/node_modules/pkg/SKILL.md"
  put "$root/.claude/skills/.venv/lib/SKILL.md"
  put "$root/.claude/skills/group/node_modules/deep/SKILL.md"
  put "$root/package.json" '{}'
  put "$root/node_modules/dep/package.json" '{}'
  put "$root/.venv/lib/pyproject.toml"
  put "$root/.venv/package.json" '{}'
  expect "skip-list/node_modules-and-venv" "$root" skill_files=1 package_manifests=1

  # A skipped name directly under a skill root.
  root="$(new_root)"
  put "$root/.claude/skills/real/SKILL.md"
  put "$root/.claude/skills/build/SKILL.md"
  put "$root/.cursor/skills/dist/SKILL.md"
  put "$root/.agents/skills/vendor/SKILL.md"
  expect "skip-list/skipped-name-under-skill-root" "$root" skill_files=1

  root="$(new_root)"
  put "$root/go.mod"
  put "$root/vendor/dep/go.mod"
  put "$root/dist/package.json" '{}'
  put "$root/build/package.json" '{}'
  put "$root/.git/package.json" '{}'
  mkdir -p "$root/tests" "$root/node_modules/tests" "$root/vendor/spec" "$root/build/test"
  expect "skip-list/vendor-dist-build-git" "$root" package_manifests=1 test_paths=1

  # A project root that is itself named like a skipped directory is still read.
  root="$(new_root)/build"
  mkdir -p "$root/tests"
  put "$root/package.json" '{}'
  put "$root/.claude/skills/real/SKILL.md"
  expect "skip-list/root-named-build-is-read" "$root" \
    package_manifests=1 test_paths=1 skill_files=1
}

# --- MCP servers ---------------------------------------------------------------

run_mcp_cases() {
  local root stub

  if ! have jq; then
    case_skip "mcp_servers/sum-across-three-files" "jq not installed"
    case_skip "mcp_servers/single-file-each" "jq not installed"
    case_skip "mcp_servers/member-missing-is-zero" "jq not installed"
    case_skip "mcp_servers/invalid-json-unknown" "jq not installed"
    case_skip "mcp_servers/valid-plus-invalid-unknown" "jq not installed"
  else
    # 2 + 1 + 3. The decoy members (`servers` in .mcp.json, `mcpServers` in
    # .vscode/mcp.json) must not be counted.
    root="$(new_root)"
    put "$root/.mcp.json" '{"mcpServers": {"a": {}, "b": {}}, "servers": {"x1": {}, "x2": {}, "x3": {}, "x4": {}}}'
    put "$root/.cursor/mcp.json" '{"mcpServers": {"c": {"command": "c"}}}'
    put "$root/.vscode/mcp.json" '{"servers": {"d": {}, "e": {}, "f": {}}, "mcpServers": {"y1": {}, "y2": {}, "y3": {}, "y4": {}, "y5": {}}}'
    expect "mcp_servers/sum-across-three-files" "$root" mcp_servers=6

    root="$(new_root)"
    put "$root/.vscode/mcp.json" '{"servers": {"d": {}, "e": {}}}'
    run_inspect "$root"
    if [ "$(value_of mcp_servers)" != "2" ]; then
      case_fail "mcp_servers/single-file-each" ".vscode/mcp.json alone: $(value_of mcp_servers) want 2"
    else
      rm -rf "$root/.vscode"
      put "$root/.cursor/mcp.json" '{"mcpServers": {"c": {}, "d": {}, "e": {}}}'
      expect "mcp_servers/single-file-each" "$root" mcp_servers=3
    fi

    root="$(new_root)"
    put "$root/.mcp.json" '{}'
    put "$root/.cursor/mcp.json" '{"mcpServers": {}}'
    expect "mcp_servers/member-missing-is-zero" "$root" mcp_servers=0

    root="$(new_root)"
    put "$root/.mcp.json" '{"mcpServers": {"a": {}'
    expect "mcp_servers/invalid-json-unknown" "$root" mcp_servers=unknown

    root="$(new_root)"
    put "$root/.mcp.json" '{"mcpServers": {"a": {}, "b": {}}}'
    put "$root/.vscode/mcp.json" 'not json at all'
    expect "mcp_servers/valid-plus-invalid-unknown" "$root" mcp_servers=unknown
  fi

  # jq missing. The other keys still print, and the exit code is still 0.
  root="$(new_root)"
  put "$root/.mcp.json" '{"mcpServers": {"a": {}, "b": {}}}'
  put "$root/.claude/skills/real/SKILL.md"
  put "$root/package.json" '{}'
  if ! have jq; then
    expect "mcp_servers/no-jq-unknown" "$root" \
      mcp_servers=unknown skill_files=1 package_manifests=1
  else
    stub="$SCRATCH_ROOT/path-no-jq"
    # shellcheck disable=SC2086
    if ! make_stub_path "$stub" $CORE_TOOLS; then
      case_skip "mcp_servers/no-jq-unknown" "cannot build a PATH without jq"
    elif (PATH="$stub" && type -P jq >/dev/null 2>&1); then
      case_skip "mcp_servers/no-jq-unknown" "jq still reachable on the stub PATH"
    else
      # Precondition: with jq on PATH this same tree counts 2 servers.
      run_inspect "$root"
      if [ "$(value_of mcp_servers)" != "2" ]; then
        case_fail "mcp_servers/no-jq-unknown" "precondition: with jq mcp_servers=$(value_of mcp_servers) want 2"
      else
        INSPECT_PATH="$stub"
        run_inspect "$root"
        INSPECT_PATH=""
        assert_out "mcp_servers/no-jq-unknown" \
          mcp_servers=unknown skill_files=1 package_manifests=1
      fi
    fi
  fi

  # No MCP file at all is 0, with or without jq.
  root="$(new_root)"
  put "$root/mcp.json" '{"mcpServers": {"a": {}}}'
  expect "mcp_servers/no-file-is-zero" "$root" mcp_servers=0
}

# --- tests, CI, lint, type check, manifests --------------------------------------

run_project_cases() {
  local root

  # Depth 1 and 2 count; depth 3, plain files and symbolic links do not.
  root="$(new_root)"
  mkdir -p "$root/test" "$root/tests" "$root/src/__tests__" "$root/pkg/spec"
  mkdir -p "$root/a/b/tests" "$root/testing" "$root/lnk"
  put "$root/docs/test"
  ln -s ../tests "$root/lnk/spec"
  expect "test_paths/depth-1-and-2" "$root" test_paths=4

  root="$(new_root)"
  put "$root/.github/workflows/ci.yml"
  put "$root/.github/workflows/release.yaml"
  put "$root/.github/workflows/notes.txt"
  put "$root/.github/workflows/sub/nested.yml"
  put "$root/.github/dependabot.yml"
  put "$root/.gitlab-ci.yml"
  put "$root/azure-pipelines.yml"
  put "$root/sub/azure-pipelines.yml"
  expect "ci_workflows/github-gitlab-azure" "$root" ci_workflows=4

  # One file per pattern (two for `.eslintrc*`), plus decoys.
  root="$(new_root)"
  put "$root/.eslintrc"
  put "$root/.eslintrc.json"
  put "$root/eslint.config.js"
  put "$root/biome.json"
  put "$root/ruff.toml"
  put "$root/.ruff.toml"
  put "$root/.flake8"
  put "$root/.golangci.yml"
  put "$root/.golangci.yaml"
  put "$root/.shellcheckrc"
  put "$root/.prettierrc"
  put "$root/sub/.flake8"
  put "$root/sub/biome.json"
  expect "lint_configs/every-pattern-at-root" "$root" lint_configs=10

  root="$(new_root)"
  put "$root/.shellcheckrc"
  expect "lint_configs/single-file" "$root" lint_configs=1 typecheck_configs=0

  root="$(new_root)"
  put "$root/tsconfig.json" '{}'
  put "$root/mypy.ini"
  put "$root/pyrightconfig.json" '{}'
  put "$root/tsconfig.base.json" '{}'
  put "$root/sub/tsconfig.json" '{}'
  expect "typecheck_configs/three-root-files" "$root" typecheck_configs=3 lint_configs=0

  # Depth 4 counts (a/b/c/Cargo.toml); depth 5 does not.
  root="$(new_root)"
  put "$root/package.json" '{}'
  put "$root/a/pyproject.toml"
  put "$root/a/b/go.mod"
  put "$root/a/b/c/Cargo.toml"
  put "$root/x/app.csproj"
  put "$root/a/b/c/d/package.json" '{}'
  put "$root/package-lock.json" '{}'
  put "$root/x/requirements.txt"
  expect "package_manifests/five-kinds-to-depth-4" "$root" package_manifests=5
}

# --- repository size -------------------------------------------------------------

run_tracked_cases() {
  local root stub

  if ! have git; then
    case_skip "tracked_files/git-init-added-files" "git not installed"
    case_skip "tracked_files/git-init-nothing-added" "git not installed"
    case_skip "tracked_files/no-git-unknown" "git not installed"
    return 0
  fi

  root="$(new_root)"
  git_fixture "$root"
  expect "tracked_files/git-init-nothing-added" "$root" tracked_files=0

  put "$root/one.txt" "1"
  put "$root/sub/two.txt" "2"
  put "$root/untracked.txt" "3"
  git -C "$root" add one.txt sub/two.txt
  expect "tracked_files/git-init-added-files" "$root" tracked_files=2

  # git hidden from PATH: the same tree is `unknown`, exit code still 0.
  stub="$SCRATCH_ROOT/path-no-git"
  # shellcheck disable=SC2086
  if ! make_stub_path "$stub" $CORE_TOOLS; then
    case_skip "tracked_files/no-git-unknown" "cannot build a PATH without git"
  elif (PATH="$stub" && type -P git >/dev/null 2>&1); then
    case_skip "tracked_files/no-git-unknown" "git still reachable on the stub PATH"
  else
    INSPECT_PATH="$stub"
    run_inspect "$root"
    INSPECT_PATH=""
    assert_out "tracked_files/no-git-unknown" tracked_files=unknown
  fi
}

# --- errors, read-only, spaces ---------------------------------------------------

run_error_cases() {
  local root
  root="$(new_root)"
  put "$root/file.txt" "x"

  expect_usage_error "errors/non-existent-path" "$root/does-not-exist"
  expect_usage_error "errors/two-arguments" "$root" "$root"
  expect_usage_error "errors/empty-string-argument" ""
  expect_usage_error "errors/argument-is-a-file" "$root/file.txt"
}

# --- required tools --------------------------------------------------------------

# One required tool missing from PATH: exit 3, nothing on stdout, the tool named
# on stderr. A usage error is reported first (exit 2) even then.
run_required_tool_cases() {
  local root tool other others stub name

  # A tree that prints non-zero counts when the tools are present.
  root="$(new_root)"
  put "$root/CLAUDE.md" "# rules"
  put "$root/package.json" '{}'
  put "$root/.claude/agents/reviewer.md" "$(printf '%s\n' '---' 'description: Reviews code' '---')"

  for tool in $CORE_TOOLS; do
    name="errors/missing-required-tool-$tool"
    others=""
    for other in $CORE_TOOLS; do
      if [ "$other" != "$tool" ]; then
        others="$others $other"
      fi
    done
    stub="$SCRATCH_ROOT/path-no-$tool"
    # shellcheck disable=SC2086
    if ! make_stub_path "$stub" $others; then
      case_skip "$name" "cannot build a PATH without $tool"
      continue
    elif (PATH="$stub" && type -P "$tool" >/dev/null 2>&1); then
      case_skip "$name" "$tool still reachable on the stub PATH"
      continue
    fi
    INSPECT_PATH="$stub"
    run_inspect "$root"
    INSPECT_PATH=""
    if [ "$RC" -ne 3 ]; then
      case_fail "$name" "exit $RC want 3"
    elif [ -n "$OUT" ]; then
      case_fail "$name" "stdout not empty: $OUT"
    elif ! printf '%s\n' "$ERR" | grep -qF "required tool not found: $tool"; then
      case_fail "$name" "stderr does not say 'required tool not found: $tool': $ERR"
    else
      case_pass "$name"
    fi
  done

  # The argument is checked before the tools.
  name="errors/usage-error-wins-over-missing-tool"
  stub="$SCRATCH_ROOT/path-no-find"
  if [ ! -d "$stub" ] || (PATH="$stub" && type -P find >/dev/null 2>&1); then
    case_skip "$name" "no PATH without find"
  else
    INSPECT_PATH="$stub"
    expect_usage_error "$name" "$root/does-not-exist"
    INSPECT_PATH=""
  fi
}

# A tree that gives every key something to read.
build_rich_tree() {
  local root="$1"
  mkdir -p "$root"
  put "$root/CLAUDE.md" "# rules"
  put "$root/AGENTS.md" "# rules"
  put "$root/.github/copilot-instructions.md" "# rules"
  put "$root/.github/workflows/ci.yml" "name: ci"
  put "$root/.cursor/agents/reviewer.md" "$(printf '%s\n' '---' 'description: mirror' '---')"
  put "$root/.claude/agents/reviewer.md" "$(printf '%s\n' '---' 'description: "Reviews a diff."' '---')"
  put "$root/.claude/agents/tester.md" "$(printf '%s\n' '---' 'description: Runs tests' '---')"
  put "$root/.codex/agents/planner.toml" 'name = "planner"'
  put "$root/.claude/skills/deploy/SKILL.md" "# deploy"
  put "$root/.agents/skills/lint/SKILL.md" "# lint"
  mkdir -p "$root/.cursor/skills"
  ln -s ../../.claude/skills/deploy "$root/.cursor/skills/deploy"
  put "$root/.agent-composer/main.crew.yaml" "name: main"
  put "$root/orchestration-kit.manifest.json" '{}'
  put "$root/.mcp.json" '{"mcpServers": {"a": {}, "b": {}}}'
  put "$root/.shellcheckrc" "disable=SC1090"
  put "$root/tsconfig.json" '{}'
  put "$root/package.json" '{}'
  put "$root/svc/go.mod" "module svc"
  mkdir -p "$root/tests" "$root/svc/test"
}

RICH_COMMON="harness_claude=1 harness_cursor=1 harness_copilot=1 harness_codex=1
  agent_kit_installed=1 composer_crews=1 agent_files=3 claude_agent_files=2
  claude_agent_description_chars=25 claude_agent_description_tokens_est=6
  skill_files=2 test_paths=2 ci_workflows=1 lint_configs=1 typecheck_configs=1
  package_manifests=2"

run_whole_tree_cases() {
  local root before after mcp_want tracked_want

  mcp_want="unknown"
  if have jq; then
    mcp_want="2"
  fi

  # Read-only: the checksum listing is the same before and after a run. With git
  # present the tree is a repository, so `.git` is part of the listing.
  root="$(new_root)"
  build_rich_tree "$root"
  tracked_want="unknown"
  if have git; then
    git_fixture "$root"
    git -C "$root" add package.json tsconfig.json svc/go.mod
    tracked_want="3"
  fi
  before="$(tree_listing "$root")"
  run_inspect "$root"
  after="$(tree_listing "$root")"
  if [ -z "$before" ]; then
    case_fail "read-only/tree-unchanged" "precondition: empty checksum listing"
  elif [ "$before" != "$after" ]; then
    case_fail "read-only/tree-unchanged" "tree changed: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -5 || true)"
  else
    case_pass "read-only/tree-unchanged"
  fi
  # shellcheck disable=SC2086
  assert_out "whole-tree/every-key" $RICH_COMMON "mcp_servers=$mcp_want" "tracked_files=$tracked_want"

  # A project root whose path contains a space.
  root="$(new_root)/my project dir"
  build_rich_tree "$root"
  # shellcheck disable=SC2086
  expect "spaces/root-path-with-space" "$root" $RICH_COMMON "mcp_servers=$mcp_want"
}

# --- guard -----------------------------------------------------------------------

run_guard_cases() {
  local out rc tmp copy key before after

  rc=0
  out="$(TMPDIR="$SCRATCH_ROOT" "$BASH_BIN" "$GUARD" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    case_pass "guard/passes-on-repository"
  else
    case_fail "guard/passes-on-repository" "exit $rc: $out"
  fi

  # A temporary root holding a copy of the skill at the same relative path.
  tmp="$(new_root)"
  copy="$tmp/skills/orchestration-advisor"
  mkdir -p "$tmp/skills"
  cp -R "$SKILL_DIR" "$copy"

  rc=0
  out="$(TMPDIR="$SCRATCH_ROOT" "$BASH_BIN" "$GUARD" "$tmp" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    case_pass "guard/passes-on-unmodified-copy"
  else
    case_fail "guard/passes-on-unmodified-copy" "exit $rc: $out"
    case_fail "guard/fails-when-signal-key-removed" "precondition: the unmodified copy does not pass"
    return 0
  fi

  # Remove one key's table row (the last key of the contract) from the copy.
  key="$(printf '%s\n' "$KEYS" | awk 'NF { last = $0 } END { print last }')"
  before="$(wc -l <"$copy/references/signals.md" | tr -d '[:space:]')"
  grep -v "^|[[:space:]]*\`${key}\`[[:space:]]*|" "$SIGNALS" >"$copy/references/signals.md" || true
  after="$(wc -l <"$copy/references/signals.md" | tr -d '[:space:]')"
  if [ "$((before - after))" -ne 1 ]; then
    case_fail "guard/fails-when-signal-key-removed" "precondition: removed $((before - after)) lines for key ${key}, want 1"
    return 0
  fi

  rc=0
  out="$(TMPDIR="$SCRATCH_ROOT" "$BASH_BIN" "$GUARD" "$tmp" 2>&1)" || rc=$?
  if [ "$rc" -ne 1 ]; then
    case_fail "guard/fails-when-signal-key-removed" "exit $rc want 1"
  elif ! printf '%s\n' "$out" | grep -q '^error: orchestration-advisor:'; then
    case_fail "guard/fails-when-signal-key-removed" "no 'error: orchestration-advisor:' line: $out"
  elif ! printf '%s\n' "$out" | grep -q "^error: orchestration-advisor:.*${key}"; then
    case_fail "guard/fails-when-signal-key-removed" "error does not name the key ${key}: $out"
  else
    case_pass "guard/fails-when-signal-key-removed"
  fi
}

# run_guard [repo-root]: runs the guard; sets GUARD_OUT (stdout and stderr) and
# GUARD_RC. The guard's here-strings make temporary files, so TMPDIR is the
# scratch root.
GUARD_OUT=""
GUARD_RC=0
run_guard() {
  GUARD_RC=0
  GUARD_OUT="$(TMPDIR="$SCRATCH_ROOT" "$BASH_BIN" "$GUARD" "$@" 2>&1)" || GUARD_RC=$?
}

lines_of() {
  wc -l <"$1" | tr -d '[:space:]'
}

# mutate_skill_file <kind> <from> <to>: writes a mutated copy of one skill file.
mutate_skill_file() {
  case "$1" in
    shape-only-in-frontmatter)
      # Every "message bus" (any case) after the frontmatter's closing line.
      awk '
        !body { print; if (NR > 1 && $0 == "---") body = 1; next }
        {
          line = $0
          while ((at = index(tolower(line), "message bus")) > 0) {
            line = substr(line, 1, at - 1) "event relay" substr(line, at + 11)
          }
          print line
        }
      ' "$2" >"$3"
      ;;
    step-heading-inside-fence)
      awk '
        /^## Step 1 .* Detect[ \t]*$/ { print "```"; print; print "```"; next }
        { print }
      ' "$2" >"$3"
      ;;
    report-headings-swapped)
      awk '
        $0 == "## Evidence" { print "## Ruled out"; next }
        $0 == "## Ruled out" { print "## Evidence"; next }
        { print }
      ' "$2" >"$3"
      ;;
    report-heading-deleted)
      awk '$0 != "## Cost note" { print }' "$2" >"$3"
      ;;
    model-id-in-scripts)
      {
        cat "$2"
        printf '%s\n' '# model gpt-4'
      } >"$3"
      ;;
    no-closing-frontmatter)
      # Drop the second line that is exactly "---".
      awk '
        $0 == "---" { seen++; if (seen == 2) next }
        { print }
      ' "$2" >"$3"
      ;;
    report-heading-moved-out-of-fence)
      # "## Cost note" leaves the fenced block and becomes a real heading right
      # after the block's closing fence line.
      awk '
        $0 == "## Cost note" && !moved { moved = 1; next }
        { print }
        moved == 1 && $0 == "```" { print "## Cost note"; moved = 2 }
      ' "$2" >"$3"
      ;;
    crlf-line-endings)
      awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$2" >"$3"
      ;;
    step-heading-inside-tilde-fence)
      awk '
        /^## Step 1 .* Detect[ \t]*$/ { print "~~~"; print; print "~~~"; next }
        { print }
      ' "$2" >"$3"
      ;;
    report-block-tilde-fence)
      # The two fence lines of the report-heading block become tilde fences.
      awk '
        $0 == "```markdown" && !block { print "~~~markdown"; block = 1; next }
        block == 1 && $0 == "```" { print "~~~"; block = 2; next }
        { print }
      ' "$2" >"$3"
      ;;
    audit-headings-swapped)
      awk '
        $0 == "## Enforcement" { print "## Suggestions"; next }
        $0 == "## Suggestions" { print "## Enforcement"; next }
        { print }
      ' "$2" >"$3"
      ;;
    audit-heading-deleted)
      awk '$0 != "## Left alone" { print }' "$2" >"$3"
      ;;
    map-step-heading-deleted)
      awk '$0 !~ /^#+ Step [0-9]+ .* Map[ \t]*$/ { print }' "$2" >"$3"
      ;;
    decide-report-steps-swapped)
      # The last words of the Step 5 and Step 6 headings trade places.
      awk '
        /^#+ Step [0-9]+ .* Decide[ \t]*$/ { sub(/Decide[ \t]*$/, "Report"); print; next }
        /^#+ Step [0-9]+ .* Report[ \t]*$/ { sub(/Report[ \t]*$/, "Decide"); print; next }
        { print }
      ' "$2" >"$3"
      ;;
    audit-rule-bold-removed)
      awk '{ gsub(/\*\*Tier rule\*\*/, "Tier rule"); print }' "$2" >"$3"
      ;;
    signals-row-hook-entries-deleted)
      awk '$0 !~ /^\|[ \t]*`harness_hook_entries`[ \t]*\|/ { print }' "$2" >"$3"
      ;;
    inspect-key-renamed)
      awk '{ sub(/echo "rubric_files=/, "echo \"rubric_count="); print }' "$2" >"$3"
      ;;
    *) return 1 ;;
  esac
}

# expect_guard_rejects <case> <kind> <file> <line-delta> <text>: on a fresh copy
# of the skill under a new temporary root, mutates one file, then wants the
# guard to exit 1 with <text> in its output. Preconditions: the mutation changed
# the file, by exactly <line-delta> lines.
expect_guard_rejects() {
  local name="$1" kind="$2" rel="$3" delta="$4" want="$5"
  local tmp copy got named

  tmp="$(new_root)"
  copy="$tmp/skills/orchestration-advisor"
  mkdir -p "$tmp/skills"
  cp -R "$SKILL_DIR" "$copy"

  if ! mutate_skill_file "$kind" "$SKILL_DIR/$rel" "$copy/$rel"; then
    case_fail "$name" "precondition: the mutation of $rel did not run"
    return 0
  fi
  if cmp -s "$SKILL_DIR/$rel" "$copy/$rel"; then
    case_fail "$name" "precondition: the mutation left $rel unchanged"
    return 0
  fi
  got=$(($(lines_of "$copy/$rel") - $(lines_of "$SKILL_DIR/$rel")))
  if [ "$got" -ne "$delta" ]; then
    case_fail "$name" "precondition: the mutation changed $rel by $got lines, want $delta"
    return 0
  fi
  if [ "$kind" = "shape-only-in-frontmatter" ]; then
    # The shape is still named, and only on the frontmatter description line.
    named="$(grep -i 'message bus' "$copy/$rel" || true)"
    case "$named" in
      description:*) ;;
      *)
        case_fail "$name" "precondition: 'message bus' is not left on the description line only: $named"
        return 0
        ;;
    esac
    if [ "$(printf '%s\n' "$named" | wc -l | tr -d '[:space:]')" != "1" ]; then
      case_fail "$name" "precondition: 'message bus' is left on more than one line"
      return 0
    fi
  fi

  run_guard "$tmp"
  if [ "$GUARD_RC" -ne 1 ]; then
    case_fail "$name" "exit $GUARD_RC want 1: $GUARD_OUT"
  elif ! printf '%s\n' "$GUARD_OUT" | grep -qF -- "$want"; then
    case_fail "$name" "output does not say '$want': $GUARD_OUT"
  else
    case_pass "$name"
  fi
}

run_guard_mutation_cases() {
  expect_guard_rejects "guard/fails-when-shape-only-in-frontmatter" \
    shape-only-in-frontmatter SKILL.md 0 \
    "does not name the shape: message bus"

  expect_guard_rejects "guard/fails-when-step-heading-only-in-fence" \
    step-heading-inside-fence SKILL.md 2 \
    "missing procedure step heading: Detect"

  expect_guard_rejects "guard/fails-when-report-headings-out-of-order" \
    report-headings-swapped SKILL.md 0 \
    "report headings are out of order"

  expect_guard_rejects "guard/fails-when-report-heading-missing" \
    report-heading-deleted SKILL.md -1 \
    "missing report heading: ## Cost note"

  expect_guard_rejects "guard/fails-when-model-id-in-scripts" \
    model-id-in-scripts scripts/inspect.sh 1 \
    "concrete model ID found in scripts/"

  expect_guard_rejects "guard/fails-when-frontmatter-not-closed" \
    no-closing-frontmatter SKILL.md -1 \
    "missing procedure step heading: Detect"
}

# Number of lines of a file that match an awk condition.
count_matching() {
  awk "$1 { n++ } END { print n + 0 }" "$2"
}

# expect_guard_accepts <case> <kind> <file> <line-delta>: on a fresh copy of the
# skill under a new temporary root, mutates one file, then wants the guard to
# exit 0. Preconditions: the mutation changed the file, by exactly <line-delta>
# lines, and left the text the kind promises.
expect_guard_accepts() {
  local name="$1" kind="$2" rel="$3" delta="$4"
  local tmp copy got

  tmp="$(new_root)"
  copy="$tmp/skills/orchestration-advisor"
  mkdir -p "$tmp/skills"
  cp -R "$SKILL_DIR" "$copy"

  if ! mutate_skill_file "$kind" "$SKILL_DIR/$rel" "$copy/$rel"; then
    case_fail "$name" "precondition: the mutation of $rel did not run"
    return 0
  fi
  if cmp -s "$SKILL_DIR/$rel" "$copy/$rel"; then
    case_fail "$name" "precondition: the mutation left $rel unchanged"
    return 0
  fi
  got=$(($(lines_of "$copy/$rel") - $(lines_of "$SKILL_DIR/$rel")))
  if [ "$got" -ne "$delta" ]; then
    case_fail "$name" "precondition: the mutation changed $rel by $got lines, want $delta"
    return 0
  fi
  case "$kind" in
    crlf-line-endings)
      # Every line ends with a carriage return.
      if [ "$(count_matching '/\r$/' "$copy/$rel")" != "$(lines_of "$copy/$rel")" ]; then
        case_fail "$name" "precondition: not every line of $rel ends with a carriage return"
        return 0
      fi
      ;;
    report-block-tilde-fence)
      # One tilde block, and two backtick fence lines fewer than the original.
      got=$(($(count_matching '/^```/' "$SKILL_DIR/$rel") - $(count_matching '/^```/' "$copy/$rel")))
      if [ "$(count_matching '$0 == "~~~markdown"' "$copy/$rel")" != "1" ] ||
        [ "$(count_matching '$0 == "~~~"' "$copy/$rel")" != "1" ] ||
        [ "$got" -ne 2 ]; then
        case_fail "$name" "precondition: the report block of $rel is not fenced by one tilde pair"
        return 0
      fi
      ;;
  esac

  run_guard "$tmp"
  if [ "$GUARD_RC" -ne 0 ]; then
    case_fail "$name" "exit $GUARD_RC want 0: $GUARD_OUT"
  else
    case_pass "$name"
  fi
}

# A symbolic link under scripts/ is not read: the model ID in its target, a
# file outside the skill copy, is not a finding.
run_guard_symlink_case() {
  local name="guard/passes-when-model-id-behind-symlink-in-scripts"
  local tmp copy target link

  tmp="$(new_root)"
  copy="$tmp/skills/orchestration-advisor"
  mkdir -p "$tmp/skills"
  cp -R "$SKILL_DIR" "$copy"
  target="$tmp/outside/notes.sh"
  put "$target" "$(printf '%s\n' '# model gpt-4')"
  link="$copy/scripts/linked.sh"

  if ! ln -s "$target" "$link" 2>/dev/null || [ ! -L "$link" ]; then
    case_skip "$name" "symbolic links are not supported here"
    return 0
  fi
  # Preconditions: the target is outside the copy, and the model ID is readable
  # through the link.
  case "$target" in
    "$copy"/*)
      case_fail "$name" "precondition: the link target is inside the skill copy"
      return 0
      ;;
  esac
  if ! grep -qE 'gpt-[0-9]' "$link" 2>/dev/null; then
    case_fail "$name" "precondition: the model ID cannot be read through the link"
    return 0
  fi

  run_guard "$tmp"
  if [ "$GUARD_RC" -ne 0 ]; then
    case_fail "$name" "exit $GUARD_RC want 0: $GUARD_OUT"
  else
    case_pass "$name"
  fi
}

run_guard_fence_and_link_cases() {
  expect_guard_rejects "guard/fails-when-report-heading-moved-out-of-fence" \
    report-heading-moved-out-of-fence SKILL.md 0 \
    "missing report heading: ## Cost note"

  expect_guard_accepts "guard/passes-on-crlf-line-endings" \
    crlf-line-endings SKILL.md 0

  expect_guard_rejects "guard/fails-when-step-heading-only-in-tilde-fence" \
    step-heading-inside-tilde-fence SKILL.md 2 \
    "missing procedure step heading: Detect"

  run_guard_symlink_case

  expect_guard_accepts "guard/passes-when-report-block-uses-tilde-fence" \
    report-block-tilde-fence SKILL.md 0
}

# --- audit signals: hooks, rules, rubrics, commands, configs, orchestrators ------

# skill_md <file> <name> <body-line>: a SKILL.md with frontmatter and one body line.
skill_md() {
  put "$1" "$(printf '%s\n' '---' "name: $2" 'description: A generic skill' '---' "$3")"
}

run_hook_cases() {
  local root stub

  root="$(new_root)"
  expect "harness_hook_entries/no-files-is-zero" "$root" harness_hook_entries=0 git_hook_files=0

  root="$(new_root)"
  put "$root/.claude/settings.json" '{"hooks": {"x": "not-a-handler"}, "permissions": {}'
  expect "harness_hook_entries/invalid-json-unknown" "$root" harness_hook_entries=unknown

  root="$(new_root)"
  put "$root/.claude/settings.json" '{"hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command"}, {"type": "command"}]}]}}'
  put "$root/.claude/settings.local.json" '{"hooks": {"Stop": [{"hooks": [{"type": "command"}]}]}'
  expect "harness_hook_entries/valid-plus-invalid-unknown" "$root" harness_hook_entries=unknown

  if ! have jq; then
    case_skip "harness_hook_entries/three-files-summed" "jq not installed"
    case_skip "harness_hook_entries/settings-without-hooks-is-zero" "jq not installed"
    case_skip "harness_hook_entries/group-without-hooks-array-is-zero" "jq not installed"
    case_skip "harness_hook_entries/top-level-array-is-zero" "jq not installed"
    case_skip "harness_hook_entries/no-jq-unknown" "jq not installed"
    return 0
  fi

  # 2 + 1 (two matcher groups) + 1 (local) + 2 + 1 (cursor events) = 7.
  root="$(new_root)"
  put "$root/.claude/settings.json" '{"hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command"}, {"type": "command"}]}, {"matcher": "Bash", "hooks": [{"type": "command"}]}]}}'
  put "$root/.claude/settings.local.json" '{"hooks": {"Stop": [{"hooks": [{"type": "command"}]}]}}'
  put "$root/.cursor/hooks.json" '{"version": 1, "hooks": {"preToolUse": [{"command": "a"}, {"command": "b"}], "stop": [{"command": "c"}]}}'
  expect "harness_hook_entries/three-files-summed" "$root" harness_hook_entries=7

  root="$(new_root)"
  put "$root/.claude/settings.json" '{"permissions": {"allow": []}}'
  put "$root/.claude/settings.local.json" '{}'
  expect "harness_hook_entries/settings-without-hooks-is-zero" "$root" harness_hook_entries=0

  root="$(new_root)"
  put "$root/.claude/settings.json" '{"hooks": {"Stop": [{"matcher": "x"}]}}'
  expect "harness_hook_entries/group-without-hooks-array-is-zero" "$root" harness_hook_entries=0

  root="$(new_root)"
  put "$root/.claude/settings.json" '[]'
  expect "harness_hook_entries/top-level-array-is-zero" "$root" harness_hook_entries=0

  # jq hidden while a hook file exists: unknown. With jq the same tree counts 1.
  root="$(new_root)"
  put "$root/.claude/settings.json" '{"hooks": {"Stop": [{"hooks": [{"type": "command"}]}]}}'
  put "$root/package.json" '{}'
  stub="$SCRATCH_ROOT/path-no-jq-hooks"
  # shellcheck disable=SC2086
  if ! make_stub_path "$stub" $CORE_TOOLS; then
    case_skip "harness_hook_entries/no-jq-unknown" "cannot build a PATH without jq"
  elif (PATH="$stub" && type -P jq >/dev/null 2>&1); then
    case_skip "harness_hook_entries/no-jq-unknown" "jq still reachable on the stub PATH"
  else
    run_inspect "$root"
    if [ "$(value_of harness_hook_entries)" != "1" ]; then
      case_fail "harness_hook_entries/no-jq-unknown" "precondition: with jq harness_hook_entries=$(value_of harness_hook_entries) want 1"
    else
      INSPECT_PATH="$stub"
      run_inspect "$root"
      INSPECT_PATH=""
      assert_out "harness_hook_entries/no-jq-unknown" harness_hook_entries=unknown package_manifests=1
    fi
  fi
}

run_git_hook_cases() {
  local root

  # Only .sample files in .git/hooks.
  root="$(new_root)"
  put "$root/.git/hooks/pre-commit.sample" "#"
  put "$root/.git/hooks/commit-msg.sample" "#"
  expect "git_hook_files/only-samples-is-zero" "$root" git_hook_files=0

  root="$(new_root)"
  put "$root/.git/hooks/pre-commit" "#"
  put "$root/.git/hooks/pre-push" "#"
  put "$root/.git/hooks/commit-msg.sample" "#"
  put "$root/.git/hooks/sub/nested" "#"
  expect "git_hook_files/git-hooks-without-sample" "$root" git_hook_files=2

  # .husky/_ is a folder of generated files and is not entered.
  root="$(new_root)"
  put "$root/.husky/pre-commit" "#"
  put "$root/.husky/commit-msg" "#"
  put "$root/.husky/_/husky.sh" "#"
  put "$root/.husky/_/h" "#"
  expect "git_hook_files/husky-underscore-not-entered" "$root" git_hook_files=2

  root="$(new_root)"
  mkdir -p "$root/.husky/_"
  put "$root/.husky/_/husky.sh" "#"
  expect "git_hook_files/husky-underscore-only-is-zero" "$root" git_hook_files=0

  # Each root config file counts 1.
  root="$(new_root)"
  put "$root/lefthook.yml"
  put "$root/.lefthook.yml"
  put "$root/lefthook.yaml"
  put "$root/.lefthook.yaml"
  put "$root/.pre-commit-config.yaml"
  put "$root/sub/lefthook.yml"
  expect "git_hook_files/each-root-config-counts-one" "$root" git_hook_files=5

  root="$(new_root)"
  put "$root/.pre-commit-config.yaml"
  expect "git_hook_files/single-root-config" "$root" git_hook_files=1

  # All three sources add up: 1 + 1 + 1.
  root="$(new_root)"
  put "$root/.git/hooks/pre-commit" "#"
  put "$root/.husky/pre-commit" "#"
  put "$root/lefthook.yml"
  expect "git_hook_files/three-sources-summed" "$root" git_hook_files=3

  # A worktree's .git is a file: nothing to count for the .git/hooks part.
  root="$(new_root)"
  put "$root/.git" "gitdir: ../elsewhere/.git/worktrees/w"
  put "$root/lefthook.yml"
  expect "git_hook_files/dot-git-file-gives-zero-for-hooks-part" "$root" git_hook_files=1

  root="$(new_root)"
  put "$root/.git" "gitdir: ../elsewhere/.git/worktrees/w"
  expect "git_hook_files/dot-git-file-alone-is-zero" "$root" git_hook_files=0
}

run_rule_command_config_cases() {
  local root

  # --- rule_files
  root="$(new_root)"
  put "$root/.cursor/rules/a.mdc"
  put "$root/.cursor/rules/sub/b.mdc"
  put "$root/.cursor/rules/notes.md"
  put "$root/.cursor/rules/c.txt"
  expect "rule_files/mdc-counted-plain-md-not" "$root" rule_files=2

  root="$(new_root)"
  put "$root/.claude/rules/style.md"
  put "$root/.claude/rules/lang/python/typing.md"
  put "$root/.claude/rules/readme.txt"
  expect "rule_files/claude-rules-nested-counted" "$root" rule_files=2

  root="$(new_root)"
  put "$root/.github/instructions/ts.instructions.md"
  put "$root/.github/instructions/deep/go.instructions.md"
  put "$root/.github/instructions/plain.md"
  put "$root/.github/copilot-instructions.md"
  expect "rule_files/github-needs-instructions-md-suffix" "$root" rule_files=2

  root="$(new_root)"
  put "$root/rules/a.md"
  put "$root/.cursor/other/b.mdc"
  expect "rule_files/outside-rule-folders-is-zero" "$root" rule_files=0

  # --- command_files
  root="$(new_root)"
  put "$root/.claude/commands/a.md"
  put "$root/.claude/commands/sub/b.md"
  put "$root/.claude/commands/c.txt"
  put "$root/.cursor/commands/d.md"
  put "$root/.cursor/commands/e.json"
  put "$root/.github/prompts/f.prompt.md"
  put "$root/.github/prompts/g.md"
  expect "command_files/three-locations-and-suffix-rules" "$root" command_files=4

  root="$(new_root)"
  put "$root/.claude/commands/x.txt"
  put "$root/.github/prompts/y.md"
  put "$root/commands/z.md"
  expect "command_files/wrong-suffix-or-place-is-zero" "$root" command_files=0

  # --- harness_config_files
  root="$(new_root)"
  put "$root/.claude/model-routing.json" '{}'
  put "$root/.codex/config.toml" 'model = "x"'
  put "$root/.cursor/routing.yaml"
  put "$root/.claude/extra.jsonc"
  put "$root/.claude/settings.json" '{}'
  put "$root/.claude/settings.local.json" '{}'
  put "$root/.cursor/hooks.json" '{}'
  put "$root/.cursor/mcp.json" '{}'
  put "$root/.claude/notes.md"
  put "$root/.claude/sub/nested.json" '{}'
  put "$root/.codex/sub/nested.toml"
  expect "harness_config_files/routing-and-codex-config-counted" "$root" harness_config_files=4

  root="$(new_root)"
  put "$root/.claude/settings.json" '{}'
  put "$root/.claude/settings.local.json" '{}'
  put "$root/.cursor/hooks.json" '{}'
  put "$root/.cursor/mcp.json" '{}'
  put "$root/.claude/sub/nested.json" '{}'
  put "$root/model-routing.json" '{}'
  expect "harness_config_files/excluded-and-nested-is-zero" "$root" harness_config_files=0
}

run_rubric_cases() {
  local root

  root="$(new_root)"
  put "$root/.claude/rubrics/judge.md"
  put "$root/.cursor/criteria/qa.md"
  put "$root/.codex/x/rubrics/deep.md"
  put "$root/.claude/rubrics/notes.txt"
  expect "rubric_files/rubrics-and-criteria-inside-harness-folders" "$root" rubric_files=3

  # Outside every harness folder: not counted.
  root="$(new_root)"
  put "$root/rubrics/outside.md"
  put "$root/docs/criteria/other.md"
  put "$root/.claude/docs/readme.md"
  expect "rubric_files/rubrics-outside-harness-folders-is-zero" "$root" rubric_files=0

  # *-criteria and *-rubric skill names, once across two roots.
  root="$(new_root)"
  skill_md "$root/.claude/skills/code-criteria/SKILL.md" code-criteria "Checks."
  skill_md "$root/.cursor/skills/code-criteria/SKILL.md" code-criteria "Checks."
  skill_md "$root/.agents/skills/ui-rubric/SKILL.md" ui-rubric "Checks."
  skill_md "$root/.claude/skills/criteria-notes/SKILL.md" criteria-notes "Not a rubric name."
  expect "rubric_files/criteria-and-rubric-skill-names-once" "$root" rubric_files=2 skill_files=3

  # A rubric folder file and a rubric skill add up.
  root="$(new_root)"
  put "$root/.claude/rubrics/judge.md"
  skill_md "$root/.claude/skills/code-criteria/SKILL.md" code-criteria "Checks."
  expect "rubric_files/folder-files-plus-skill-names" "$root" rubric_files=2
}

run_orchestrator_cases() {
  local root

  root="$(new_root)"
  skill_md "$root/.claude/skills/a/SKILL.md" a "Launch SUBAGENTS for each task."
  skill_md "$root/.claude/skills/b/SKILL.md" b "Use the Task Tool."
  skill_md "$root/.claude/skills/c/SKILL.md" c "It spawns workers."
  skill_md "$root/.claude/skills/d/SKILL.md" d "Delegates to a sub-agent."
  skill_md "$root/.claude/skills/e/SKILL.md" e "Formats a changelog."
  expect "orchestrator_skills/case-insensitive-match-plain-skill-not-counted" "$root" \
    orchestrator_skills=4 skill_files=5

  # Distinct across roots.
  root="$(new_root)"
  skill_md "$root/.claude/skills/runner/SKILL.md" runner "Launches subagents."
  skill_md "$root/.cursor/skills/runner/SKILL.md" runner "Launches subagents."
  skill_md "$root/.agents/skills/other/SKILL.md" other "Spawn a helper."
  expect "orchestrator_skills/distinct-across-roots" "$root" orchestrator_skills=2

  root="$(new_root)"
  skill_md "$root/.claude/skills/plain/SKILL.md" plain "Formats text."
  expect "orchestrator_skills/no-words-is-zero" "$root" orchestrator_skills=0

  # An installed copy of orchestration-advisor mentions subagents but is left out.
  root="$(new_root)"
  skill_md "$root/.claude/skills/orchestration-advisor/SKILL.md" orchestration-advisor "Recommends subagents and spawn patterns."
  expect "orchestrator_skills/installed-advisor-copy-is-zero" "$root" orchestrator_skills=0 skill_files=1

  # The exclusion follows the frontmatter name; other skills are still counted.
  root="$(new_root)"
  skill_md "$root/.claude/skills/orchestration-advisor/SKILL.md" orchestration-advisor "Recommends subagents."
  skill_md "$root/.cursor/skills/real-one/SKILL.md" real-one "Spawn subagents."
  expect "orchestrator_skills/advisor-excluded-others-counted" "$root" orchestrator_skills=1
}

# A synthetic two-tier orchestration tree. It mirrors
# tests/orchestration-advisor/fixtures/audit-scenario.md at small scale: a
# program-level orchestrator skill that launches a feature orchestrator skill,
# which launches agents (implementer, judge, test writer), with hooks, rules,
# rubrics, a model-routing config and a goals folder.
build_two_tier_tree() {
  local root="$1"
  mkdir -p "$root"
  skill_md "$root/.claude/skills/program-orchestrator/SKILL.md" program-orchestrator "Launch a feature orchestrator per work package using subagents."
  skill_md "$root/.claude/skills/feature-orchestrator/SKILL.md" feature-orchestrator "Spawn the implementer, the judge and the test writer."
  skill_md "$root/.claude/skills/judge-criteria/SKILL.md" judge-criteria "Checklist the judge loads."
  skill_md "$root/.claude/skills/changelog-helper/SKILL.md" changelog-helper "Formats a changelog."
  put "$root/.claude/agents/implementer.md" "$(printf '%s\n' '---' 'name: implementer' 'description: Implements a task' '---')"
  put "$root/.claude/agents/judge.md" "$(printf '%s\n' '---' 'name: judge' 'description: Judges a diff' '---')"
  put "$root/.claude/agents/test-writer.md" "$(printf '%s\n' '---' 'name: test-writer' 'description: Writes tests' '---')"
  put "$root/.claude/settings.json" '{"hooks": {"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command"}, {"type": "command"}]}], "Stop": [{"hooks": [{"type": "command"}]}]}}'
  put "$root/.cursor/hooks.json" '{"hooks": {"preToolUse": [{"command": "a"}, {"command": "b"}]}}'
  put "$root/.claude/rules/style.md"
  put "$root/.cursor/rules/edit-guard.mdc"
  put "$root/.cursor/rules/notes.md"
  put "$root/.claude/rubrics/judge.md"
  put "$root/.claude/criteria/qa.md"
  put "$root/.claude/commands/feature.md"
  put "$root/.claude/model-routing.json" '{}'
  put "$root/.pre-commit-config.yaml"
  put "$root/.husky/pre-commit" "#"
  put "$root/_memory/goals/g1/goal.md" "# goal"
  put "$root/_memory/goals/g1/task-01.md" "# task"
  mkdir -p "$root/tests"
}

count_nonblank() {
  printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'
}

run_two_tier_cases() {
  local root hooks_want before after

  root="$(new_root)"
  build_two_tier_tree "$root"
  hooks_want="unknown"
  if have jq; then
    hooks_want="5"
  fi
  # 25 keys, all asserted. tracked_files is unknown: not a git work tree.
  expect "two-tier-tree/all-25-keys" "$root" \
    harness_claude=1 harness_cursor=1 harness_copilot=0 harness_codex=0 \
    agent_kit_installed=0 composer_crews=0 \
    agent_files=3 claude_agent_files=3 \
    claude_agent_description_chars=42 claude_agent_description_tokens_est=10 \
    skill_files=4 mcp_servers=0 test_paths=1 ci_workflows=0 lint_configs=0 \
    typecheck_configs=0 package_manifests=0 tracked_files=unknown \
    "harness_hook_entries=$hooks_want" git_hook_files=2 rule_files=2 \
    rubric_files=3 command_files=1 harness_config_files=1 orchestrator_skills=2

  # The contract has exactly 25 keys, and the run printed all of them.
  if [ "$(count_nonblank "$KEYS")" -ne 25 ]; then
    case_fail "two-tier-tree/contract-has-25-keys" "signals.md lists $(count_nonblank "$KEYS") keys"
  else
    run_inspect "$root"
    if [ "$(count_nonblank "$OUT")" -ne 25 ]; then
      case_fail "two-tier-tree/contract-has-25-keys" "inspect.sh printed $(count_nonblank "$OUT") lines, want 25"
    else
      case_pass "two-tier-tree/contract-has-25-keys"
    fi
  fi

  before="$(tree_listing "$root")"
  run_inspect "$root"
  after="$(tree_listing "$root")"
  if [ "$before" != "$after" ]; then
    case_fail "two-tier-tree/read-only" "tree changed"
  else
    case_pass "two-tier-tree/read-only"
  fi
}

# --- guard: audit-mode content contract --------------------------------------------

# expect_guard_rejects_removed <case> <rel> <text>: a copy of the skill without
# one file must make the guard exit 1 with <text>.
expect_guard_rejects_removed() {
  local name="$1" rel="$2" want="$3"
  local tmp copy
  tmp="$(new_root)"
  copy="$tmp/skills/orchestration-advisor"
  mkdir -p "$tmp/skills"
  cp -R "$SKILL_DIR" "$copy"
  if [ ! -f "$copy/$rel" ]; then
    case_fail "$name" "precondition: $rel is not in the skill"
    return 0
  fi
  rm -f "${copy:?}/${rel:?}"
  if [ -e "$copy/$rel" ]; then
    case_fail "$name" "precondition: $rel was not removed"
    return 0
  fi
  run_guard "$tmp"
  if [ "$GUARD_RC" -ne 1 ]; then
    case_fail "$name" "exit $GUARD_RC want 1: $GUARD_OUT"
  elif ! printf '%s\n' "$GUARD_OUT" | grep -qF -- "$want"; then
    case_fail "$name" "output does not say '$want': $GUARD_OUT"
  else
    case_pass "$name"
  fi
}

run_guard_audit_cases() {
  expect_guard_rejects_removed "guard/fails-when-audit-md-missing" \
    references/audit.md "missing required path: skills/orchestration-advisor/references/audit.md"

  expect_guard_rejects_removed "guard/fails-when-report-audit-md-missing" \
    references/report-audit.md "missing required path: skills/orchestration-advisor/references/report-audit.md"

  expect_guard_rejects "guard/fails-when-audit-headings-out-of-order" \
    audit-headings-swapped references/report-audit.md 0 \
    "audit report headings are out of order"

  expect_guard_rejects "guard/fails-when-audit-heading-missing" \
    audit-heading-deleted references/report-audit.md -1 \
    "missing audit report heading: ## Left alone"

  expect_guard_rejects "guard/fails-when-map-step-heading-missing" \
    map-step-heading-deleted SKILL.md -1 \
    "missing procedure step heading: Map"

  expect_guard_rejects "guard/fails-when-decide-and-report-steps-swapped" \
    decide-report-steps-swapped SKILL.md 0 \
    "procedure step headings are out of order at: Report"

  expect_guard_rejects "guard/fails-when-audit-rule-name-not-bold" \
    audit-rule-bold-removed references/audit.md 0 \
    "missing audit rule: **Tier rule**"

  expect_guard_rejects "guard/fails-when-new-key-row-missing-in-signals-md" \
    signals-row-hook-entries-deleted references/signals.md -1 \
    "no table row for signal key: harness_hook_entries"

  expect_guard_rejects "guard/fails-when-new-key-missing-in-inspect-sh" \
    inspect-key-renamed scripts/inspect.sh 0 \
    "does not print signal key: rubric_files"
}

# --- exit trap -------------------------------------------------------------------

# A copy of this suite that stops inside its first case function (an injected
# `false` under `set -e`) must say so, still print the summary line, and exit
# non-zero. The copy stops before any case runs, so it never reaches this case.
run_abort_cases() {
  local name="summary/abort-says-so-prints-summary-exits-non-zero"
  local self dir copy restored errf at out rc last err

  self="$HERE/${BASH_SOURCE[0]##*/}"
  dir="$SCRATCH_ROOT/suite-copy"
  copy="$dir/tests/orchestration-advisor/run.sh"
  restored="$dir/restored.sh"
  errf="$dir/stderr.txt"
  if ! mkdir -p "$dir/tests/orchestration-advisor" "$dir/tmp" 2>/dev/null; then
    case_skip "$name" "cannot create a folder for the suite copy"
    return 0
  fi

  at="$(awk '$0 == "run_contract_cases() {" { print NR; exit }' "$self" 2>/dev/null || true)"
  if [ -z "$at" ]; then
    case_fail "$name" "precondition: no 'run_contract_cases() {' line in $self"
    return 0
  fi
  awk -v at="$at" '{ print } NR == at { print "  false" }' "$self" >"$copy"

  # Precondition: the copy is the suite plus exactly one line, `false`, right
  # after the function's opening line.
  awk -v skip="$((at + 1))" 'NR != skip { print }' "$copy" >"$restored"
  if [ "$(($(lines_of "$copy") - $(lines_of "$self")))" -ne 1 ] ||
    [ "$(awk -v n="$((at + 1))" 'NR == n { print }' "$copy")" != "  false" ] ||
    ! cmp -s "$restored" "$self"; then
    case_fail "$name" "precondition: the copy does not differ from the suite by exactly one line"
    return 0
  fi

  # The copy gets its own TMPDIR under the scratch root.
  rc=0
  out="$(TMPDIR="$dir/tmp" ORCHESTRATION_ADVISOR_SKILL_DIR="$SKILL_DIR" \
    "$BASH_BIN" "$copy" 2>"$errf")" || rc=$?
  err="$(cat "$errf")"
  last="$(printf '%s\n' "$out" | awk '{ last = $0 } END { print last }')"
  if [ "$rc" -eq 0 ]; then
    case_fail "$name" "exit 0 want non-zero"
  elif ! printf '%s\n' "$err" | grep -qF "ABORTED: suite stopped before all cases ran"; then
    case_fail "$name" "stderr does not say 'ABORTED: suite stopped before all cases ran': $err"
  elif [ "$last" != "PASS: 0 FAIL: 0 SKIP: 0" ]; then
    case_fail "$name" "last stdout line is '$last' want 'PASS: 0 FAIL: 0 SKIP: 0'"
  else
    case_pass "$name"
  fi
}

# --- main ------------------------------------------------------------------------

KEYS="$(keys_from_contract)"

main() {
  if [ -z "$KEYS" ]; then
    case_fail "contract/keys-parsed-from-signals-md" "no keys found under '## Keys' in $SIGNALS"
    print_summary
    return 1
  fi
  if [ ! -f "$INSPECT" ]; then
    case_fail "contract/inspect-script-exists" "missing $INSPECT"
    print_summary
    return 1
  fi

  run_contract_cases
  run_harness_cases
  run_agent_cases
  run_description_cases
  run_wc_fallback_cases
  run_wc_failure_cases
  run_skill_cases
  run_unreadable_skill_cases
  run_interrupted_run_cases
  run_skip_list_cases
  run_mcp_cases
  run_project_cases
  run_tracked_cases
  run_error_cases
  run_required_tool_cases
  run_whole_tree_cases
  run_hook_cases
  run_git_hook_cases
  run_rule_command_config_cases
  run_rubric_cases
  run_orchestrator_cases
  run_two_tier_cases
  run_guard_cases
  run_guard_mutation_cases
  run_guard_fence_and_link_cases
  run_guard_audit_cases
  run_abort_cases

  print_summary
  [ "$FAIL" -eq 0 ]
}

main "$@"
