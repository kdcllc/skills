# greek-to-hebrew

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/greek-to-hebrew)

Traces a New Testament Greek word to the Old Testament Hebrew words behind it through the Septuagint (LXX), using free web tools. Use it for Bible word studies, Strong's number lookups, LXX occurrences, first mentions, or NT quotations and allusions of the OT.

## Install

```bash
npx skills add kdcllc/skills --skill greek-to-hebrew
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills greek-to-hebrew` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#greek-to-hebrew/vX.Y.Z --skill greek-to-hebrew` ([releases](https://github.com/kdcllc/skills/releases)) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Give an NT reference and a target word, Greek lemma, or Greek Strong's number. If you give only an English word, the agent asks for a verse. It can give a concise result or a broad survey of LXX equivalents.

Example prompts:

- "Ephesians 2:8 grace"
- "Trace the Greek word in John 1:14 for 'truth' back to the Hebrew."
- "Show the LXX occurrences of G5485 and the Hebrew behind them."

The result is a "Word Trace" with the Greek lemma and Strong's number, LXX count and first mention, a table of Hebrew equivalents, a confidence level, alternatives, and the sources checked. It treats Strong's numbers as lookup keys and the LXX as translation evidence, not proof of equivalence. A first mention is a heuristic only.

## Requirements

- An agent that can fetch web pages
- Network access to Blue Letter Bible, BibleHub, STEP Bible, studybible.info and StudyLight (the skill falls back between them)

## License

CC BY-SA 4.0 (see [LICENSE.txt](LICENSE.txt)), unlike the rest of the pack, which is MIT.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/tools.md](references/tools.md) — URL patterns for each tool and a failure playbook
- [references/methodology.md](references/methodology.md) — the research and scholarly caveats behind the method
