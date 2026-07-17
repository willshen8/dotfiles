# dotfiles

Personal macOS configuration files — shell, window management, and CLI tooling.

## Contents

| File | What it configures |
| --- | --- |
| `.aerospace.toml` | [AeroSpace](https://github.com/nikitabobko/AeroSpace) — tiling window manager for macOS |
| `.claude/statusline-command.sh` | [Claude Code](https://claude.com/claude-code) custom status line — model, context usage, cost, and a daily per-model token bar |

_More configs (shell, etc.) will be added over time._

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

### Claude Code status line

A custom [status line](https://docs.claude.com/en/docs/claude-code/statusline) for the Claude Code CLI. It renders:

- Active model and output style
- A context-window usage bar (`ctx:[███░░░░░░░] 30%`) with token count
- Current session cost
- A `today:` bar showing the day's token usage split by model (cyan = Opus, green = Sonnet, yellow = Haiku), plus total tokens and cost

```bash
# Symlink the script into place
ln -sf ~/dotfiles/.claude/statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then point Claude Code at it by adding this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

Requires `jq` and `bc` (`brew install jq`; `bc` ships with macOS). Daily usage is tracked in `~/.claude/daily-usage/` (gitignored).

## Notes

- Secrets are never committed. `.zshrc` and anything containing tokens/credentials are excluded via `.gitignore`.
