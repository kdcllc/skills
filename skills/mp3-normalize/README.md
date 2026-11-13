# mp3-normalize

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/mp3-normalize)

A Copilot CLI extension that batch-normalizes MP3 loudness with mp3gain. Files are copied into a `normalized/` subfolder, originals are never modified, and gain is applied in the MP3 headers only, with no re-encoding.

## Install

```bash
npx skills add kdcllc/skills --skill mp3-normalize
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills mp3-normalize` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#mp3-normalize/vX.Y.Z --skill mp3-normalize` ([releases](https://github.com/kdcllc/skills/releases)) |

Copilot CLI extension setup: after `npx skills add`, link or copy the installed skill folder to `~/.copilot/extensions/mp3-normalize/` (user) or `.github/extensions/mp3-normalize/` (project). The folder name becomes the extension name, so keep it `mp3-normalize`. Example, adjusting the source path to where `npx skills` installed it:

```bash
ln -s "$(pwd)/.agents/skills/mp3-normalize" ~/.copilot/extensions/mp3-normalize
```

Then restart Copilot CLI or run `/clear`. The first load runs `npm install` in the skill folder. Use `/extensions manage` and the logs under `~/.copilot/logs/extensions/` if the extension does not load.

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

In Copilot CLI, use the slash command:

```
/mp3-normalize
/mp3-normalize /home/user/Music/Album
```

Or ask the agent to call the `normalize_mp3` tool with `sourceDir` (required), `mode` and `targetDb`.

- `track` mode (default) normalizes each file independently. `album` mode normalizes the files together and keeps their relative loudness.
- `targetDb` defaults to 89, the mp3gain default. The webview accepts 70 to 105; the agent tool does not enforce that range.

Example prompts:

- "Normalize the MP3s in ~/Music/Album in album mode."
- "Even out the volume of the MP3s in ~/Podcasts at 95 dB."

Results are written to `<sourceDir>/normalized/` with the same filenames. Only `.mp3` files at the top level of `sourceDir` are processed, and cancelling is best-effort.

On Claude Code, Cursor and Codex the extension does not load. An agent can run `mp3gain` directly: `-c -p -r` for track mode, `-c -p -a` for album mode, and optionally `-d N` for a dB offset from 89.

## Requirements

- GitHub Copilot CLI with extension support, and Node 20+.
- `mp3gain` on `PATH`, for example `sudo apt install mp3gain` on Ubuntu or Debian. Other distros are covered in the installation reference.
- The source folder must be writable, because the skill creates `normalized/` inside it.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/installation.md](references/installation.md) — mp3gain per OS
- [references/development.md](references/development.md) — code flow and mp3gain flags
