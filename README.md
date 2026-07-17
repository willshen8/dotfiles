# dotfiles

Personal macOS configuration files — shell, window management, and CLI tooling.

## Contents

| File | What it configures |
| --- | --- |
| `.aerospace.toml` | [AeroSpace](https://github.com/nikitabobko/AeroSpace) — tiling window manager for macOS |

_More configs (shell, Claude Code) will be added over time._

## Install

These files live in your home directory (`~`). Clone the repo somewhere, then symlink the files you want. Symlinking (rather than copying) means edits stay in sync with the repo.

```bash
git clone https://github.com/willshen8/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### AeroSpace

```bash
# Install AeroSpace (if you haven't already)
brew install --cask nikitabobko/tap/aerospace

# Symlink the config into place
ln -sf ~/dotfiles/.aerospace.toml ~/.aerospace.toml
```

Reload the config from within AeroSpace with `alt-shift-;` then `esc`, or restart the app.

> [!note]
> If you already have a `~/.aerospace.toml`, back it up first: `mv ~/.aerospace.toml ~/.aerospace.toml.bak`

## Notes

- Secrets are never committed. `.zshrc` and anything containing tokens/credentials are excluded via `.gitignore`.
