<div align="center">

# proj

**`zoxide` helps you `cd` faster. `proj` helps you remember what you were doing.**

Too many projects. Pick up any of them in 3 seconds.
AI scans your code, tracks progress and TODO, resumes your Claude Code sessions.

**~1000 lines of shell. No binary. No runtime. Loads in <50ms.**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: zsh](https://img.shields.io/badge/Shell-zsh-blue.svg)](#requirements)
[![Platform: macOS & Linux](https://img.shields.io/badge/Platform-macOS%20%26%20Linux-orange.svg)](#requirements)
[![AI: Claude Code](https://img.shields.io/badge/AI-Claude%20Code-blueviolet.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-blue.svg)](#)

[Features](#features) · [Why not X?](#why-not-x) · [Install](#install) · [Usage](#usage) · [Privacy](#privacy)

<!-- TODO: Replace with demo GIF when available -->
<!-- ![proj demo](docs/demo.gif) -->

</div>

---

## The Problem

When you vibe-code across many projects, you lose context fast:
- **"Where was that project?"** — repos scattered across `~/projects`, `~/dev`, `~/Desktop/temp-thing`
- **"What was I doing?"** — no summary, no TODO, just stale `git log`
- **"Which Claude session?"** — you had a great conversation about the auth flow, good luck finding it
- **"What about that server project?"** — you SSH'd in, started something, completely forgot about it
- **"I was working on this at the office..."** — your home machine has no idea what you did

## The Fix

`proj add` in any project directory. Claude Code scans your codebase and writes the summary for you:

![proj add — Claude scans and generates project summary](docs/screenshot-add-en.png)

Then type `proj` (or `Ctrl+P` from anywhere) — see progress, TODO, and Claude sessions for every project at a glance:

![proj interactive panel with project list and preview](docs/screenshot-panel-en.png)

## Features

- **AI-Generated Progress & TODO** — `proj add` and Claude writes the summary, progress, and TODO for you. Never write project notes yourself
- **Fuzzy Find & Jump** — `Ctrl+P` from anywhere, fuzzy search, Enter to `cd` right in
- **Resume Claude Code Sessions** — One keystroke to pick up the exact Claude Code conversation. Preview shows session history and summaries
- **Remote Project Tracking** — `proj add-remote` to track projects on remote servers. `Enter` to SSH jump, metadata synced locally
- **Multi-Machine Sync** — `proj sync` to keep all project metadata in sync across machines via a private git repo
- **Meta Session** — `proj meta` launches an AI advisor that knows all your projects. Ask "which project should I work on next?"
- **Claude Status Detection** — Preview panel shows whether Claude Code is actively running for each project
- **Status Tracking** — `active` / `paused` / `blocked` / `done`, your prompt shows the count via Starship
- **Lightweight & Fast** — ~30 KB total, loads in <50ms. Pure `zsh` shell script, no binary, no daemon, no background process. Plain text data you can `cat`, `grep`, or `git diff`
- **Cross-Platform** — macOS + Linux. Tab completion, `starship` integration, i18n (English / 中文)

## Why not X?

| | **proj** | zoxide | tmuxinator | Agent Deck |
|---|----------|--------|------------|------------|
| AI project summary | Yes | — | — | — |
| Progress & TODO tracking | Yes | — | — | — |
| Claude session resume | Yes | — | — | Partial |
| Remote server projects | Yes | — | — | Yes |
| Multi-machine sync | Yes | — | — | — |
| AI project advisor | Yes | — | — | — |
| **Install size** | **~30 KB** | ~1 MB | ~5 MB | ~15 MB |
| **Startup overhead** | **<50ms** | <10ms | ~200ms | ~300ms |
| **Dependencies** | `zsh` + `fzf` | none | Ruby | Go + tmux |
| Compile step | none | Rust build | gem install | Go build |

**TL;DR:** `zoxide` helps you `cd` faster. `proj` helps you *remember what you were doing*. And it's just a shell script — nothing to compile, nothing to break.

## Requirements

- **`zsh`** (macOS default, `apt install zsh` on Linux)
- **[`fzf`](https://github.com/junegunn/fzf)** >= 0.38
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** (optional — for AI scanning, session resume, and meta advisor. Without it, you can still add/track/jump projects manually)
- Optional: [`starship`](https://starship.rs) (prompt integration), [`eza`](https://github.com/eza-community/eza) (pretty file listing), [`jq`](https://jqlang.github.io/jq/) (session preview)

## Install

### One-liner

```bash
git clone https://github.com/doctormin/proj.git ~/.proj-repo && ~/.proj-repo/install.sh
```

The installer will:
- Check for required dependencies (`zsh`, `fzf`) and warn about optional ones
- Copy files to `~/.proj/`
- Add one line to your `.zshrc`
- Optionally configure `starship` integration

### Quick Start (after install)

```bash
# 1. Restart your shell
exec zsh

# 2. Add your first project
cd ~/my-project && proj add

# 3. Open the panel
proj   # or Ctrl+P from anywhere
```

### Uninstall

```bash
~/.proj-repo/uninstall.sh        # Remove plugin, keep project data
~/.proj-repo/uninstall.sh --all  # Remove everything
```

## Usage

### Local projects

```bash
proj add                          # Add current directory
proj add my-api ~/src/api         # Add with custom name and path
```

### Remote projects

```bash
proj add-remote api user@server:/home/user/api
# Shows in panel with [user@server] label
# Enter to SSH jump, metadata stored locally
```

### Multi-machine sync

```bash
proj config sync-repo git@github.com:you/proj-sync.git  # Set up (once)
proj sync                         # Sync project metadata across machines
```

### AI project advisor

```bash
proj meta                         # Launch Meta Session
# Ask: "Which project should I work on next?"
# Ask: "Summarize all my TODOs across projects"
```

### Other commands

```bash
proj                              # Open interactive panel (fzf)
proj cc [name]                    # Resume Claude Code session
proj scan [name]                  # Rescan with Claude Code
proj status <name> <state>        # Change status (active/paused/blocked/done)
proj edit <name> <field> <value>  # Edit field (desc/path/progress/todo)
proj list [active|done]           # Static list view
proj config                       # Settings
proj --version                    # Show version
proj help                         # Show help
```

## Hotkeys

Inside the interactive panel (`proj` or `Ctrl+P`):

| Key | Action |
|-----|--------|
| `Enter` | Jump to project (cd for local, SSH for remote) |
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
proj config                       # Interactive settings menu
proj config lang zh               # Set Chinese
proj config lang en               # Set English
proj config sync-repo <git-url>   # Set sync repository
```

Config is stored in `~/.proj/config`.

## Data Storage

```
~/.proj/
├── config                        # User settings
├── machine-id                    # UUID for multi-machine sync
├── schema_version                # Data format version
├── version                       # Installed version
├── meta/                         # Meta Session working directory
│   └── CLAUDE.md                 # Auto-generated project context
└── data/
    └── <project-name>/
        ├── path.<machine-id>     # Local path (per-machine)
        ├── type                  # "local" or "remote"
        ├── status                # active | paused | blocked | done
        ├── updated               # Last update timestamp
        ├── desc                  # AI-generated description
        ├── progress              # AI-generated progress
        ├── todo                  # AI-generated TODO
        ├── host                  # Remote only: user@hostname
        └── remote_path           # Remote only: path on server
```

Plain text files. No database. Easy to backup, sync, or edit by hand.

## Privacy

- **All project metadata stays local** in `~/.proj/` — plain text files you can read, edit, or delete anytime
- **AI scanning** uses the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code). When you run `proj add`, your code is sent to Anthropic's API for analysis (same as using Claude Code directly). See [Anthropic's data policy](https://www.anthropic.com/policies/privacy) for retention details. No data is sent to any third-party service
- **Without Claude Code**, proj still works — you can manually add projects, set descriptions, jump between them, and manage status. AI features are optional
- **Sync** pushes metadata only (descriptions, TODO, status) to a **private** git repo you control — no source code is ever synced
- **No telemetry, no analytics, no tracking**. The install script copies two files and adds one line to `.zshrc`. That's it

## Troubleshooting

**`proj add` hangs or takes too long:**
Claude Code is scanning your project. Large repos take 5-15 seconds. If it fails, you can manually set fields with `proj edit <name> desc "your description"`.

**Claude Code not found:**
Install [Claude Code](https://docs.anthropic.com/en/docs/claude-code) for AI features. Without it, you can still use `proj add <name> <path>` + manual edits, jump with `proj`/`Ctrl+P`, and manage status.

**`Ctrl+P` doesn't work:**
Another `zsh` plugin may have bound `Ctrl+P`. Check with `bindkey '^P'`. `proj` binds it on load; whichever loads last wins.

**Remote project SSH fails:**
`proj` opens a new terminal window for SSH. If no terminal emulator is found, it prints the SSH command for manual use. Set `PROJ_TERMINAL` env var to specify your terminal app.

**Sync conflicts:**
Conflicts are extremely rare with single-user use. If they happen, `proj sync` will show the conflicted files. Resolve them manually in `~/.proj/data/` with standard git tools.

## Update

```bash
cd ~/.proj-repo && git pull && ./install.sh
```

## License

MIT

---

<div align="center">
<sub>Built with zsh, fzf & Claude Code · <a href="https://cc-proj.cc">cc-proj.cc</a></sub>
</div>
