# muxbar

**Language:** [English](README.md) | [한국어](README.ko.md)

> A native macOS menu bar app for tmux session management + caffeinate toggle.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)

## Features

- **Session list** — All tmux sessions at a glance, sorted by attached first and creation date (latest first within each group)
- **Attach** — Open the selected session in Terminal.app / iTerm2 / Warp / Alacritty / kitty
- **Kill** — Drop a session from the menu
- **Live Preview** — Click a session row or pick "Preview" to see recent output (ANSI-rendered via SwiftTerm)
- **Keep Awake** — Toggle `caffeinate -dims` as a tracked tmux session (`_muxbar-awake`). Detects external caffeinate too (any tmux session running it, or any system-level process), and stops all of them with one click.
- **Templates** — Built-in and user-defined session layouts (YAML). New Session → pick a template.
- **Global hotkeys** — `⌘⇧A` toggles Keep Awake, `⌘⇧1`~`⌘⇧9` attach the top N sessions.
- **Open at Login** — Registers as a macOS Login Item under Settings (when installed as a bundled `.app`).

## Menu bar icon

- 0 sessions: plain coffee cup
- Active sessions: cup + session count badge
- Keep Awake active: steaming cup, orange tint

## Menu layout

```
┌ muxbar  ● (connected) ────┐
│ ○ dev        2w /msa      │  ← session rows, attached first, newest first
│ ● api        1w /Users    │    (scrollable if > 5)
│ ○ logs       1w /var/log  │
├───────────────────────────┤
│ ☕ Keep Awake        ON   │  ← toggle (also ⌘⇧A)
├───────────────────────────┤
│ ⊞ New Session          ▸ │  ← templates submenu
├───────────────────────────┤
│ ⚙ Settings             ▸ │  ← Open at Login, future prefs
├───────────────────────────┤
│ Quit muxbar         ⌘Q    │
└───────────────────────────┘
```

## Requirements

- macOS 13 (Ventura) or later
- `tmux` (`brew install tmux`)

## Installation

### Homebrew (planned)

```bash
brew install --cask 1989v/tap/muxbar
```

### Build from source (Xcode not required)

You only need the Command Line Tools + Swift 5.9+.

```bash
git clone https://github.com/1989v/muxbar.git
cd muxbar

./build.sh           # Release build + .app bundle
./build.sh open      # Build + open
./build.sh install   # Build + copy to /Applications
```

`build.sh` does:
1. `swift build -c release`
2. Creates `muxbar.app/Contents/{MacOS,Info.plist}`
3. Ad-hoc codesigns with `codesign --sign -`
4. Strips quarantine attribute

### Manual download (after release)

1. Download the `.dmg` from [Releases](https://github.com/1989v/muxbar/releases)
2. Drag `muxbar.app` into Applications
3. First launch: **right-click → Open** (needed because the app uses ad-hoc signing)

## Development

Run from sources (some features are disabled in unbundled mode — see table below):

```bash
swift build
swift run muxbar
```

Run the test suite (requires Xcode for XCTest):

```bash
swift test
```

## Feature availability by execution mode

| Feature | `swift run` (unbundled) | `.app` bundle |
|---|---|---|
| Session list / Attach / Kill / Preview | ✅ | ✅ |
| Keep Awake, Templates, Hotkeys | ✅ | ✅ |
| Open at Login (Login Item) | ⚠ (Settings → shown disabled) | ✅ |
| User notifications | ❌ | ✅ |

Features that need a proper `.app` bundle (Open at Login, notifications) fall back gracefully when running unbundled — the menu shows the item but disables the toggle with a hint.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘⇧A` | Toggle Keep Awake |
| `⌘⇧1` ~ `⌘⇧9` | Attach the N-th visible session |

## Custom templates

Put YAML files under `~/Library/Application Support/muxbar/Templates/`:

```yaml
name: MyDev
description: My dev setup
sessionNameHint: mydev
windows:
  - name: edit
    command: nvim .
    cwd: ~
  - name: run
    command: npm run dev
  - name: logs
    command: tail -f logs/app.log
```

- Files starting with `_` are ignored (so `_example.yaml` stays as a reference)
- Reload via menu: **New Session → Reload Templates**
- Open the folder: **New Session → Edit Templates…**

## Design & documentation

- [v0.1 Design spec](docs/specs/2026-04-17-v0.1-design.md)
- [Implementation plans](docs/README.md)
- [Architecture decisions (ADRs)](docs/adr)

## License

[MIT](LICENSE) © 2026 kgd
