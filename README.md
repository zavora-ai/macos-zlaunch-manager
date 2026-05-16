# macOS Launch Manager

A native macOS GUI + CLI for managing launchd services. Replaces the need to wrestle with `launchctl` commands and plist files directly.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![Universal Binary](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-green)
![License](https://img.shields.io/badge/License-Apache%202.0-green)

## What It Does

macOS uses `launchd` to manage all background services, but there's no built-in GUI for it (unlike Windows Services or Linux systemctl). Launch Manager fills that gap with:

- **GUI App** — Three-column SwiftUI interface for browsing, controlling, and configuring services
- **CLI Tool (`lm`)** — Fast terminal interface for the same operations

## Installation

### CLI — One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/zavora/macos-launch-manager/main/scripts/install.sh | bash
```

### CLI — Homebrew

```bash
brew tap zavora/tap
brew install lm
```

### CLI — Download binary

```bash
# From GitHub Releases (no Swift/Xcode needed)
curl -L https://github.com/zavora/macos-launch-manager/releases/latest/download/lm-v1.0.0-macos-universal.tar.gz | tar xz
sudo mv lm /usr/local/bin/
```

### CLI — Build from source

```bash
git clone https://github.com/zavora/macos-launch-manager.git
cd macos-launch-manager/cli
swift build -c release
cp .build/release/lm /usr/local/bin/lm
```

### GUI App — DMG

```bash
# Build locally
./scripts/create-dmg.sh
# Output: build/LaunchManager-YYYY.MM.DD.dmg
# Open DMG → drag to Applications
```

Or download from [GitHub Releases](https://github.com/zavora/macos-launch-manager/releases).

## CLI Usage

The `lm` command provides full service management from the terminal:

```bash
# List services
lm                                  # All services (default)
lm list -d user                     # User agents only
lm list -d global-daemons           # Global daemons only
lm list --running                   # Only running services
lm list --loaded                    # Only loaded services
lm list -f docker                   # Filter by name substring

# Service info
lm status <label>                   # Detailed status
lm info <label>                     # Raw launchctl print output
lm logs <label>                     # View stdout/stderr logs
lm logs -f <label>                  # Follow logs (tail -f)
lm logs -l 200 <label>             # Last 200 lines

# Control services
lm start <label>                    # Start (auto-loads if needed)
lm stop <label>                     # Stop (SIGTERM)
lm stop -f <label>                  # Force kill (SIGKILL)
lm restart <label>                  # Stop + start

# Load/unload
lm load <label>                     # Bootstrap into launchd
lm unload <label>                   # Bootout from launchd

# Enable/disable
lm enable <label>                   # Auto-load on boot/login
lm disable <label>                  # Prevent auto-load

# Create/delete
lm create com.company.myservice \
    -p /usr/local/bin/myapp \
    --run-at-load --keep-alive \
    --stdout /tmp/myservice.log \
    --stderr /tmp/myservice.err

lm delete <label>                   # Unload + remove plist
lm delete -y <label>               # Skip confirmation

# Edit
lm edit <label>                     # Open plist in $EDITOR
```

### Domains

| Flag | Domain | Path |
|------|--------|------|
| `-d user` | User Agents | `~/Library/LaunchAgents` |
| `-d global-agents` | Global Agents | `/Library/LaunchAgents` |
| `-d global-daemons` | Global Daemons | `/Library/LaunchDaemons` |
| `-d system-agents` | System Agents | `/System/Library/LaunchAgents` |
| `-d system-daemons` | System Daemons | `/System/Library/LaunchDaemons` |
| `-d all` | All (default) | All of the above |

### Status Indicators

```
● running    — Service has an active process
◐ loaded     — Registered with launchd but not running
○ stopped    — Not loaded into launchd
```

## GUI Features

- **Three-column layout** — Sidebar domains → service list → detail view
- **All 5 launchd domains** with service counts and running badges
- **Service lifecycle** — Start, stop, restart, load/unload, enable/disable
- **Plist editor** — Edit XML with validation and save
- **Log viewer** — Stdout/stderr + system log with filtering and auto-refresh
- **Create services** — Template wizard (simple agent, periodic task, daemon, web server)
- **Delete services** — Unloads then removes plist with confirmation
- **Search & filter** — By label or executable, filter by status
- **Context menus** — Right-click for quick actions
- **Dark mode** — Full support
- **Universal Binary** — Runs natively on Intel and Apple Silicon

## Project Structure

```
macos-launch-manager/
├── LaunchManager/                  # GUI App (SwiftUI)
│   ├── LaunchManager.xcodeproj
│   └── LaunchManager/
│       ├── LaunchManagerApp.swift
│       ├── ContentView.swift       # NavigationSplitView layout
│       ├── Models/
│       │   ├── LaunchdService.swift
│       │   └── ServiceDomain.swift
│       ├── Services/
│       │   ├── ServiceManager.swift
│       │   └── PrivilegedHelper.swift
│       └── Views/
│           ├── SidebarView.swift
│           ├── ServiceListView.swift
│           ├── ServiceDetailView.swift
│           ├── PlistEditorView.swift
│           ├── CreateServiceView.swift
│           ├── LogViewerView.swift
│           ├── SettingsView.swift
│           ├── SearchBar.swift
│           └── ServiceStatusBadge.swift
├── cli/                            # CLI Tool (Swift Package)
│   ├── Package.swift
│   └── Sources/
│       ├── LM.swift                # Entry point & subcommands
│       ├── Commands.swift          # All command implementations
│       └── Helpers.swift           # Domain, shell exec, ANSI colors
├── scripts/
│   ├── create-dmg.sh              # Build & package DMG
│   ├── generate-dmg-background.py
│   └── dmg-background.png
├── docs/
│   ├── ARCHITECTURE.md
│   ├── USAGE.md
│   ├── DEVELOPMENT.md
│   └── CHANGELOG.md
├── README.md
├── LICENSE
└── .gitignore
```

## How It Works

Both the GUI and CLI use `launchctl` subcommands under the hood:

| Action | Command |
|--------|---------|
| List loaded | `launchctl list` |
| Start | `launchctl kickstart -kp <target>` |
| Stop | `launchctl kill SIGTERM <target>` |
| Load | `launchctl bootstrap <domain> <plist>` |
| Unload | `launchctl bootout <target>` |
| Enable | `launchctl enable <target>` |
| Disable | `launchctl disable <target>` |
| Info | `launchctl print <target>` |

Service targets use the format `gui/<uid>/<label>` for user/agent domains and `system/<label>` for daemons.

For system-level operations requiring root, the GUI uses AppleScript `with administrator privileges` and the CLI uses `osascript` to prompt for admin credentials.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building from source)
- Swift 5.9+ (for CLI)

## Distribution

### Unsigned (personal use)

```bash
./scripts/create-dmg.sh
# Recipients bypass Gatekeeper with: xattr -cr /Applications/LaunchManager.app
```

### Signed + Notarized (public distribution)

Requires Apple Developer Program ($99/year):

```bash
export DEVELOPER_ID="Zavora Technologies Ltd (TEAMID)"
export APPLE_ID="james.karanja@zavora.ai"
export APPLE_TEAM_ID="YOUR_TEAM_ID"
./scripts/create-dmg.sh
```

## Security Notes

- Runs **without App Sandbox** (required for launchd access)
- System-owned services (`/System/Library/`) are read-only
- Destructive actions require confirmation
- Privileged operations prompt via standard macOS auth dialog
- Universal Binary (arm64 + x86_64)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

## License

Apache License 2.0 — see [LICENSE](LICENSE)

## Author

**James Karanja Maina**
Email: james.karanja@zavora.ai
Company: [Zavora Technologies Ltd](https://zavora.ai)

---

Copyright 2024-2026 Zavora Technologies Ltd
