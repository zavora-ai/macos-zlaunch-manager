import ArgumentParser
import Foundation

// MARK: - List

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List launchd services"
    )

    @Option(name: .shortAndLong, help: "Domain to list (user, global-agents, global-daemons, system-agents, system-daemons, all)")
    var domain: Domain = .all

    @Flag(name: .shortAndLong, help: "Show only running services")
    var running = false

    @Flag(name: .shortAndLong, help: "Show only loaded services")
    var loaded = false

    @Flag(name: .shortAndLong, help: "Show only stopped services")
    var stopped = false

    @Option(name: .shortAndLong, help: "Filter by label (substring match)")
    var filter: String?

    func run() {
        let domains: [Domain] = domain == .all ? Domain.scannable : [domain]
        var services = discoverAllServices(domains: domains)
        updateStatuses(&services)

        // Apply filters
        if running { services = services.filter { $0.isRunning } }
        if loaded { services = services.filter { $0.isLoaded } }
        if stopped { services = services.filter { !$0.isLoaded } }
        if let filter = filter {
            let q = filter.lowercased()
            services = services.filter { $0.label.lowercased().contains(q) }
        }

        services.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        if services.isEmpty {
            print(colored("No services found.", .gray))
            return
        }

        // Header
        print(colored("  ST  LABEL                                              PID      STATUS       DOMAIN", .gray))
        print(colored("  " + String(repeating: "─", count: 90), .gray))

        for svc in services {
            let symbol = colored(svc.statusSymbol, svc.statusColor)
            let pidStr = svc.pid != nil && svc.pid! > 0 ? String(svc.pid!) : "-"
            let statusStr = colored(svc.statusText, svc.statusColor)
            let labelStr = String(svc.label.prefix(48))
            let domainStr = svc.domain.displayName

            let paddedLabel = labelStr.padding(toLength: 48, withPad: " ", startingAt: 0)
            let paddedPid = pidStr.padding(toLength: 8, withPad: " ", startingAt: 0)
            let paddedDomain = domainStr

            print("  \(symbol)  \(paddedLabel) \(paddedPid) \(statusStr)\t\(colored(paddedDomain, .gray))")
        }

        print("")
        let total = services.count
        let runCount = services.filter { $0.isRunning }.count
        let loadCount = services.filter { $0.isLoaded && !$0.isRunning }.count
        print(colored("  \(total) services", .white) + " │ " +
              colored("● \(runCount) running", .green) + " │ " +
              colored("◐ \(loadCount) loaded", .blue) + " │ " +
              colored("○ \(total - runCount - loadCount) stopped", .gray))
    }
}

// MARK: - Status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show detailed status of a service"
    )

    @Argument(help: "Service label (or substring)")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        print("")
        print(bold("  \(svc.label)"))
        print(colored("  \(svc.domain.displayName)", .gray))
        print("")

        let symbol = colored(svc.statusSymbol, svc.statusColor)
        print("  Status:     \(symbol) \(colored(svc.statusText, svc.statusColor))")
        if let pid = svc.pid, pid > 0 {
            print("  PID:        \(pid)")
        }
        if let exit = svc.exitStatus {
            print("  Exit Code:  \(exit == 0 ? colored("\(exit)", .green) : colored("\(exit)", .yellow))")
        }
        print("  Loaded:     \(svc.isLoaded ? colored("yes", .green) : colored("no", .gray))")
        print("  Enabled:    \(svc.disabled ? colored("no", .yellow) : colored("yes", .green))")
        print("")
        print("  Plist:      \(svc.plistPath)")
        if let prog = svc.program {
            print("  Executable: \(prog)")
        }
        print("  Run at Load: \(svc.runAtLoad ? "yes" : "no")")
        print("  Keep Alive:  \(svc.keepAlive ? "yes" : "no")")
        print("")
    }
}

