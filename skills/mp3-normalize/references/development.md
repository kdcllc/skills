# Development — mp3-normalize

## Layout

```
extension.mjs
scripts/main.mjs       # callbacks, normalize_mp3 tool, /mp3-normalize
scripts/backend.js     # mp3gain orchestration
scripts/lib/copilot-webview.js
assets/content/        # webview UI
```

## Code flow

1. `/mp3-normalize` or `mp3_normalize_show` opens the webview (`assets/content/`).
2. Form submit → `copilot.startNormalization(sourceDir, mode, targetDb)` → `normalizeFiles()` in `scripts/backend.js`.
3. Agent tool `normalize_mp3` calls the same `normalizeFiles()` with progress on `session.log()`.

Reload: `mp3_normalize_show reload=true`.

## mp3gain invocation

In `normalizeFiles()`:

- Copies each `.mp3` from `sourceDir` to `sourceDir/normalized/`.
- Runs `mp3gain` on copies only.
- **Track mode:** `-c -p -r` (each file to target).
- **Album mode:** `-c -p -a` (relative levels preserved).
- **Target dB:** offset `targetDb - 89` passed as `-d N` when non-zero (mp3gain default is 89 dB).

Example manual track normalize:

```bash
mp3gain -c -p -r -d 6 normalized/*.mp3   # ~95 dB target
```

## Extending

- New UI fields: `assets/content/main.js` + matching callback in `scripts/main.mjs`.
- Recursive folders: extend `listMp3Files()` in `scripts/backend.js` (not supported in 1.0.0).

## Debugging

- Run mp3gain manually on one file in `normalized/` to see stderr.
- Extension logs under `~/.copilot/logs/extensions/`.
