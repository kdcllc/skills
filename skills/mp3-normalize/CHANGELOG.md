# Changelog

All notable changes to the `mp3-normalize` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `mp3-normalize/vX.Y.Z`.

## [Unreleased]

## [1.0.0] - 2026-10-15

### Added

- Initial version: a Copilot CLI extension that copies MP3 files to a `normalized/` subfolder and applies lossless track or album gain with mp3gain.
- `/mp3-normalize` slash command with a webview UI, the `normalize_mp3` agent tool, and the webview tools `mp3_normalize_show`, `mp3_normalize_eval`, and `mp3_normalize_close`.
- `references/installation.md` and `references/development.md`, covering install into `~/.copilot/extensions/<name>/`, mp3gain setup, and the note that only the webview enforces the 70-105 dB `targetDb` range.
