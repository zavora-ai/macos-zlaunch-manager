# Architecture

## Overview

Launch Manager provides both a GUI and CLI interface for managing macOS launchd services. Both share the same underlying approach: scan plist directories for service definitions, query `launchctl` for runtime status, and execute `launchctl` subcommands for lifecycle management.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                         │
│                                                               │
│   ┌─────────────────────┐     ┌─────────────────────────┐   │
│   │   GUI (SwiftUI)      │     │   CLI (ArgumentParser)   │   │
│   │   LaunchManager.app  │     │   /usr/local/bin/lm      │   │
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
LaunchManagerApp (@main)
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
lm (ParsableCommand)
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