// MARK: - Start

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a service"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"

        // Load first if not loaded
        if !svc.isLoaded {
            print(colored("  Loading \(svc.label)...", .gray))
            if svc.domain.requiresPrivilege {
                shellPrivileged("/bin/launchctl", ["bootstrap", svc.domain.domainTarget, svc.plistPath])
            } else {
                shell("/bin/launchctl", ["bootstrap", svc.domain.domainTarget, svc.plistPath])
            }
            Thread.sleep(forTimeInterval: 0.3)
        }

        print(colored("  Starting \(svc.label)...", .cyan))
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["kickstart", "-kp", target])
        } else {
            result = shell("/bin/launchctl", ["kickstart", "-kp", target])
        }

        Thread.sleep(forTimeInterval: 0.5)

        if result.exitCode == 0 {
            print(colored("  ✓ Started \(svc.label)", .green))
        } else {
            print(colored("  ✗ Failed to start: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Stop

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop a running service"
    )

    @Argument(help: "Service label")
    var label: String

    @Flag(name: .shortAndLong, help: "Force kill (SIGKILL)")
    var force = false

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"
        let signal = force ? "SIGKILL" : "SIGTERM"

        print(colored("  Stopping \(svc.label) (\(signal))...", .cyan))
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["kill", signal, target])
        } else {
            result = shell("/bin/launchctl", ["kill", signal, target])
        }

        if result.exitCode == 0 || result.output.isEmpty {
            print(colored("  ✓ Stopped \(svc.label)", .green))
        } else {
            print(colored("  ✗ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Restart

struct Restart: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Restart a service (stop + start)"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"

        if svc.isRunning {
            print(colored("  Stopping \(svc.label)...", .cyan))
            if svc.domain.requiresPrivilege {
                shellPrivileged("/bin/launchctl", ["kill", "SIGTERM", target])
            } else {
                shell("/bin/launchctl", ["kill", "SIGTERM", target])
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        print(colored("  Starting \(svc.label)...", .cyan))
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["kickstart", "-kp", target])
        } else {
            result = shell("/bin/launchctl", ["kickstart", "-kp", target])
        }

        if result.exitCode == 0 {
            print(colored("  ✓ Restarted \(svc.label)", .green))
        } else {
            print(colored("  ✗ Failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Load

struct Load: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Load (bootstrap) a service into launchd"
    )

    @Argument(help: "Service label or plist path")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        print(colored("  Loading \(svc.label)...", .cyan))
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["bootstrap", svc.domain.domainTarget, svc.plistPath])
        } else {
            result = shell("/bin/launchctl", ["bootstrap", svc.domain.domainTarget, svc.plistPath])
        }

        if result.exitCode == 0 || result.output.isEmpty {
            print(colored("  ✓ Loaded \(svc.label)", .green))
        } else {
            print(colored("  ✗ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Unload

struct Unload: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Unload (bootout) a service from launchd"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"

        print(colored("  Unloading \(svc.label)...", .cyan))
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["bootout", target])
        } else {
            result = shell("/bin/launchctl", ["bootout", target])
        }

        if result.exitCode == 0 || result.output.isEmpty {
            print(colored("  ✓ Unloaded \(svc.label)", .green))
        } else {
            print(colored("  ✗ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Enable

struct Enable: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enable a service (auto-load on boot/login)"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["enable", target])
        } else {
            result = shell("/bin/launchctl", ["enable", target])
        }

        if result.exitCode == 0 || result.output.isEmpty {
            print(colored("  ✓ Enabled \(svc.label)", .green))
        } else {
            print(colored("  ✗ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Disable

struct Disable: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Disable a service (prevent auto-load)"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"
        let result: (output: String, exitCode: Int32)
        if svc.domain.requiresPrivilege {
            result = shellPrivileged("/bin/launchctl", ["disable", target])
        } else {
            result = shell("/bin/launchctl", ["disable", target])
        }

        if result.exitCode == 0 || result.output.isEmpty {
            print(colored("  ✓ Disabled \(svc.label)", .green))
        } else {
            print(colored("  ✗ \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", .red))
        }
    }
}

// MARK: - Logs

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "View service logs"
    )

    @Argument(help: "Service label")
    var label: String

    @Option(name: .shortAndLong, help: "Number of lines to show")
    var lines: Int = 50

    @Flag(name: .shortAndLong, help: "Follow log output (like tail -f)")
    var follow = false

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        // Read plist to find log paths
        let fm = FileManager.default
        guard let data = fm.contents(atPath: svc.plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            print(colored("✗ Cannot read plist", .red))
            throw ExitCode.failure
        }

        let stdoutPath = plist["StandardOutPath"] as? String
        let stderrPath = plist["StandardErrorPath"] as? String

        var hasLogs = false

        if let path = stdoutPath, fm.fileExists(atPath: path) {
            print(colored("── stdout: \(path) ──", .cyan))
            if follow {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                process.arguments = ["-f", "-n", "\(lines)", path]
                try? process.run()
                process.waitUntilExit()
            } else {
                let (output, _) = shell("/usr/bin/tail", ["-n", "\(lines)", path])
                print(output)
            }
            hasLogs = true
        }

        if let path = stderrPath, fm.fileExists(atPath: path) {
            print(colored("── stderr: \(path) ──", .yellow))
            let (output, _) = shell("/usr/bin/tail", ["-n", "\(lines)", path])
            print(output)
            hasLogs = true
        }

        if !hasLogs {
            // Try system log
            print(colored("── system log ──", .cyan))
            let (output, _) = shell("/usr/bin/log", [
                "show", "--predicate", "subsystem == '\(svc.label)'",
                "--last", "1h", "--style", "compact"
            ])
            if output.isEmpty || output.contains("No log messages") {
                print(colored("  No logs found. Configure StandardOutPath/StandardErrorPath in the plist.", .gray))
            } else {
                print(output)
            }
        }
    }
}

// MARK: - Info

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show raw launchctl print output for a service"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let target = "\(svc.domain.domainTarget)/\(svc.label)"
        let (output, _) = shell("/bin/launchctl", ["print", target])
        print(output)
    }
}

// MARK: - Create

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new launchd service"
    )

    @Argument(help: "Service label (reverse-DNS, e.g. com.company.myservice)")
    var label: String

    @Option(name: .shortAndLong, help: "Program path to execute")
    var program: String

    @Option(name: .shortAndLong, help: "Domain (user, global-agents, global-daemons)")
    var domain: Domain = .user

    @Option(name: .long, help: "Program arguments (comma-separated)")
    var args: String?

    @Flag(name: .long, help: "Run at load")
    var runAtLoad = false

    @Flag(name: .long, help: "Keep alive (restart on exit)")
    var keepAlive = false

    @Option(name: .long, help: "Start interval in seconds")
    var interval: Int?

    @Option(name: .long, help: "Working directory")
    var workDir: String?

    @Option(name: .long, help: "Stdout log path")
    var stdout: String?

    @Option(name: .long, help: "Stderr log path")
    var stderr: String?

    func run() throws {
        guard label.contains(".") else {
            print(colored("✗ Label must be reverse-DNS format (e.g. com.company.service)", .red))
            throw ExitCode.failure
        }

        var plist: [String: Any] = ["Label": label]

        var programArgs = [program]
        if let args = args {
            programArgs.append(contentsOf: args.split(separator: ",").map(String.init))
        }
        plist["ProgramArguments"] = programArgs

        if runAtLoad { plist["RunAtLoad"] = true }
        if keepAlive { plist["KeepAlive"] = true }
        if let interval = interval { plist["StartInterval"] = interval }
        if let dir = workDir { plist["WorkingDirectory"] = dir }
        if let out = stdout { plist["StandardOutPath"] = out }
        if let err = stderr { plist["StandardErrorPath"] = err }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            print(colored("✗ Failed to serialize plist", .red))
            throw ExitCode.failure
        }

        let filePath = (domain.path as NSString).appendingPathComponent("\(label).plist")

        if domain.requiresPrivilege {
            let tempPath = NSTemporaryDirectory() + "\(label).plist"
            FileManager.default.createFile(atPath: tempPath, contents: data)
            shellPrivileged("/bin/cp", [tempPath, filePath])
            try? FileManager.default.removeItem(atPath: tempPath)
        } else {
            try? FileManager.default.createDirectory(atPath: domain.path, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: filePath, contents: data)
        }

        print(colored("  ✓ Created \(filePath)", .green))
        print(colored("  Run `lm load \(label)` to load it", .gray))
    }
}

