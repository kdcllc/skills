# Agent-kit maintainer docs

This folder holds the **developer guide** for the AI Orchestration Kit (`skills/agent-kit/`).
It is maintainer material: it does not ship with `/agent-kit` installs.

## Contents

| Area | Location |
|------|----------|
| Guide index (workflows, loop, evaluation, memory) | [guide/README.md](guide/README.md) |
| Architecture (components, sequences, state) | [guide/architecture.md](guide/architecture.md) |
| Research briefs (curated studies + status) | [_memory/research/README.md](../../_memory/research/README.md) |
| Canonical orchestration template (placeholders, guards) | [skills/agent-kit/templates/ORCHESTRATION.md](../../skills/agent-kit/templates/ORCHESTRATION.md) |

## Capability snapshot

The kit provides a seven-phase `/feature` flow with fresh-context workers and evaluators,
optional `/research` before implementation, a staged test ladder, and an optional
autonomous loop with driver-owned dispatch, write-set admission, slot/worktree controls,
and aggregated exit codes. After fix-cycle exhaustion, goals may run the **continuation ladder** (rungs 5→4→6); see
[autonomous-escalation.md](../../_memory/research/autonomous-escalation.md) for the study
that shaped that policy.

Cursor installs receive a **self-contained** `.cursor/` tree (skills, architecture doc,
model map, agents) with no cross-harness reads at runtime.

Version history: [CHANGELOG.md](../../skills/agent-kit/CHANGELOG.md).
