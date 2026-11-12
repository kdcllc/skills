# Audit report

The audience is the owners of the existing system. They know their flows; what they need is a map they can check, the evidence behind each suggestion, and what was left alone. Every statement about the current system cites a file. The procedure that produces the content is in [audit.md](audit.md); [../SKILL.md](../SKILL.md) Step 6 chooses this file when audit mode was chosen.

## Chat summary

Chat gets a short summary, in this order:

1. Mode and the values behind it: the mode chosen (audit), and the signal values that suggested it (`agent_files`, `agent_kit_installed`, `composer_crews`, `orchestrator_skills`).
2. Headline: one or two sentences, per the Honesty rule.
3. Systems and tiers: one table (system, entry point, tier).
4. Top suggestions: each with the failure it fixes and the enforcer that covers its gate afterwards.
5. What was left alone, in a line or two.

Then the save offer: ask whether to save the full report as a markdown file, and let the user choose the path. Write nothing without a yes. If the user says no, stop; the chat summary is the report.

## Full report

When the user says yes, write exactly these headings, in this order, and nothing else at `## ` level:

```markdown
## Headline
## Systems and tiers
## Current-state map
## Enforcement
## Current vs recommended
## Suggestions
## Left alone
## Harness notes
## Cost note
## How to check this
## Appendix: shapes in play
```

Keep mermaid diagrams out of any fenced `markdown` block in this skill's files; in the saved report, diagrams are ordinary fenced `mermaid` blocks under Current-state map.

- **Headline** — one or two sentences. State the Honesty rule in full: when no material change is found, the headline says the current design fits and lists the small fixes; a fold of one or two agents is never the headline unless it is the only material change and is labeled as small.
- **Systems and tiers** — a table: system, entry point, started by, tier, launches. A higher tier shows its boundary only.
- **Current-state map** — one mermaid diagram per system (gates as decision nodes, enforcers labeled) plus the tier boundary diagram. No diagram for a shape not in use.
- **Enforcement** — a table: gate or rule, enforcer, file, enforced or prompt-only. Include every hook, git hook, rubric, CI workflow and routing config found.
- **Current vs recommended** — per system, a table of the current design next to the recommended one. Rows with no change say "unchanged".
- **Suggestions** — numbered. For each: the problem fixed (a visible failure), evidence with file paths and signal values, the enforcer after the change (and whether it must change), effort, risk, confidence.
- **Left alone** — each item and why: working, higher tier (Tier rule), or no evidence.
- **Harness notes** — same rules as the design report in SKILL.md Step 6: keep `inferred` and `not checked` marks; say the statements may be out of date when today is past the re-check date in [patterns.md](patterns.md).
- **Cost note** — same rules as the design report: set the 3 to 10 times token figure (with its source and date, from SKILL.md Step 6) against the owner's cost tolerance; say so when no suggestion adds agents.
- **How to check this** — same rules as the design report: about 10 representative tasks, run more than once on the current setup and on the changed one, compare completion, tokens and wall time. The experiment changes one suggestion at a time and looks at which tasks flipped.
- **Appendix: shapes in play** — only the shapes found in the map, each with its definition and main failure mode from [patterns.md](patterns.md). Never a catalog of shapes not in use.

## Do not

- Do not lead with a catalog of all six shapes.
- Do not list a shape already in use as ruled out.
- Do not present an existing flow as a new recommendation.
- Do not use agent count as the measure of the change.
- Do not drop hooks or other enforcers.
