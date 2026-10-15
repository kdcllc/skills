---
name: youtube-download
description: "Download YouTube video or audio (MP3/M4A/WAV), save metadata and thumbnails, and convert English subtitles to Markdown or plain-text transcripts. Use when the user asks to download a YouTube video, rip audio, or get a transcript."
license: MIT
compatibility: GitHub Copilot CLI extension; Node 20+; yt-dlp (binary, pip, or venv)
metadata:
  version: "1.0.0"
---

# YouTube Download (`youtube-download`)

Copilot CLI extension for downloading YouTube media with format control, optional metadata, and English transcript conversion. Use the slash command for a desktop webview, or the `youtube_download` agent tool for scripted downloads.

## Install

1. Install the skill: `npx skills add kdcllc/skills --skill youtube-download`
2. Copilot CLI loads extensions from `~/.copilot/extensions/<name>/` (user) or `.github/extensions/<name>/` (project). Each location is an **immediate subdirectory** named `<name>` that contains `extension.mjs` at its root; that folder name becomes the extension name (keep it `youtube-download`). Link or copy the installed skill folder there, for example:
   `ln -s "$(pwd)/.agents/skills/youtube-download" ~/.copilot/extensions/youtube-download`
   (Adjust the source path to wherever `npx skills` installed the skill.)
3. Restart Copilot CLI or run `/clear`. First load runs `npm install` in the skill folder automatically.
4. Install yt-dlp. On Linux/macOS see [references/installation.md](references/installation.md) or run `bash scripts/setup.sh`. On Windows use `pip install yt-dlp` so `python3 -m yt_dlp` works (the extension does not auto-detect `bin\yt-dlp.exe` or `.venv\Scripts`).

Use `/extensions manage` and logs under `~/.copilot/logs/extensions/` when troubleshooting extension load. See [About CLI extensions](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-extensions).

**Claude Code, Cursor, Codex:** the Node extension does not load there. An agent can run `yt-dlp` directly using the format flags documented in [references/development.md](references/development.md) (`buildFormatArgs` map).

## Usage

### Slash command (webview)

```
/youtube-download
/youtube-download https://www.youtube.com/watch?v=VIDEO_ID
```

### Agent tool `youtube_download`

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `url` | string | yes | — | YouTube video URL |
| `format` | string | no | `best` | Agent tool enum: `best`, `audio`, `mp4`, `mkv`, `360p`, `720p`, `1080p` (see formats table) |
| `outputPath` | string | yes | — | Directory for output files |
| `metadata` | boolean | no | `true` | JSON info, thumbnail, subs |
| `transcriptEnabled` | boolean | no | `false` | Download and convert English subs |
| `transcriptOnly` | boolean | no | `false` | Skip media; transcript only |
| `transcriptOutput` | string | no | `md` | `md` or `txt` |
| `removeTimestamps` | boolean | no | `true` | Strip VTT timestamps in output |

### Webview tools

`youtube_dl_ui_show`, `youtube_dl_ui_eval`, `youtube_dl_ui_close` (for example `youtube_dl_ui_show reload=true` to reload the UI).

## Formats

| Format | Output | Agent tool | Webview |
|--------|--------|------------|---------|
| `best` | Best available video+audio | yes | yes |
| `best-video` | Video+audio merged (`bv+ba/b`) | no | yes |
| `audio` | MP3 | yes | yes |
| `audio-m4a` | M4A | no | yes |
| `audio-wav` | WAV | no | yes |
| `mp4` | MP4 | yes | yes |
| `mkv` | MKV | yes | yes |
| `360p` | Video capped at 360p | yes | yes |
| `720p` | Video capped at 720p | yes | yes |
| `1080p` | Video capped at 1080p | yes | yes |

Webview-only formats still work via `/youtube-download`; the `youtube_download` tool rejects unknown enum values.

## Output layout

```
output-directory/
├── Title.ext
├── Title.info.json
├── Title.jpg
├── Title.en.vtt
└── Title.en.md   (or .txt)
```

## Configuration

`.env.example` is a template for future use. The extension does **not** read `.env`, `DEBUG`, or `YOUTUBE_DOWNLOAD_DEFAULT_OUTPUT_DIR` today.

## Known limitations

- One active download at a time in the webview.
- Playlists and live streams are not fully supported.
- Transcript conversion targets English subtitle tracks.
- Region-locked or private videos may fail.
- Very large files may time out on slow links.
- On Windows, only `python3 -m yt_dlp` is auto-detected; skill-root `bin/yt-dlp.exe` and `.venv\Scripts\python.exe` are not.
- Format discovery in the webview UI is not implemented (backend supports listing formats for callbacks only).

## References

- [references/installation.md](references/installation.md) — yt-dlp binary, pip, and venv setup
- [references/troubleshooting.md](references/troubleshooting.md) — npm, webview, and download issues
- [references/development.md](references/development.md) — code flow, formats, callbacks, debugging
