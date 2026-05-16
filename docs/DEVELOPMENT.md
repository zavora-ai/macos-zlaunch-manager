# Development Guide

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9+ (included with Xcode)

## Project Setup

```bash
git clone https://github.com/zavora/macos-launch-manager.git
cd macos-launch-manager
```

## Building

### GUI App

```bash
# Debug (Xcode)
open LaunchManager/LaunchManager.xcodeproj
# ⌘R to build and run

# Debug (command line)
xcodebuild -project LaunchManager/LaunchManager.xcodeproj \
  -scheme LaunchManager -configuration Debug build

# Release (Universal Binary)
xcodebuild -project LaunchManager/LaunchManager.xcodeproj \
  -scheme LaunchManager -configuration Release \
  -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO build
```

### CLI Tool

```bash
cd cli
swift build              # Debug
swift build -c release   # Release
```

### DMG

```bash
./scripts/create-dmg.sh
# Output: build/LaunchManager-YYYY.MM.DD.dmg
```

## Architecture

### GUI (SwiftUI)

```
ContentView (NavigationSplitView)
├── SidebarView          ← Domain list + stats
│   └── List(selection:) with .tag() for domain switching
├── ServiceListView      ← Filtered/sorted service list
│   └── List(selection:) with ServiceRowView items
└── ServiceDetailView    ← Tabbed detail (.id(service.id) for reset)
    ├── Overview tab     ← Status cards + configuration
    ├── Plist tab        ← XML editor
    ├── Logs tab         ← Log viewer
    └── Info tab         ← Raw launchctl print
```

**Key patterns:**
- `@Observable` on `ServiceManager` and `LaunchdService` for reactive updates
- `.id(service.id)` on detail view forces full recreation on selection change
- `onDelete` closures propagate from detail/context menu back to clear `selectedService`
- `NavigationSplitView` with `List(selection:)` + `.tag()` for sidebar navigation

### CLI (Swift Package Manager)

```
LM (ArgumentParser)
├── list        → discoverAllServices() + updateStatuses()
├── status      → findService() + formatted output
├── start       → bootstrap + kickstart
├── stop        → kill SIGTERM/SIGKILL
├── restart     → stop + start
├── load        → bootstrap
├── unload      → bootout
├── enable      → launchctl enable
├── disable     → launchctl disable
├── logs        → tail stdout/stderr paths
├── info        → launchctl print
├── create      → PropertyListSerialization + write
├── delete      → bootout + rm
└── edit        → $EDITOR on plist path
```

**Key patterns:**
- `shell()` / `shellPrivileged()` for command execution
- `discoverServices()` scans plist directories
- `updateStatuses()` parses `launchctl list` output
- `findService()` does substring matching on labels
- ANSI color output via `colored()` helper

## Key Design Decisions

### No App Sandbox

Required for: filesystem access to all plist directories, running `launchctl`, privilege escalation.

### @Observable over ObservableObject

Modern Swift observation (macOS 14+): finer-grained updates, no `@Published` boilerplate, better performance with 800+ services.

### NavigationSplitView over HSplitView

`HSplitView` caused layout issues when combined with toolbar modifiers. `NavigationSplitView` with `List(selection:)` + `.tag()` provides proper sidebar selection behavior.

### .id(service.id) on Detail View

Forces SwiftUI to destroy and recreate the detail view when selection changes. Prevents stale logs/tabs from previous service bleeding through.

### launchctl CLI over Private APIs

Stable interface, no App Store rejection risk, well-documented, same commands users would run manually.

### Substring Matching in CLI

`lm status yabai` finds `com.asmvik.yabai` — saves typing full reverse-DNS labels.

## Adding Features

### New GUI view

1. Create SwiftUI file in `Views/`
2. Add to `project.pbxproj` (or via Xcode navigator)
3. Wire into parent view

### New CLI command

1. Add struct conforming to `ParsableCommand` in `Commands.swift`
2. Register in `LM.subcommands` array in `LM.swift`
3. Use `findService()` for label lookup, `shell()`/`shellPrivileged()` for execution

### New service action

1. Add method to `ServiceManager.swift`
2. Use `runCommand()` or `runPrivilegedCommand()`
3. Call `refreshService()` after to update status
4. Add UI trigger in `ServiceDetailView` or context menu

## Testing

### Manual test service

```bash
lm create com.test.launchmanager \
  -p /bin/bash \
  --args "-c,echo hello >> /tmp/lm-test.log" \
  --run-at-load \
  --stdout /tmp/lm-test.stdout.log \
  --stderr /tmp/lm-test.stderr.log

lm load com.test.launchmanager
lm start com.test.launchmanager
lm logs com.test.launchmanager
lm delete com.test.launchmanager
```

### Verify universal binary

```bash
file build/release/LaunchManager.app/Contents/MacOS/LaunchManager
# Should show: Mach-O universal binary with 2 architectures: [x86_64] [arm64]
```

## Code Style

- Swift standard naming conventions
- `async/await` over completion handlers
- `@Observable` for state management
- Extract subviews at ~50 lines
- SF Symbols for all icons
- ANSI colors for CLI output (no third-party terminal libraries)
