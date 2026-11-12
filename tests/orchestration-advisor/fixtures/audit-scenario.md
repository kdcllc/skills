# Audit-mode regression scenario: Project X

This file is a regression scenario for the audit mode of `orchestration-advisor`. It is not a skill and has no front matter. It describes an anonymized, generic mature orchestration system and lists the checks an evaluator applies to audit-mode output.

## How the check is run

An evaluator reads `skills/orchestration-advisor/SKILL.md`, `references/audit.md` and `references/report-audit.md`, walks the procedure over the scenario below on paper (Detect, Inspect, Ask about the workload, Map, Decide, Report in audit mode), and marks each check C1 to C7 as pass or fail, quoting the passage of the skill or of the paper report that satisfies it. A check with no satisfying passage fails.

## Project X

Project X is a large repository that already runs a mature orchestration setup.

- **Harness**: one harness, with project agents, skills, hooks and rules in its project folders.
- **Agents**: a dozen or more, in generic roles:
  - a contract (spec) writer;
  - a judge, and a second, more skeptical judge;
  - a QA judge and a QA evidence gatherer;
  - a task implementer;
  - a test writer;
  - helper agents at two cost tiers (a cheaper fast tier and a mid tier);
  - an exploration agent;
  - design and critique agents;
  - a program-level spec writer and a program-level judge.
- **Skills**: dozens, including the orchestrator skills below, reference skills and checklists.
- **Hooks**: an edit guard (blocks writes outside a task's declared file set), model routing (picks the model tier per agent), and stop telemetry (records each run's end).
- **Rubric files**: judge rubrics and criteria files that the judges load.
- **Model-routing config**: a config file that maps agent roles to model tiers.
- **Goals folder**: a folder written by the orchestrators. Goals, task files and verdicts live there, and every orchestrator and agent reads and writes it as shared state.
- **Orchestrators** (each a skill):
  - a feature orchestrator: goal, tasks, implementer, judge, fix cycles, final audit;
  - a test orchestrator: test contract, test writer, judge;
  - a design orchestrator: design agent, critique agent, rounds;
  - a refactor fan-out: a wave of child runs, each of which runs the feature flow on one slice;
  - a program orchestrator: its workers are feature orchestrators, each launched per work package, with a program-level spec writer and judge gating the whole.
- **Outside the harness**: a pull-request event router (a CI workflow) that starts a review flow when a pull request opens.
- **Test writer, two roles**: the feature flow launches the test writer to add tests for one task, under a task contract. The test flow launches the same agent to write the tests of a whole feature, under a test contract. The contracts differ.

## Reviewer feedback as checks

Each check is a pass condition on the audit-mode output.

- **C1** Existing flows are mapped as existing. The shared-state goals folder and the orchestrator-subagent shape are named as in use, never listed as ruled out and never proposed as new.
- **C2** Hooks and other enforcers (the edit guard, model routing, stop telemetry, rubrics, the pull-request router) appear in the Enforcement section, and every suggestion names the enforcer that covers the affected gate after the change. A suggestion with no enforcer is not recommended.
- **C3** Overlap is judged per flow. The test writer's two roles (task tests under the feature flow, feature tests under the test flow) are assessed separately, and agents are not called overlapping from their descriptions alone.
- **C4** The program orchestrator and the refactor fan-out are identified as higher tiers by the general pattern (their workers are themselves orchestration systems), mapped only at their boundary, kept as their own systems, and not re-architected or folded into the feature flow without the user opting in.
- **C5** The headline is not a fold of one or two agents. It follows the honesty rule: when no material change is found, it says the current design fits and lists the small fixes.
- **C6** The full report follows the headings of `references/report-audit.md` in order and has a mermaid map per system, plus the tier boundary diagram.
- **C7** The generic catalog of six shapes does not lead the report. The appendix covers only the shapes in play.
