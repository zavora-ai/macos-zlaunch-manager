# macOS ZLaunch Manager

A native macOS GUI + CLI for managing launchd services. Replaces the need to wrestle with `launchctl` commands and plist files directly.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![Universal Binary](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-green)
![License](https://img.shields.io/badge/License-Apache%202.0-green)

## What It Does

macOS uses `launchd` to manage all background services, but there's no built-in GUI for it (unlike Windows Services or Linux systemctl). ZLaunch Manager fills that gap with:

![ZLaunch Manager Screenshot](docs/screenshot.png)

- **GUI App** — Three-column SwiftUI interface for browsing, controlling, and configuring services
- **CLI Tool (`zlm`)** — Fast terminal interface for the same operations
- **MCP Server** — Model Context Protocol server so AI assistants (Kiro, Claude Desktop) can manage launchd services

## Installation

### CLI — One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/zavora-ai/macos-zlaunch-manager/main/scripts/install.sh | bash
```

### CLI — Homebrew

```bash
brew tap zavora-ai/tap
brew install zlm
```

### CLI — Download binary

```bash
# From GitHub Releases (no Swift/Xcode needed)
curl -L https://github.com/zavora-ai/macos-zlaunch-manager/releases/latest/download/zlm-v1.2.0-macos-universal.tar.gz | tar xz
sudo mv zlm /usr/local/bin/
```

### CLI — Build from source

```bash
git clone https://github.com/zavora-ai/macos-zlaunch-manager.git
cd macos-zlaunch-manager/cli
swift build -c release
cp .build/release/zlm /usr/local/bin/zlm
```

### GUI App — DMG

```bash
# Build locally
./scripts/create-dmg.sh
# Output: build/ZLaunchManager-YYYY.MM.DD.dmg
# Open DMG → drag to Applications
```

Or download from [GitHub Releases](https://github.com/zavora-ai/macos-zlaunch-manager/releases).

### MCP Server

```bash
# Build and install
cd mcp-server
swift build -c release
cp .build/release/zlm-mcp-server /usr/local/bin/

# Add to Kiro (~/.kiro/settings/mcp.json)
```

```json
{
  "mcpServers": {
    "launchd": {
      "command": "/usr/local/bin/zlm-mcp-server",
      "args": [],
      "autoApprove": ["launchd_list", "launchd_status", "launchd_logs", "launchd_info", "launchd_plist_read"]
    }
  }
}
```

For Claude Desktop, add to `~/Library/Application Support/Claude/claude_desktop_config.json`.

## CLI Usage

The `zlm` command provides full service management from the terminal:

```bash
# List services
zlm                                  # All services (default)
zlm list -d user                     # User agents only
zlm list -d global-daemons           # Global daemons only
zlm list --running                   # Only running services
zlm list --loaded                    # Only loaded services
zlm list -f docker                   # Filter by name substring

# Service info
zlm status <label>                   # Detailed status
zlm info <label>                     # Raw launchctl print output
zlm logs <label>                     # View stdout/stderr logs
zlm logs -f <label>                  # Follow logs (tail -f)
zlm logs -l 200 <label>             # Last 200 lines

# Control services
zlm start <label>                    # Start (auto-loads if needed)
zlm stop <label>                     # Stop (SIGTERM)
zlm stop -f <label>                  # Force kill (SIGKILL)
zlm restart <label>                  # Stop + start

# Load/unload
zlm load <label>                     # Bootstrap into launchd
zlm unload <label>                   # Bootout from launchd

# Enable/disable
zlm enable <label>                   # Auto-load on boot/login
zlm disable <label>                  # Prevent auto-load

# Create/delete
zlm create com.company.myservice \
    -p /usr/local/bin/myapp \
    --run-at-load --keep-alive \
    --stdout /tmp/myservice.log \
    --stderr /tmp/myservice.err

zlm delete <label>                   # Unload + remove plist
zlm delete -y <label>               # Skip confirmation

# Edit
zlm edit <label>                     # Open plist in $EDITOR

# GUI
zlm gui                              # Open GUI app (installs if not found)
zlm gui --reinstall                  # Force reinstall GUI from GitHub
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

## MCP Server

The MCP server exposes launchd management as tools for AI assistants. It implements the Model Context Protocol (JSON-RPC 2.0 over stdio).

### Available Tools

| Tool | Description |
|------|-------------|
| `launchd_list` | List services with domain/status/label filtering |
| `launchd_status` | Detailed service info (PID, exit code, config) |
| `launchd_start` | Start a service (auto-loads if needed) |
| `launchd_stop` | Stop a service (SIGTERM or SIGKILL) |
| `launchd_restart` | Restart a service |
| `launchd_load` | Bootstrap a service into launchd |
| `launchd_unload` | Bootout a service from launchd |
| `launchd_enable` | Enable auto-load on boot/login |
| `launchd_disable` | Disable auto-load |
| `launchd_logs` | Read stdout/stderr log files |
| `launchd_info` | Raw `launchctl print` output |
| `launchd_create` | Create a new service plist |
| `launchd_delete` | Unload and remove a service |
| `launchd_plist_read` | Read raw XML plist content |
| `launchd_plist_write` | Write/update plist content with validation |
| `launchd_force_reload` | Clear stale state and reload (bootout + enable + bootstrap) |
| `launchd_print_disabled` | Query launchd's internal disabled overrides database |
| `launchd_override_status` | Detect conflicts between plist and launchd override state |
| `launchd_open_gui` | Open the ZLaunch Manager GUI app |

### Configuration

**Kiro** (`~/.kiro/settings/mcp.json`):
```json
{
  "mcpServers": {
    "launchd": {
      "command": "/usr/local/bin/zlm-mcp-server",
      "args": [],
      "autoApprove": ["launchd_list", "launchd_status", "launchd_logs", "launchd_info", "launchd_plist_read"]
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "launchd": {
      "command": "/usr/local/bin/zlm-mcp-server"
    }
  }
}
```

### Example Prompts

Once configured, you can ask your AI assistant:
- "List all running launchd services"
- "What's the status of my adk-gateway service?"
- "Stop com.zavora.adk-gateway"
- "Show me the logs for yabai"
- "Create a new service that runs my backup script every hour"
- "Disable the Google updater from running at login"
- "Force reload the adk-gateway service — it's stuck"
- "Check if any services have conflicting disabled states"
- "Open the ZLaunch Manager GUI"

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
macos-zlaunch-manager/
├── ZLaunchManager/                  # GUI App (SwiftUI)
│   ├── ZLaunchManager.xcodeproj
│   └── ZLaunchManager/
│       ├── ZLaunchManagerApp.swift
│       ├── ContentView.swift
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
│       ├── LM.swift
│       ├── Commands.swift
│       └── Helpers.swift
├── mcp-server/                     # MCP Server (Swift Package)
│   ├── Package.swift
│   └── Sources/
│       ├── main.swift
│       ├── MCPServer.swift
│       └── ServiceManager.swift
├── scripts/
│   ├── create-dmg.sh
│   ├── install.sh
│   ├── generate-dmg-background.py
│   └── dmg-background.png
├── docs/
│   ├── ARCHITECTURE.md
│   ├── USAGE.md
│   ├── DEVELOPMENT.md
│   └── CHANGELOG.md
├── .github/workflows/release.yml
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
# Recipients bypass Gatekeeper with: xattr -cr /Applications/ZLaunchManager.app
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

## Related Projects

- **[LaunchManager](https://github.com/Sean10000/LaunchManager)** by Shi-Cheng Ma ([launchmanager.dev](https://www.launchmanager.dev/)) — an independently developed macOS launchd manager whose project and public design documents predate this repository. ZLaunch Manager was built independently, but because launchd constrains the solution space heavily, the two share a similar feature set and idiomatic macOS UI patterns. We renamed our project from "LaunchManager" to "ZLaunch Manager" to avoid confusion, since theirs came first. If you're comparing options, check out their project too.

Other launchd tools worth knowing:
- [LaunchControl](https://www.soma-zone.com/LaunchControl/) — mature commercial launchd GUI
- [glowinthedark/pylaunchd](https://github.com/glowinthedark/pylaunchd) — Python launchd GUI

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
