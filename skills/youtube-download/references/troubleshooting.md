# Troubleshooting — youtube-download

## npm install fails

Clear cache and reinstall from the skill root:

```bash
npm cache clean --force
rm -rf node_modules package-lock.json
npm install
# or
npm install --legacy-peer-deps
```

Use Node 20+.

## yt-dlp not found

See [installation.md](installation.md). From the skill root:

```bash
./bin/yt-dlp --version
python3 -m yt_dlp --version
bash scripts/setup.sh
```

On Windows, the extension does not auto-detect `bin\yt-dlp.exe` or a `.venv` under the skill folder. Install with `pip install yt-dlp` and ensure `python3 -m yt_dlp --version` works.

## Webview does not open

Check files exist:

```bash
ls assets/content/index.html
ls scripts/lib/copilot-webview.js scripts/lib/webview-child.mjs
npm list @webviewjs/webview ws
```

Linux may need WebView build deps; Windows needs WebView2.

## Download or transcript failures

- Confirm the URL is public and uses `https://www.youtube.com/watch?v=...`
- List subtitles: `python3 -m yt_dlp --list-subs "URL"`
- Update yt-dlp: `pip install --upgrade yt-dlp`

## Extension not loaded

Ensure the skill folder is linked under `~/.copilot/extensions/youtube-download/` with `extension.mjs` at that folder root. Restart Copilot CLI or `/clear`. Check `~/.copilot/logs/extensions/`.

## More help

- [SKILL.md](../SKILL.md) — usage and parameters
- [development.md](development.md) — code layout and debugging
