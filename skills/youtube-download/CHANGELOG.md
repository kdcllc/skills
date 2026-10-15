# Changelog

All notable changes to the `youtube-download` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `youtube-download/vX.Y.Z`.

## [Unreleased]

## [1.0.0] - 2026-10-15

### Added

- Initial version: a Copilot CLI extension that downloads YouTube video or audio with yt-dlp, saves metadata, and converts English subtitles to Markdown or text transcripts.
- `/youtube-download` slash command with a webview UI, the `youtube_download` agent tool, and the webview tools `youtube_dl_ui_show`, `youtube_dl_ui_eval`, and `youtube_dl_ui_close`.
- `scripts/setup.sh` and `scripts/setup.bat` for installing yt-dlp, and a `.env.example` template.
- `references/installation.md`, `references/troubleshooting.md`, and `references/development.md`, covering install into `~/.copilot/extensions/<name>/`, Windows yt-dlp auto-detection limits, agent-tool versus webview formats, and the full yt-dlp format map.
