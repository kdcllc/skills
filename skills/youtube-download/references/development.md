# Development — youtube-download

## Layout

```
extension.mjs          # bootstrap → scripts/main.mjs
scripts/main.mjs       # callbacks, youtube_download tool, /youtube-download
scripts/backend.js     # yt-dlp spawn, transcripts, downloadBinary
scripts/lib/           # copilot-webview (shared pattern with mp3-normalize)
assets/content/        # webview HTML/JS/CSS
```

## Code flow

1. **Slash command** `/youtube-download` → `scripts/main.mjs` → `webview.show()` → HTTP server in `scripts/lib/copilot-webview.js` → native window loads `assets/content/`.
2. **Form submit** → `assets/content/main.js` calls `copilot.startDownload(...)` → WebSocket → `scripts/main.mjs` callback → `downloadVideo()` in `scripts/backend.js`.
3. **Agent tool** `youtube_download` → same `downloadVideo()` path; progress via `session.log()`.

Reload the webview: `youtube_dl_ui_show reload=true`.

## yt-dlp flags (agents outside Copilot CLI)

`downloadVideo()` in `scripts/backend.js` builds a yt-dlp argument list. Reproduce a download by combining the format args from `buildFormatArgs()` below with these flags (when applicable):

- Always: `--js-runtimes node:<node executable path>` (uses `process.execPath` in the extension).
- Output template: `-o <outputPath>/%(title)s.%(ext)s` (output path is resolved absolute).
- When `metadata` is true: `--write-info-json`, `--write-thumbnail`, `--write-auto-subs`.
- When transcript is enabled: `--write-auto-subs`, `--write-subs`, `--sub-langs en.*`, `--sub-format vtt`.
- When `transcriptOnly` is true: `--skip-download` (transcript flags still apply).
- Progress: `--progress-template "%(progress.status)s at %(progress._percentage_str)s"`.
- Final argument: the video URL.

## Format map (`buildFormatArgs`)

Verbatim from `scripts/backend.js` — append these after your yt-dlp command prefix (`yt-dlp`, `python3 -m yt_dlp`, etc.):

```javascript
const formatMap = {
    best: ["-f", "best"],
    "best-video": ["-f", "bv+ba/b"],
    audio: ["-f", "ba", "-x", "--audio-format", "mp3"],
    "audio-m4a": ["-f", "ba", "-x", "--audio-format", "m4a"],
    "audio-wav": ["-f", "ba", "-x", "--audio-format", "wav"],
    mp4: ["-f", "bv[ext=mp4]+ba[ext=m4a]/b[ext=mp4]", "--merge-output-format", "mp4"],
    mkv: ["-f", "bv+ba/b", "--merge-output-format", "mkv"],
    "360p": ["-f", "bv[height<=360]+ba/b[height<=360]"],
    "720p": ["-f", "bv[height<=720]+ba/b[height<=720]"],
    "1080p": ["-f", "bv[height<=1080]+ba/b[height<=1080]"],
};
```

Unknown format keys fall back to `["-f", "best"]`.

## Adding a format

Edit `buildFormatArgs()` in `scripts/backend.js` (map above). Also update `assets/content/index.html` (dropdown), `SKILL.md` formats table, and the `youtube_download` tool `enum` in `scripts/main.mjs` if the format should be available to agents.

## Adding a callback

In `scripts/main.mjs`, add to the `CopilotWebview` `callbacks` object, then call from `assets/content/main.js` via `copilot.myCallback(...)`.

## Adding an agent tool

Append to the `tools` array in `joinSession()` in `scripts/main.mjs`.

## Programmatic download (Node)

From the skill root after `npm install`:

```javascript
import { downloadVideo, verifyPrerequisites, downloadBinary } from "./scripts/backend.js";
```

First-time binary setup: `await downloadBinary()` (writes `bin/yt-dlp` at skill root).

## Debugging

- Test yt-dlp: `python3 -m yt_dlp -F "URL"`.
- Extension logs: Copilot CLI output and `~/.copilot/logs/extensions/`.

The extension does not read `.env` or `DEBUG` from disk; `.env.example` is a template only.

## Security notes

yt-dlp is invoked with an argument array (no shell). The URL and output path are only checked for presence before spawn; there is no URL scheme allowlist or path traversal guard in this skill.
