# Architecture

## Overview

ZLaunch Manager provides both a GUI and CLI interface for managing macOS launchd services. Both share the same underlying approach: scan plist directories for service definitions, query `launchctl` for runtime status, and execute `launchctl` subcommands for lifecycle management.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                         │
│                                                               │
│   ┌─────────────────────┐     ┌─────────────────────────┐   │
│   │   GUI (SwiftUI)      │     │   CLI (ArgumentParser)   │   │
│   │   ZZLaunchManager.app  │     │   /usr/local/bin/zlm      │   │
│   └──────────┬───────────┘     └────────────┬────────────┘   │
├──────────────┼──────────────────────────────┼────────────────┤
│              │     Service Layer             │                 │
│   ┌──────────▼───────────┐     ┌────────────▼────────────┐   │
│   │   ServiceManager     │     │   shell() / helpers      │   │
│   │   (@Observable)      │     │   discoverServices()     │   │
│   └──────────┬───────────┘     └────────────┬────────────┘   │
├──────────────┼──────────────────────────────┼────────────────┤
│              │     System Interface          │                 │
│   ┌──────────▼──────────────────────────────▼────────────┐   │
│   │   /bin/launchctl                                      │   │
│   │   PropertyListSerialization (plist parsing)            │   │
│   │   AuthorizationServices / osascript (privilege)        │   │
│   └──────────────────────────┬───────────────────────────┘   │
├──────────────────────────────┼───────────────────────────────┤
│                              │                                 │
│   ┌──────────────────────────▼───────────────────────────┐   │
│   │                    macOS launchd                       │   │
│   │                                                       │   │
│   │   ~/Library/LaunchAgents     (user agents)            │   │
│   │   /Library/LaunchAgents      (global agents)          │   │
│   │   /Library/LaunchDaemons     (global daemons)         │   │
│   │   /System/Library/LaunchAgents  (system agents)       │   │
│   │   /System/Library/LaunchDaemons (system daemons)      │   │
│   └──────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

## Data Flow

### Service Discovery

```
Plist directories → FileManager.contentsOfDirectory()
                  → PropertyListSerialization.propertyList()
                  → ServiceInfo / LaunchdService objects
```

### Status Updates

```
launchctl list → parse tab-separated output
              → match labels to discovered services
              → set pid, exitStatus, isLoaded, status
```

### Service Actions

```
User action → determine domain target (gui/<uid> or system)
            → construct service target (<domain>/<label>)
            → check if privilege required
            → run launchctl command (direct or via osascript)
            → refresh status
            → update UI
```

## Security Model

| Domain | Read | Write | Control | Privilege |
|--------|------|-------|---------|-----------|
| User Agents | ✅ | ✅ | ✅ | None |
| Global Agents | ✅ | ✅ | ✅ | Admin prompt |
| Global Daemons | ✅ | ✅ | ✅ | Admin prompt |
| System Agents | ✅ | ❌ | Limited | Admin prompt |
| System Daemons | ✅ | ❌ | Limited | Admin prompt |

System-owned services under `/System/Library/` are protected by SIP and displayed as read-only.

## GUI Component Architecture

```
ZLaunchManagerApp (@main)
└── ContentView
    └── NavigationSplitView
        ├── sidebar: SidebarView
        │   └── List(selection: $selectedDomain)
        │       └── ForEach(ServiceDomain.allCases) + .tag()
        │
        ├── content: ServiceListView
        │   ├── Filter toolbar (sort picker, status circles)
        │   └── List(selection: $selectedService)
        │       └── ForEach(filteredServices) → ServiceRowView
        │
        └── detail: ServiceDetailView .id(service.id)
            ├── Header (status badge, label, action buttons)
            └── TabView
                ├── Overview (StatusCards, DetailRows, GroupBoxes)
                ├── PlistEditorView (TextEditor + validation)
                ├── LogViewerView (tail + filter + auto-refresh)
                └── Raw Info (launchctl print output)
```

## CLI Command Architecture

```
zlm (ParsableCommand)
├── list    → discoverAllServices() → updateStatuses() → formatted table
├── status  → findService() → formatted detail
├── start   → findService() → bootstrap (if needed) → kickstart
├── stop    → findService() → kill SIGTERM → (kill SIGKILL if needed)
├── restart → stop → sleep → start
├── load    → findService() → bootstrap
├── unload  → findService() → bootout
├── enable  → findService() → launchctl enable
├── disable → findService() → launchctl disable
├── logs    → findService() → read plist → tail log files
├── info    → findService() → launchctl print
├── create  → build plist dict → serialize → write file
├── delete  → findService() → bootout → rm plist
└── edit    → findService() → exec $EDITOR on plist path
```

## MCP Server Architecture

The MCP server implements the Model Context Protocol (JSON-RPC 2.0 over stdio) to expose launchd management as tools for AI assistants.

```
stdin (JSON-RPC) → MCPServer.handleRequest()
                 ├── initialize → return capabilities + server info
                 ├── tools/list → return 15 tool definitions with schemas
                 └── tools/call → route to ServiceManager method
                                → execute launchctl commands
                                → return text content
                 → stdout (JSON-RPC response)
```

**Key design choices:**
- Zero dependencies — pure Swift, no external packages
- Single binary — compiles to one executable, easy to distribute
- Stdio transport — standard MCP transport, works with any client
- Read-only tools auto-approved — list, status, logs, info, plist_read
- Write tools require approval — start, stop, create, delete, plist_write
- Substring matching on labels — same as CLI, no need for exact labels

## launchctl Command Reference

| Operation | Modern Command | Legacy Equivalent |
|-----------|---------------|-------------------|
| List loaded | `launchctl list` | same |
| Load | `launchctl bootstrap <domain> <plist>` | `launchctl load <plist>` |
| Unload | `launchctl bootout <target>` | `launchctl unload <plist>` |
| Start | `launchctl kickstart -kp <target>` | `launchctl start <label>` |
| Stop | `launchctl kill SIGTERM <target>` | `launchctl stop <label>` |
| Enable | `launchctl enable <target>` | N/A |
| Disable | `launchctl disable <target>` | N/A |
| Info | `launchctl print <target>` | N/A |

Target format: `gui/<uid>/<label>` (user) or `system/<label>` (daemon)
