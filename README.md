<div align="center">

# proj

**Stop losing track of your vibe-coded projects.**

You have a dozen repos open. You `cd` into one you touched 3 days ago and think: *"what was the plan? what's left? which Claude session had that idea?"*

**proj** gives you one place to see every project's progress, TODO, and jump right back in.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: zsh](https://img.shields.io/badge/Shell-zsh-blue.svg)](#requirements)
[![AI: Claude](https://img.shields.io/badge/AI-Claude-blueviolet.svg)](https://claude.ai)

[Features](#features) · [Install](#install) · [Usage](#usage) · [Hotkeys](#hotkeys) · [Configuration](#configuration)

</div>

---

## The Problem

When you vibe-code across many projects, you lose context fast:
- **"Where was that project?"** — repos scattered across ~/projects, ~/dev, ~/Desktop/temp-thing
- **"What was I doing?"** — no summary, no TODO, just stale git log
- **"Which Claude session?"** — you had a great conversation about the auth flow, good luck finding it

## The Fix

`proj add` in any project directory. Claude AI scans your codebase and writes the summary for you:

![proj add](docs/screenshot-add.png)

Then type `proj` (or `Ctrl+P` from anywhere) — see progress, TODO, and Claude sessions for every project at a glance:

![proj interactive panel](docs/screenshot-panel.png)

## Features

- **Progress & TODO at a Glance** — See what's done and what's next for every project, AI-generated
- **Fuzzy Find & Jump** — `Ctrl+P` from anywhere, fuzzy search, Enter to `cd` right in
- **Resume Claude Sessions** — One keystroke to pick up the exact Claude Code conversation
- **Status Tracking** — active / paused / blocked / done, your prompt shows the count
- **AI Does the Busywork** — `proj add` and Claude writes the summary, progress, and TODO for you
- **Pure Terminal** — zsh + fzf, tab completion, Starship integration, i18n (English / 中文)

## Requirements

- **zsh** (macOS default)
- **[fzf](https://github.com/junegunn/fzf)** >= 0.38
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** (for AI scanning & session resume)
- Optional: [Starship](https://starship.rs) (for prompt integration), [eza](https://github.com/eza-community/eza) (for preview file listing)

## Install

### One-liner

```bash
git clone https://github.com/doctormin/proj.git ~/.proj-repo && ~/.proj-repo/install.sh
```

### Manual

```bash
# Copy files
mkdir -p ~/.proj/data
cp proj.zsh ~/.proj/proj.zsh
cp preview.sh ~/.proj/preview.sh
chmod +x ~/.proj/preview.sh

# Add to ~/.zshrc
echo '[ -f "$HOME/.proj/proj.zsh" ] && source "$HOME/.proj/proj.zsh"' >> ~/.zshrc
```

### Starship integration (optional)

Add to `~/.config/starship.toml`:

```toml
[custom.projects]
command = 'echo "$PROJ_ACTIVE_COUNT"'
when = '[ "${PROJ_ACTIVE_COUNT:-0}" -gt 0 ]'
format = '[📋 $output proj](bold cyan) '
shell = ['bash', '--noprofile', '--norc']
```

## Usage

### Add a project

```bash
# In any project directory
cd ~/projects/my-app
proj add                    # Name defaults to directory name

# Or specify name and path
proj add my-api ~/src/api
```

Claude will automatically scan the project and populate description, progress, and TODO.

### Interactive panel

```bash
proj                        # Open the panel
# or press Ctrl+P from anywhere
```

### Resume Claude Code

```bash
proj cc                     # Auto-detect from current directory
proj cc my-api              # Specify project name
# or press Ctrl-E in the interactive panel
```

### Manage status

```bash
proj status my-api paused
proj status my-api active
proj status my-api done
```

### Rescan with Claude

```bash
proj scan my-api            # Or just `proj scan` inside the project dir
# or press Ctrl-R in the interactive panel
```

### Static list

```bash
proj list                   # All projects
proj list active            # Only active
proj list done              # Only completed
```

## Hotkeys

Inside the interactive panel (`proj` or `Ctrl+P`):

| Key | Action |
|-----|--------|
| `Enter` | Jump to project directory |
| `Ctrl-E` | Resume Claude Code session |
| `Ctrl-R` | AI rescan progress & TODO |
| `Ctrl-X` | Mark done or remove project |
| `Esc` | Exit panel |
| Type | Fuzzy search / filter |

Global (in any terminal):

| Key | Action |
|-----|--------|
| `Ctrl-P` | Open interactive panel |

## Configuration

```bash
proj config                 # Interactive settings menu
proj config lang zh         # Set Chinese
proj config lang en         # Set English
proj config lang auto       # Follow system locale
```

Config is stored in `~/.proj/config`.

## Data Storage

```
~/.proj/
├── config                  # User settings (lang, etc.)
├── preview.sh              # fzf preview renderer
├── proj.zsh                # Main plugin
└── data/
    └── <project-name>/
        ├── path            # Project directory path
        ├── status          # active | paused | blocked | done
        ├── updated         # Last update timestamp
        ├── desc            # AI-generated description
        ├── progress        # AI-generated progress items
        └── todo            # AI-generated TODO items
```

Plain text files. No database. Easy to backup, sync, or edit by hand.

## All Commands

```
proj                          Open interactive panel (fzf)
proj add [name] [path]        Add project (Claude auto-scan)
proj rm <name>                Remove project
proj cc [name]                Resume Claude Code session
proj scan [name]              Rescan with Claude AI
proj status <name> <state>    Change status
proj edit <name> <field> <v>  Edit field manually
proj list [active|done]       Static list view
proj config                   Settings
proj help                     Show help
```

## License

MIT

---

<div align="center">
<sub>Built with zsh, fzf & Claude AI</sub>
</div>
