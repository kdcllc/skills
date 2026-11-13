#!/usr/bin/env bash
# Stand-in for the claude CLI, used only by the eval self-test and the runner's scratch checks.
# Accepts the CLI arguments, ignores all but -p. Behaviour from EVAL_STUB_MODE:
#   solve    copy the overlay EVAL_STUB_SOLUTION into cwd (honouring .delete), print the fixed JSON
#   noop     change nothing, print the fixed JSON
#   garbage  change nothing, print a non-JSON line
#   sleep    sleep 5 seconds, change nothing
# EVAL_STUB_PROBE (a file path) receives grade_visible, prompt_has_feature and claude_env lines.
set -u

prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p)
      if [ $# -ge 2 ]; then prompt="$2"; shift 2; else shift; fi
      ;;
    *) shift ;;
  esac
done

mode="${EVAL_STUB_MODE-}"
case "$mode" in
  solve | noop | garbage | sleep) ;;
  *)
    echo "stub-cli: EVAL_STUB_MODE must be solve, noop, garbage or sleep (got '${mode}')" >&2
    exit 2
    ;;
esac

if [ -n "${EVAL_STUB_PROBE-}" ]; then
  gv=no
  if [ -n "$(find . \( -name grade.sh -o \( -name solution -a -type d \) \) -print -quit 2>/dev/null)" ]; then
    gv=yes
  fi
  pf=no
  case "$prompt" in /feature*) pf=yes ;; esac
  ce=no
  for v in CLAUDECODE CLAUDE_EFFORT CLAUDE_PID CLAUDE_AGENT_SDK_VERSION \
    CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_EMIT_STARTUP_TIMING CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING \
    CLAUDE_CODE_ENABLE_TASKS CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
    CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN \
    CLAUDE_CODE_QUESTION_PREVIEW_FORMAT CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_STARTUP_FAILURE_RESULTS CLAUDE_CODE_SSE_PORT; do
    if [ -n "${!v+x}" ]; then ce=yes; fi
  done
  {
    printf 'grade_visible=%s\n' "$gv"
    printf 'prompt_has_feature=%s\n' "$pf"
    printf 'claude_env=%s\n' "$ce"
  } > "$EVAL_STUB_PROBE"
fi

fixed_json() {
  printf '%s\n' '{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"is_error":false,"result":"stub"}'
}

case "$mode" in
  solve)
    sol="${EVAL_STUB_SOLUTION-}"
    if [ -z "$sol" ] || [ ! -d "$sol" ]; then
      echo "stub-cli: EVAL_STUB_SOLUTION is not a directory: '${sol}'" >&2
      exit 2
    fi
    cp -R "$sol/." . || exit 2
    rm -f ./.delete
    if [ -f "$sol/.delete" ]; then
      while IFS= read -r rel || [ -n "$rel" ]; do
        [ -n "$rel" ] || continue
        case "$rel" in
          /* | ../* | */../* | .. ) continue ;;
        esac
        rm -rf -- "./$rel"
      done < "$sol/.delete"
    fi
    fixed_json
    ;;
  noop) fixed_json ;;
  garbage) printf '%s\n' 'stub: not json' ;;
  sleep) sleep 5 ;;
esac
exit 0