// MARK: - Delete

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a service (unload + remove plist)"
    )

    @Argument(help: "Service label")
    var label: String

    @Flag(name: .shortAndLong, help: "Skip confirmation")
    var yes = false

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        if svc.domain == .systemAgents || svc.domain == .systemDaemons {
            print(colored("✗ Cannot delete system-owned services", .red))
            throw ExitCode.failure
        }

        if !yes {
            print("  Delete \(svc.label)?")
            print("  Path: \(svc.plistPath)")
            print("  Type 'yes' to confirm: ", terminator: "")
            guard readLine()?.lowercased() == "yes" else {
                print(colored("  Cancelled.", .gray))
                return
            }
        }

        // Unload first
        if svc.isLoaded {
            let target = "\(svc.domain.domainTarget)/\(svc.label)"
            if svc.domain.requiresPrivilege {
                shellPrivileged("/bin/launchctl", ["bootout", target])
            } else {
                shell("/bin/launchctl", ["bootout", target])
            }
        }

        // Remove plist
        if svc.domain.requiresPrivilege {
            shellPrivileged("/bin/rm", [svc.plistPath])
        } else {
            try? FileManager.default.removeItem(atPath: svc.plistPath)
        }

        print(colored("  ✓ Deleted \(svc.label)", .green))
    }
}

