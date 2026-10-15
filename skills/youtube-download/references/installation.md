# Installation — yt-dlp

Install yt-dlp in the **youtube-download skill root** (where `extension.mjs` and `package.json` live). On Linux and macOS, runtime binaries and `.venv` also live at the skill root.

## Option 1: Binary (Linux and macOS)

From the skill root:

```bash
mkdir -p bin
# Linux
wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O bin/yt-dlp
chmod +x bin/yt-dlp
# macOS
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos -o bin/yt-dlp
chmod +x bin/yt-dlp
```

Or run `bash scripts/setup.sh` from anywhere; the script `cd`s to the skill root.

## Option 2: Python module (recommended on Windows)

```bash
pip install yt-dlp
# or
python3 -m pip install yt-dlp
```

On Windows, use this option so `scripts/backend.js` can run yt-dlp via `python3 -m yt_dlp`. The extension does **not** auto-detect a Windows binary at `bin\yt-dlp.exe` or Python inside `.venv\Scripts\`.

`scripts\setup.bat` can still download `bin\yt-dlp.exe` for manual use, but Copilot will not pick it up until you use the Python module path above.

## Option 3: Virtual environment (Linux and macOS skill root)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install yt-dlp
```

The extension looks for `.venv/bin/python3 -m yt_dlp` only (not `.venv\Scripts\python.exe` on Windows).

## Detection order (Linux and macOS)

`scripts/backend.js` tries, in order:

1. `bin/yt-dlp` at the skill root (same path name on all platforms; not `bin/yt-dlp.exe`)
2. `python3 -m yt_dlp` on PATH
3. `.venv/bin/python3 -m yt_dlp` under the skill root

## Verify

```bash
./bin/yt-dlp --version
python3 -m yt_dlp --version
```

## Node dependencies

From the skill root: `npm install` (Copilot CLI runs this on first extension load).

## macOS quarantine

If the binary is blocked: `xattr -d com.apple.quarantine ./bin/yt-dlp`
