Invoke the `auto-loop` skill and follow it for exactly ONE iteration: pick one story
from `_goals/backlog.md`, run it through the orchestration flow with judge gates,
commit only on an APPROVED audit with green targeted tests, update the backlog and
learnings, then stop. Obey the skill's output contract — end with an `ITERATION:` line,
or `<promise>COMPLETE</promise>` if no eligible stories remain. Do exactly one story.
Never push.