// MARK: - Edit

struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open service plist in your default editor"
    )

    @Argument(help: "Service label")
    var label: String

    func run() throws {
        guard let svc = findService(label: label) else {
            print(colored("✗ Service not found: \(label)", .red))
            throw ExitCode.failure
        }

        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "nano"
        print(colored("  Opening \(svc.plistPath) in \(editor)...", .gray))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, svc.plistPath]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try? process.run()
        process.waitUntilExit()
    }
}


// MARK: - GUI

struct GUI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open the Launch Manager GUI app (installs if not found)"
    )

    @Flag(name: .long, help: "Force reinstall even if already installed")
    var reinstall = false

    func run() throws {
        if !reinstall {
            // Try to open existing installation
            let appPaths = [
                "/Applications/LaunchManager.app",
                NSHomeDirectory() + "/Applications/LaunchManager.app",
            ]

            for path in appPaths {
                if FileManager.default.fileExists(atPath: path) {
                    print(colored("  Opening Launch Manager...", .cyan))
                    shell("/usr/bin/open", [path])
                    return
                }
            }

            // Try by bundle ID
            let (_, exitCode) = shell("/usr/bin/open", ["-b", "com.launchmanager.app"])
            if exitCode == 0 {
                print(colored("  Opening Launch Manager...", .cyan))
                return
            }
        }

        // Not installed — offer to install
        print(colored("  Launch Manager.app not found.", .yellow))
        print("")
        print("  Install options:")
        print("    1. Download from GitHub Releases (recommended)")
        print("    2. Build from source")
        print("")
        print("  Select [1/2]: ", terminator: "")

        guard let choice = readLine()?.trimmingCharacters(in: .whitespaces) else {
            throw ExitCode.failure
        }

        switch choice {
        case "1":
            installFromRelease()
        case "2":
            try installFromSource()
        default:
            print(colored("  Cancelled.", .gray))
        }
    }

    private func installFromRelease() {
        print(colored("  Downloading latest release...", .cyan))

        let dmgPath = "/tmp/LaunchManager-latest.dmg"
        let (_, dlExit) = shell("/usr/bin/curl", [
            "-L", "-o", dmgPath,
            "https://github.com/zavora-ai/macos-launch-manager/releases/latest/download/LaunchManager-v1.1.0.dmg"
        ])

        guard dlExit == 0 else {
            print(colored("  ✗ Download failed.", .red))
            return
        }

        print(colored("  Mounting DMG...", .cyan))
        let (_, _) = shell("/usr/bin/hdiutil", ["attach", dmgPath, "-nobrowse", "-quiet"])

        // Find mount point
        let mountPoint = "/Volumes/Launch Manager"
        let appSource = "\(mountPoint)/LaunchManager.app"

        guard FileManager.default.fileExists(atPath: appSource) else {
            print(colored("  ✗ Could not find app in DMG.", .red))
            shell("/usr/bin/hdiutil", ["detach", mountPoint])
            return
        }

        print(colored("  Installing to /Applications...", .cyan))
        // Remove old version if exists
        try? FileManager.default.removeItem(atPath: "/Applications/LaunchManager.app")

        do {
            try FileManager.default.copyItem(atPath: appSource, toPath: "/Applications/LaunchManager.app")
        } catch {
            // Try with elevated privileges
            print(colored("  Requires admin access...", .gray))
            shellPrivileged("/bin/cp", ["-R", appSource, "/Applications/LaunchManager.app"])
        }

        // Unmount and clean up
        shell("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
        try? FileManager.default.removeItem(atPath: dmgPath)

        // Remove quarantine
        shell("/usr/bin/xattr", ["-cr", "/Applications/LaunchManager.app"])

        if FileManager.default.fileExists(atPath: "/Applications/LaunchManager.app") {
            print(colored("  ✓ Installed to /Applications/LaunchManager.app", .green))
            print(colored("  Opening...", .cyan))
            shell("/usr/bin/open", ["/Applications/LaunchManager.app"])
        } else {
            print(colored("  ✗ Installation failed.", .red))
        }
    }

    private func installFromSource() throws {
        let repoURL = "https://github.com/zavora-ai/macos-launch-manager.git"
        let tempDir = "/tmp/lm-gui-build"

        try? FileManager.default.removeItem(atPath: tempDir)

        print(colored("  Cloning repository...", .cyan))
        let (_, cloneExit) = shell("/usr/bin/git", ["clone", "--depth", "1", "--quiet", repoURL, tempDir])
        guard cloneExit == 0 else {
            print(colored("  ✗ Clone failed.", .red))
            throw ExitCode.failure
        }

        print(colored("  Building (this may take a minute)...", .cyan))
        let projectPath = "\(tempDir)/LaunchManager/LaunchManager.xcodeproj"
        let (buildOutput, _) = shell("/usr/bin/xcodebuild", [
            "-project", projectPath,
            "-scheme", "LaunchManager",
            "-configuration", "Release",
            "-arch", "arm64", "-arch", "x86_64",
            "ONLY_ACTIVE_ARCH=NO",
            "CONFIGURATION_BUILD_DIR=\(tempDir)/build",
            "build"
        ])

        let builtApp = "\(tempDir)/build/LaunchManager.app"
        guard FileManager.default.fileExists(atPath: builtApp) else {
            print(colored("  ✗ Build failed.", .red))
            if buildOutput.contains("error:") {
                let errors = buildOutput.components(separatedBy: "\n").filter { $0.contains("error:") }
                for err in errors.prefix(3) { print("    \(err)") }
            }
            throw ExitCode.failure
        }

        print(colored("  Installing to /Applications...", .cyan))
        try? FileManager.default.removeItem(atPath: "/Applications/LaunchManager.app")

        do {
            try FileManager.default.copyItem(atPath: builtApp, toPath: "/Applications/LaunchManager.app")
        } catch {
            shellPrivileged("/bin/cp", ["-R", builtApp, "/Applications/LaunchManager.app"])
        }

        // Clean up
        try? FileManager.default.removeItem(atPath: tempDir)

        if FileManager.default.fileExists(atPath: "/Applications/LaunchManager.app") {
            print(colored("  ✓ Installed to /Applications/LaunchManager.app", .green))
            print(colored("  Opening...", .cyan))
            shell("/usr/bin/open", ["/Applications/LaunchManager.app"])
        } else {
            print(colored("  ✗ Installation failed.", .red))
            throw ExitCode.failure
        }
    }
}
