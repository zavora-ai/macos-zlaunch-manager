# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- **CLI Tool (`lm`)**
  - `lm list` — List services with color-coded status indicators
  - `lm status` — Detailed service information
  - `lm start/stop/restart` — Service lifecycle control
  - `lm load/unload` — Bootstrap/bootout services
  - `lm enable/disable` — Auto-load configuration
  - `lm logs` — View stdout/stderr with follow mode
  - `lm info` — Raw launchctl print output
  - `lm create` — Create new services from command line
  - `lm delete` — Unload and remove services
  - `lm edit` — Open plist in $EDITOR
  - Domain filtering (`-d user`, `-d global-daemons`, etc.)
  - Substring search for service labels
  - ANSI color output
  - Privilege escalation for system services

- **Build & Distribution**
  - DMG creation script with install instructions
  - Universal Binary build (Intel + Apple Silicon)
  - Code signing and notarization support
  - GitHub Actions release workflow (auto-builds on tag push)
  - Homebrew tap (`brew tap zavora-ai/tap && brew install lm`)
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
