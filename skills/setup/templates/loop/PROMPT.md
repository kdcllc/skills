Invoke the `auto-loop` skill in driver-dispatched mode: run story `%%STORY_ID%%`
from `_goals/backlog.md` through ONE iteration — orchestration flow, judge gates,
commit only on an APPROVED audit with green targeted tests, then stop. This story
was already selected and validated by the driver: never re-evaluate eligibility
or pick another. Write learning/escalation lines to `%%OUTBOX_DIR%%/learnings.md`
and `%%OUTBOX_DIR%%/escalations.md` (names pinned) — never the shared memory
files directly. The driver fills `%%STORY_ID%%`/`%%OUTBOX_DIR%%` at dispatch, not
setup: end with the `ITERATION:` line naming `%%STORY_ID%%`. Never push.
