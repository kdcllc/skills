---
name: mp3-normalize
description: "Normalize or equalize MP3 loudness with mp3gain (lossless, no re-encoding). Use when the user wants consistent volume across MP3 files, batch gain adjustment, album or track normalization, or mp3gain-based loudness fixes."
license: MIT
compatibility: GitHub Copilot CLI extension; Node 20+; mp3gain
metadata:
  version: "1.0.0"
---

# MP3 Normalize (`mp3-normalize`)

Copilot CLI extension that batch-normalizes MP3 files with **mp3gain**. Files are copied into a `normalized/` subfolder; originals are never modified. Gain is applied in the MP3 headers only (no re-encoding).

## Install

1. Install the skill: `npx skills add kdcllc/skills --skill mp3-normalize`
2. Copilot CLI loads extensions from `~/.copilot/extensions/<name>/` (user) or `.github/extensions/<name>/` (project). Each location is an immediate subdirectory named `<name>` with `extension.mjs` at its root; the folder name becomes the extension name (keep it `mp3-normalize`). Link or copy the installed skill folder there, for example:
   `ln -s "$(pwd)/.agents/skills/mp3-normalize" ~/.copilot/extensions/mp3-normalize`
   (Adjust the source path to wherever `npx skills` installed the skill.)
3. Restart Copilot CLI or run `/clear`. First load runs `npm install` in the skill folder.
4. Install `mp3gain`. See [references/installation.md](references/installation.md).

Use `/extensions manage` and logs under `~/.copilot/logs/extensions/` when troubleshooting extension load. See [About CLI extensions](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-extensions).

**Claude Code, Cursor, Codex:** the extension does not load there. Run `mp3gain` directly: track mode `-c -p -r`, album mode `-c -p -a`, optional `-d N` for dB offset from 89 (documented in [references/development.md](references/development.md)).

## Usage

### Slash command

```
/mp3-normalize
/mp3-normalize /home/user/Music/Album
```

### Agent tool `normalize_mp3`

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `sourceDir` | string | yes | — | Folder containing `.mp3` files (top level only) |
| `mode` | string | no | `track` | `track` or `album` |
| `targetDb` | number | no | `89` | Target loudness in dB (webview UI enforces 70–105; the agent tool does not) |

### Webview tools

`mp3_normalize_show`, `mp3_normalize_eval`, `mp3_normalize_close`.

## Modes

| Mode | Behavior |
|------|----------|
| `track` | Each file normalized independently to the target dB |
| `album` | All files normalized together; relative loudness preserved |

## Target dB (reference)

| dB | Typical use |
|----|-------------|
| 83 | Quiet background |
| 89 | mp3gain default (CD-like) |
| 95 | Podcast / spoken word |
| 98+ | Very loud material |

## Output

Normalized copies live in `<sourceDir>/normalized/` with the same filenames.

## Known limitations

- Only `.mp3` files in the top level of `sourceDir` (no subfolders).
- Cancel is best-effort; the current file may finish before stop.
- Requires `mp3gain` on `PATH`.

## References

- [references/installation.md](references/installation.md) — mp3gain per OS
- [references/development.md](references/development.md) — code flow and mp3gain flags
