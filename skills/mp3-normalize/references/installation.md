# Installation — mp3gain

## Ubuntu / Debian

```bash
sudo apt update
sudo apt install mp3gain
mp3gain --version
```

Enable `universe` if the package is missing:

```bash
sudo add-apt-repository universe
sudo apt update && sudo apt install mp3gain
```

## Other Linux

| Distro | Command |
|--------|---------|
| Fedora / RHEL | `sudo dnf install mp3gain` |
| Arch | `sudo pacman -S mp3gain` |
| openSUSE | `sudo zypper install mp3gain` |

## Verify (read-only)

```bash
mp3gain -s c /path/to/file.mp3
```

## Copilot extension

Install the skill, link to `~/.copilot/extensions/mp3-normalize/`, restart Copilot CLI. Node deps install on first load from the skill root (`extension.mjs` + `package.json`).

## Permissions

The skill creates `<sourceDir>/normalized/`. The source folder must be writable.
