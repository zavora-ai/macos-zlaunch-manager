# Usage Guide

## GUI App

### Getting Started

Launch the app and it automatically scans all launchd domains. The initial load takes a few seconds to parse plist files from all five directories.

### Interface Layout

| Panel | Purpose |
|-------|---------|
| Left sidebar | Domain navigation + statistics |
| Center list | Services in selected domain |
| Right detail | Full details for selected service |

### Navigating Domains

Click any domain in the sidebar:

- **User Agents** — Your personal agents (`~/Library/LaunchAgents`)
- **Global Agents** — Third-party system-wide agents (`/Library/LaunchAgents`)
- **Global Daemons** — Third-party daemons running as root (`/Library/LaunchDaemons`)
- **System Agents** — Apple's built-in agents (read-only)
- **System Daemons** — Apple's built-in daemons (read-only)

Green badges show running service count per domain.

### Status Indicators

| Symbol | Color | Meaning |
|--------|-------|---------|
| ● | Green | Running (has active PID) |
| ◐ | Yellow/Blue | Loaded but not running |
| ○ | Gray | Not loaded |
| ⚠ | Orange | Exited with error |

### Filtering Services

In the service list toolbar:
- **Green circle** — Toggle to show only running services
- **Yellow circle** — Toggle to show only loaded services
- **Sort picker** — Sort by Name, Status, or Domain
- **Search** — Filter by label or executable path (toolbar search field)

### Managing Services

Select a service, then use the action buttons in the detail header:

- **Start** (green) — Loads the service if needed, then kicks it off
- **Stop** (red) — Sends SIGTERM; escalates to SIGKILL if needed
- **Restart** — Stop then start
- **⋯ Menu** — Load/Unload, Enable/Disable, Reveal in Finder, Copy Label, Delete

### Viewing Details

The detail pane has four tabs:

1. **Overview** — Status cards, configuration, log paths, environment variables
2. **Plist** — Raw XML editor with validation and save
3. **Logs** — Live log viewer with filter, line count, auto-refresh, copy
4. **Info** — Raw `launchctl print` output

### Creating Services

1. Click **+** in the toolbar
2. Choose a template or start custom
3. Fill in label (reverse-DNS), program path, domain
4. Configure behavior (run at load, keep alive, interval)
5. Set log paths and environment variables
6. Click **Create Service**

### Deleting Services

- Right-click → Delete, or
- Detail view → ⋯ menu → Delete Service

Both unload the service first, then remove the plist file. The detail view clears automatically.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘R | Refresh all services |
| ⌘, | Open Settings |

---

## CLI Tool (`zlm`)

### Installation

```bash
cd cli
swift build -c release
cp .build/release/zlm /usr/local/bin/zlm
```

### Quick Reference

```bash
# Browse
zlm                          # List all services
zlm list -d user             # User agents only
zlm list --running           # Only running
zlm list -f nginx            # Search by name
zlm status com.my.service    # Detailed info

# Control
zlm start <label>            # Start service
zlm stop <label>             # Stop service
zlm stop -f <label>          # Force kill
zlm restart <label>          # Restart

# Configuration
zlm load <label>             # Load into launchd
zlm unload <label>           # Remove from launchd
zlm enable <label>           # Auto-start on login
zlm disable <label>          # Prevent auto-start

# Logs & Info
zlm logs <label>             # View logs
zlm logs -f <label>          # Follow (tail -f)
zlm logs -l 500 <label>     # Last 500 lines
zlm info <label>             # launchctl print output

# Manage
zlm create com.co.svc -p /path/to/bin --run-at-load
zlm delete <label>           # Remove service
zlm edit <label>             # Open plist in $EDITOR

# GUI
zlm gui                      # Open GUI app (installs if needed)
zlm gui --reinstall          # Force reinstall from GitHub
```

### Label Matching

The CLI uses substring matching — you don't need the full label:

```bash
zlm status yabai             # Matches com.asmvik.yabai
zlm logs gateway             # Matches com.zavora.adk-gateway
zlm stop docker              # Matches com.docker.helper
```

### Privilege Escalation

For system services (global daemons, system agents/daemons), the CLI automatically prompts for admin credentials via a macOS dialog. No `sudo` needed.

---

## MCP Server

The MCP server lets AI assistants manage launchd services directly.

### Installation

```bash
cd mcp-server
swift build -c release
cp .build/release/zlm-mcp-server /usr/local/bin/
```

### Configuration

Add to your MCP client config:

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

### What You Can Ask

Once configured, your AI assistant can:

- "List all running launchd services"
- "What's the status of my adk-gateway service?"
- "Stop com.zavora.adk-gateway"
- "Show me the logs for yabai"
- "Create a new service that runs my backup script every hour"
- "Disable the Google updater from running at login"
- "Read the plist for com.asmvik.yabai"
- "Restart all my user agents"

### Auto-Approved vs Manual Approval

Read-only tools are safe to auto-approve:
- `launchd_list`, `launchd_status`, `launchd_logs`, `launchd_info`, `launchd_plist_read`

Write tools should require approval:
- `launchd_start`, `launchd_stop`, `launchd_restart`, `launchd_load`, `launchd_unload`, `launchd_enable`, `launchd_disable`, `launchd_create`, `launchd_delete`, `launchd_plist_write`

---

## Troubleshooting

### "Operation not permitted"

Some system services are protected by SIP. This is expected — you cannot control Apple's core services.

### Service won't start

1. Check if it's loaded: `zlm status <label>`
2. If not loaded: `zlm load <label>` first
3. Check logs: `zlm logs <label>`
4. Verify the executable exists and is executable

### GUI shows stale data

Press ⌘R to refresh. The app doesn't auto-refresh by default to avoid unnecessary system calls.

### Installed app has broken layout

Clear saved window state:
```bash
defaults delete com.zavora.zlaunchmanager
rm -rf ~/Library/Saved\ Application\ State/com.zavora.zlaunchmanager.savedState
```

### CLI not found after install

Ensure `/usr/local/bin` is in your PATH:
```bash
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```
