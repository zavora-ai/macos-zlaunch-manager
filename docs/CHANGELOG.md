# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-07-05

### Changed

- **Renamed the product to ZLaunch Manager** to avoid a naming collision with the
  independently developed [LaunchManager](https://github.com/Sean10000/LaunchManager)
  by Shi-Cheng Ma, whose project and public design docs predate this repository.
  - Repository: `macos-launch-manager` → `macos-zlaunch-manager`
  - GUI app: `LaunchManager` → `ZLaunch Manager` (bundle `com.zavora.zlaunchmanager`)
  - CLI: `lm` → `zlm`
  - MCP server: `lm-mcp-server` → `zlm-mcp-server`
  - Homebrew formula: `lm` → `zlm` (`brew install zavora-ai/tap/zlm`)
- Added a **Related Projects** section to the README acknowledging LaunchManager.

## [1.1.0] - 2026-05-16

### Added

- **MCP Server** — Full Model Context Protocol server for AI-assisted launchd management
  - 18 tools covering complete launchd lifecycle
  - JSON-RPC 2.0 over stdio transport
  - Zero external dependencies (pure Swift)
  - Works with Kiro, Claude Desktop, and any MCP client

- **New tools for launchctl parity:**
  - `launchd_force_reload` — Clears stale state (enable → bootout → bootstrap). Fixes services stuck with I/O errors
  - `launchd_print_disabled` — Queries launchd's internal disabled overrides database (separate from plist `Disabled` key)
  - `launchd_override_status` — Detects conflicts between plist `Disabled` key and launchd's override database

- **Smart start/load recovery:**
  - Automatically checks `print-disabled` before bootstrap
  - Enables service in override database if disabled there
  - Detects "Bootstrap failed: 5: Input/output error" and auto-recovers (enable → bootout stale → retry)

- **Distribution:**
  - Homebrew tap (`brew tap zavora-ai/tap && brew install zlm`)
  - One-liner install script
  - GitHub Actions release workflow with pre-built universal binaries
  - GitHub Release with DMG + CLI binary assets

### Fixed

- Sidebar navigation not switching domains (replaced NavigationLink with List selection + .tag())
- Detail view showing stale data from previous service (added .id(service.id))
- Detail view persisting after service deletion (added onDelete callback)
- "Running" and "Loaded" filter buttons replaced with circular color indicators
- "Updated X ago" timestamp relocated to bottom-left status bar
- App icon now displays in Dock

## [1.0.0] - 2026-05-16

### Added

- **GUI App (SwiftUI)**
  - Three-column NavigationSplitView layout (sidebar, service list, detail)
  - Support for all five launchd domains
  - Service lifecycle management (start, stop, restart, load, unload, enable, disable)
  - Plist editor with XML validation
  - Log viewer with filtering and auto-refresh
  - Service creation wizard with templates
  - Service deletion with confirmation and automatic UI cleanup
  - Search and filter by label or executable path
  - Sort by name, status, or domain
  - Circular status filter icons (green=running, yellow=loaded)
  - Context menus for quick actions
  - Privileged operation support via admin authentication
  - Statistics dashboard in sidebar footer
  - Dark mode support
  - Custom app icon (gear + launch arrow)
  - Detail view resets properly when switching services
  - Universal Binary (arm64 + x86_64)

- **CLI Tool (`zlm`)**
  - `zlm list` — List services with color-coded status indicators
  - `zlm status` — Detailed service information
  - `zlm start/stop/restart` — Service lifecycle control
  - `zlm load/unload` — Bootstrap/bootout services
  - `zlm enable/disable` — Auto-load configuration
  - `zlm logs` — View stdout/stderr with follow mode
  - `zlm info` — Raw launchctl print output
  - `zlm create` — Create new services from command line
  - `zlm delete` — Unload and remove services
  - `zlm edit` — Open plist in $EDITOR
  - Domain filtering (`-d user`, `-d global-daemons`, etc.)
  - Substring search for service labels
  - ANSI color output
  - Privilege escalation for system services

- **Build & Distribution**
  - DMG creation script with install instructions
  - Universal Binary build (Intel + Apple Silicon)
  - Code signing and notarization support
  - GitHub Actions release workflow (auto-builds on tag push)
  - Homebrew tap (`brew tap zavora-ai/tap && brew install zlm`)
  - One-liner install script
  - Apache 2.0 license

- **MCP Server**
  - JSON-RPC 2.0 over stdio (standard MCP transport)
  - 15 tools covering full launchd lifecycle
  - `launchd_list` — List services with filtering by domain/status/label
  - `launchd_status` — Detailed service information
  - `launchd_start/stop/restart` — Service lifecycle control
  - `launchd_load/unload` — Bootstrap/bootout services
  - `launchd_enable/disable` — Auto-load configuration
  - `launchd_logs` — Read stdout/stderr log files
  - `launchd_info` — Raw launchctl print output
  - `launchd_create` — Create new service plists
  - `launchd_delete` — Unload and remove services
  - `launchd_plist_read/plist_write` — Read/write raw plist XML
  - Zero external dependencies (pure Swift)
  - Works with Kiro, Claude Desktop, and any MCP-compatible client

### Architecture

- SwiftUI with `@Observable` pattern (macOS 14+)
- NavigationSplitView with proper selection handling
- Swift Package Manager for CLI with ArgumentParser
- `launchctl` CLI interface (no private APIs)
- AppleScript privilege escalation for system operations
