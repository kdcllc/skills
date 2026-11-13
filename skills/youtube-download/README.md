# youtube-download

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/youtube-download)

A Copilot CLI extension that downloads YouTube video or audio (MP3, M4A, WAV), saves metadata and thumbnails, and converts English subtitles to Markdown or plain-text transcripts. Use it when you want to download a video, rip audio, or get a transcript.

## Install

```bash
npx skills add kdcllc/skills --skill youtube-download
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills youtube-download` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#youtube-download/vX.Y.Z --skill youtube-download` ([releases](https://github.com/kdcllc/skills/releases)) |

Copilot CLI extension setup: after `npx skills add`, link or copy the installed skill folder to `~/.copilot/extensions/youtube-download/` (user) or `.github/extensions/youtube-download/` (project). The folder name becomes the extension name, so keep it `youtube-download`. Example, adjusting the source path to where `npx skills` installed it:

```bash
ln -s "$(pwd)/.agents/skills/youtube-download" ~/.copilot/extensions/youtube-download
```

Then restart Copilot CLI or run `/clear`. The first load runs `npm install` in the skill folder automatically. Use `/extensions manage` and the logs under `~/.copilot/logs/extensions/` if the extension does not load.

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

In Copilot CLI, open the desktop webview with the slash command:

```
/youtube-download
/youtube-download https://www.youtube.com/watch?v=VIDEO_ID
```

Or ask the agent to call the `youtube_download` tool. Its parameters are `url` and `outputPath` (both required), `format` (`best`, `audio`, `mp4`, `mkv`, `360p`, `720p`, `1080p`; default `best`), `metadata` (default true), `transcriptEnabled`, `transcriptOnly`, `transcriptOutput` (`md` or `txt`) and `removeTimestamps`.

Example prompts:

- "Download this video as MP3 into ~/Music: <url>"
- "Get the English transcript of this video as Markdown, no media: <url>"

Output goes to your chosen directory as `Title.ext`, `Title.info.json`, `Title.jpg`, `Title.en.vtt` and `Title.en.md` (or `.txt`). The webview also offers `audio-m4a`, `audio-wav` and `best-video`.

On Claude Code, Cursor and Codex the Node extension does not load. An agent can run `yt-dlp` directly with the format flags listed in the development reference.

Known limits: one active download at a time in the webview, playlists and live streams are not fully supported, transcripts cover English tracks only, and region-locked or private videos may fail.

## Requirements

- GitHub Copilot CLI with extension support, and Node 20+.
- yt-dlp. On Linux and macOS install it as `bin/yt-dlp` in the skill folder (`bash scripts/setup.sh` does this), via `python3 -m yt_dlp`, or in a `.venv` in the skill folder. On Windows use `pip install yt-dlp` so `python3 -m yt_dlp` works; the extension does not detect a Windows binary or `.venv\Scripts`.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/installation.md](references/installation.md) — yt-dlp setup per OS
- [references/troubleshooting.md](references/troubleshooting.md) — npm, webview and download problems
- [references/development.md](references/development.md) — code flow and format flags
