import Foundation

class ServiceManager {
    private let fm = FileManager.default

    // MARK: - Domain Mapping

    private func domainPath(_ domain: String) -> String {
        switch domain {
        case "user": return NSHomeDirectory() + "/Library/LaunchAgents"
        case "global-agents": return "/Library/LaunchAgents"
        case "global-daemons": return "/Library/LaunchDaemons"
        case "system-agents": return "/System/Library/LaunchAgents"
        case "system-daemons": return "/System/Library/LaunchDaemons"
        default: return ""
        }
    }

    private func domainTarget(_ domain: String) -> String {
        switch domain {
        case "user", "global-agents", "system-agents":
            return "gui/\(getuid())"
        default:
            return "system"
        }
    }

    private func requiresPrivilege(_ domain: String) -> Bool {
        domain != "user"
    }

    private let allDomains = ["user", "global-agents", "global-daemons", "system-agents", "system-daemons"]

    // MARK: - Service Discovery

    private struct ServiceInfo {
        let label: String
        let domain: String
        let plistPath: String
        var pid: Int?
        var exitStatus: Int?
        var isLoaded: Bool = false
        var program: String?
        var runAtLoad: Bool = false
        var keepAlive: Bool = false
        var disabled: Bool = false

        var isRunning: Bool { pid != nil && pid! > 0 }
        var statusText: String {
            if isRunning { return "running" }
            if isLoaded && exitStatus != nil && exitStatus != 0 { return "error(\(exitStatus!))" }
            if isLoaded { return "loaded" }
            return "stopped"
        }
    }

    private func discoverServices(domains: [String]? = nil) -> [ServiceInfo] {
        let targets = domains ?? allDomains
        var services: [ServiceInfo] = []

        for domain in targets {
            let path = domainPath(domain)
            guard fm.fileExists(atPath: path),
                  let files = try? fm.contentsOfDirectory(atPath: path) else { continue }

            for file in files where file.hasSuffix(".plist") {
                let fullPath = (path as NSString).appendingPathComponent(file)
                guard let data = fm.contents(atPath: fullPath),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = plist["Label"] as? String else { continue }

                var svc = ServiceInfo(label: label, domain: domain, plistPath: fullPath)
                svc.program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                svc.runAtLoad = plist["RunAtLoad"] as? Bool ?? false
                svc.keepAlive = (plist["KeepAlive"] as? Bool) ?? false
                svc.disabled = plist["Disabled"] as? Bool ?? false
                services.append(svc)
            }
        }
        return services
    }

    private func updateStatuses(_ services: inout [ServiceInfo]) {
        let output = shell("/bin/launchctl", ["list"])
        var loaded: [String: (pid: Int?, exitStatus: Int?)] = [:]

        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let pidStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let exitStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)
            loaded[label] = (pid: pidStr == "-" ? nil : Int(pidStr), exitStatus: exitStr == "-" ? nil : Int(exitStr))
        }

        for i in services.indices {
            if let info = loaded[services[i].label] {
                services[i].pid = info.pid
                services[i].exitStatus = info.exitStatus
                services[i].isLoaded = true
            }
        }
    }

    private func findService(_ label: String) -> ServiceInfo? {
        var services = discoverServices()
        updateStatuses(&services)
        return services.first { $0.label == label } ?? services.first { $0.label.localizedCaseInsensitiveContains(label) }
    }

    // MARK: - Shell Execution

    private func shell(_ command: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Tool Implementations

    func list(domain: String, status: String, filter: String?) -> String {
        let domains: [String] = domain == "all" ? allDomains : [domain]
        var services = discoverServices(domains: domains)
        updateStatuses(&services)

        // Filter by status
        switch status {
        case "running": services = services.filter { $0.isRunning }
        case "loaded": services = services.filter { $0.isLoaded && !$0.isRunning }
        case "stopped": services = services.filter { !$0.isLoaded }
        default: break
        }

        // Filter by label
        if let filter = filter, !filter.isEmpty {
            let q = filter.lowercased()
            services = services.filter { $0.label.lowercased().contains(q) }
        }

        services.sort { $0.label < $1.label }

        if services.isEmpty { return "No services found." }

        var lines: [String] = []
        lines.append("LABEL | STATUS | PID | DOMAIN")
        lines.append(String(repeating: "-", count: 80))
        for svc in services {
            let pidStr = svc.pid != nil && svc.pid! > 0 ? "\(svc.pid!)" : "-"
            lines.append("\(svc.label) | \(svc.statusText) | \(pidStr) | \(svc.domain)")
        }
        lines.append("")
        let running = services.filter { $0.isRunning }.count
        let loaded = services.filter { $0.isLoaded && !$0.isRunning }.count
        let stopped = services.count - running - loaded
        lines.append("Total: \(services.count) | Running: \(running) | Loaded: \(loaded) | Stopped: \(stopped)")
        return lines.joined(separator: "\n")
    }

    func status(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }

        var lines: [String] = []
        lines.append("Label: \(svc.label)")
        lines.append("Domain: \(svc.domain)")
        lines.append("Status: \(svc.statusText)")
        if let pid = svc.pid, pid > 0 { lines.append("PID: \(pid)") }
        if let exit = svc.exitStatus { lines.append("Exit Code: \(exit)") }
        lines.append("Loaded: \(svc.isLoaded ? "yes" : "no")")
        lines.append("Enabled: \(svc.disabled ? "no" : "yes")")
        lines.append("Plist: \(svc.plistPath)")
        if let prog = svc.program { lines.append("Executable: \(prog)") }
        lines.append("Run at Load: \(svc.runAtLoad ? "yes" : "no")")
        lines.append("Keep Alive: \(svc.keepAlive ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    func start(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"

        if !svc.isLoaded {
            // Check if disabled in launchd's override database
            let disabledOutput = shell("/bin/launchctl", ["print-disabled", domainTarget(svc.domain)])
            if disabledOutput.contains("\"\(svc.label)\" => disabled") {
                let _ = shell("/bin/launchctl", ["enable", target])
                Thread.sleep(forTimeInterval: 0.2)
            }

            let bootstrapResult = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])

            // Handle "Bootstrap failed: 5: Input/output error" by enabling first
            if bootstrapResult.contains("Input/output error") || bootstrapResult.contains("failed: 5") {
                let _ = shell("/bin/launchctl", ["enable", target])
                Thread.sleep(forTimeInterval: 0.2)
                // Try bootout stale state then bootstrap again
                let _ = shell("/bin/launchctl", ["bootout", target])
                Thread.sleep(forTimeInterval: 0.3)
                let retryResult = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])
                if retryResult.contains("failed") {
                    return "Error: Bootstrap failed after recovery attempt: \(retryResult.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } else if bootstrapResult.contains("failed") && !bootstrapResult.contains("already loaded") {
                return "Error: \(bootstrapResult.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            Thread.sleep(forTimeInterval: 0.3)
        }

        let result = shell("/bin/launchctl", ["kickstart", "-kp", target])
        Thread.sleep(forTimeInterval: 0.5)

        // Verify
        if let updated = findService(svc.label), updated.isRunning {
            return "Started \(svc.label) (PID: \(updated.pid ?? 0))"
        }
        return result.isEmpty ? "Started \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func stop(label: String, force: Bool) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"
        let signal = force ? "SIGKILL" : "SIGTERM"

        let result = shell("/bin/launchctl", ["kill", signal, target])
        Thread.sleep(forTimeInterval: 0.5)

        return result.isEmpty ? "Stopped \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func restart(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"

        if svc.isRunning {
            let _ = shell("/bin/launchctl", ["kill", "SIGTERM", target])
            Thread.sleep(forTimeInterval: 1.0)
        }

        let result = shell("/bin/launchctl", ["kickstart", "-kp", target])
        return result.isEmpty ? "Restarted \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func load(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"

        // Check if disabled in launchd's override database and enable first
        let disabledOutput = shell("/bin/launchctl", ["print-disabled", domainTarget(svc.domain)])
        if disabledOutput.contains("\"\(svc.label)\" => disabled") {
            let _ = shell("/bin/launchctl", ["enable", target])
            Thread.sleep(forTimeInterval: 0.2)
        }

        let result = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])

        // Handle I/O error by clearing stale state
        if result.contains("Input/output error") || result.contains("failed: 5") {
            let _ = shell("/bin/launchctl", ["bootout", target])
            Thread.sleep(forTimeInterval: 0.3)
            let retryResult = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])
            if retryResult.contains("failed") && !retryResult.contains("already loaded") {
                return "Error: \(retryResult.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            return "Loaded \(svc.label) (recovered from stale state)"
        }

        if result.isEmpty || result.contains("already loaded") {
            return "Loaded \(svc.label)"
        }
        return "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func unload(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"
        let result = shell("/bin/launchctl", ["bootout", target])
        return result.isEmpty ? "Unloaded \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func enable(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"
        let result = shell("/bin/launchctl", ["enable", target])
        return result.isEmpty ? "Enabled \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func disable(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"
        let result = shell("/bin/launchctl", ["disable", target])
        return result.isEmpty ? "Disabled \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func logs(label: String, lines: Int) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }

        guard let data = fm.contents(atPath: svc.plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return "Error: Cannot read plist"
        }

        var output: [String] = []
        let stdoutPath = plist["StandardOutPath"] as? String
        let stderrPath = plist["StandardErrorPath"] as? String

        if let path = stdoutPath, fm.fileExists(atPath: path) {
            output.append("=== stdout (\(path)) ===")
            output.append(shell("/usr/bin/tail", ["-n", "\(lines)", path]))
        }

        if let path = stderrPath, fm.fileExists(atPath: path) {
            output.append("=== stderr (\(path)) ===")
            output.append(shell("/usr/bin/tail", ["-n", "\(lines)", path]))
        }

        if output.isEmpty {
            output.append("No log files configured. Set StandardOutPath/StandardErrorPath in the plist.")
        }

        return output.joined(separator: "\n")
    }

    func info(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"
        return shell("/bin/launchctl", ["print", target])
    }

    func create(label: String, program: String, domain: String, arguments: [String],
                runAtLoad: Bool, keepAlive: Bool, startInterval: Int?,
                workingDirectory: String?, stdoutPath: String?, stderrPath: String?,
                environment: [String: String]?) -> String {

        guard label.contains(".") else { return "Error: Label must be reverse-DNS format (e.g. com.company.service)" }
        guard !program.isEmpty else { return "Error: Program path is required" }

        var plist: [String: Any] = ["Label": label]
        var args = [program]
        args.append(contentsOf: arguments)
        plist["ProgramArguments"] = args

        if runAtLoad { plist["RunAtLoad"] = true }
        if keepAlive { plist["KeepAlive"] = true }
        if let interval = startInterval { plist["StartInterval"] = interval }
        if let dir = workingDirectory { plist["WorkingDirectory"] = dir }
        if let out = stdoutPath { plist["StandardOutPath"] = out }
        if let err = stderrPath { plist["StandardErrorPath"] = err }
        if let env = environment, !env.isEmpty { plist["EnvironmentVariables"] = env }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return "Error: Failed to serialize plist"
        }

        let path = domainPath(domain)
        let filePath = (path as NSString).appendingPathComponent("\(label).plist")

        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        fm.createFile(atPath: filePath, contents: data)

        return "Created service at \(filePath)"
    }

    func delete(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }

        if svc.domain == "system-agents" || svc.domain == "system-daemons" {
            return "Error: Cannot delete system-owned services"
        }

        // Unload first
        if svc.isLoaded {
            let target = "\(domainTarget(svc.domain))/\(svc.label)"
            let _ = shell("/bin/launchctl", ["bootout", target])
            Thread.sleep(forTimeInterval: 0.5)
        }

        do {
            try fm.removeItem(atPath: svc.plistPath)
            return "Deleted \(svc.label) (\(svc.plistPath))"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func plistRead(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        guard let data = fm.contents(atPath: svc.plistPath) else { return "Error: Cannot read file" }

        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            return xml
        }
        return String(data: data, encoding: .utf8) ?? "Error: Cannot decode file"
    }

    func plistWrite(label: String, content: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        guard let data = content.data(using: .utf8) else { return "Error: Invalid content encoding" }

        // Validate plist
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else {
            return "Error: Invalid plist XML format"
        }

        if svc.domain == "system-agents" || svc.domain == "system-daemons" {
            return "Error: Cannot write to system-owned services"
        }

        do {
            try data.write(to: URL(fileURLWithPath: svc.plistPath))
            return "Saved \(svc.plistPath)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}


extension ServiceManager {

    /// Force reload a service (bootout stale state, then bootstrap fresh)
    func forceReload(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = "\(domainTarget(svc.domain))/\(svc.label)"

        // Enable first in case it's in the disabled database
        let _ = shell("/bin/launchctl", ["enable", target])

        // Bootout any stale state (ignore errors if not loaded)
        let _ = shell("/bin/launchctl", ["bootout", target])
        Thread.sleep(forTimeInterval: 0.5)

        // Bootstrap fresh
        let result = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])
        Thread.sleep(forTimeInterval: 0.5)

        if result.contains("failed") && !result.contains("already loaded") {
            return "Error: Force reload failed: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        // Verify
        if let updated = findService(svc.label), updated.isLoaded {
            if updated.isRunning {
                return "Force reloaded \(svc.label) (PID: \(updated.pid ?? 0))"
            }
            return "Force reloaded \(svc.label) (loaded, not running)"
        }
        return "Force reloaded \(svc.label)"
    }

    /// Check the launchd disabled overrides database for a domain
    func printDisabled(domain: String) -> String {
        let target = domain == "all" ? domainTarget("user") : domainTarget(domain)
        let output = shell("/bin/launchctl", ["print-disabled", target])

        if output.isEmpty {
            return "No disabled overrides found."
        }

        // Parse and format the output
        var lines: [String] = []
        lines.append("Disabled overrides for domain: \(target)")
        lines.append(String(repeating: "-", count: 60))

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("=>") {
                let parts = trimmed.components(separatedBy: "=>")
                if parts.count == 2 {
                    let label = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    let state = parts[1].trimmingCharacters(in: .whitespaces)
                    lines.append("\(label) => \(state)")
                }
            }
        }

        if lines.count <= 2 {
            return "No disabled overrides found for \(target)."
        }

        return lines.joined(separator: "\n")
    }

    /// Get the true enabled/disabled state from launchd's override database (not just the plist)
    func overrideStatus(label: String) -> String {
        guard let svc = findService(label) else { return "Error: Service not found: \(label)" }
        let target = domainTarget(svc.domain)

        let output = shell("/bin/launchctl", ["print-disabled", target])
        let plistDisabled = svc.disabled

        var launchdDisabled: Bool? = nil
        if output.contains("\"\(svc.label)\" => disabled") {
            launchdDisabled = true
        } else if output.contains("\"\(svc.label)\" => enabled") {
            launchdDisabled = false
        }

        var lines: [String] = []
        lines.append("Service: \(svc.label)")
        lines.append("Plist Disabled key: \(plistDisabled ? "true" : "false")")

        if let override = launchdDisabled {
            lines.append("Launchd override database: \(override ? "disabled" : "enabled")")
            if override && !plistDisabled {
                lines.append("")
                lines.append("⚠️  CONFLICT: Plist says enabled, but launchd override says disabled.")
                lines.append("   The service will NOT load on boot/login.")
                lines.append("   Fix: run `launchctl enable \(target)/\(svc.label)`")
            } else if !override && plistDisabled {
                lines.append("")
                lines.append("ℹ️  Override active: Plist says disabled, but launchd override says enabled.")
                lines.append("   The service WILL load on boot/login despite plist setting.")
            }
        } else {
            lines.append("Launchd override database: no override (using plist value)")
        }

        lines.append("")
        lines.append("Effective state: \((launchdDisabled ?? plistDisabled) ? "DISABLED" : "ENABLED")")
        return lines.joined(separator: "\n")
    }
}


extension ServiceManager {
    /// Open the Launch Manager GUI app
    func openGUI() -> String {
        let appPaths = [
            "/Applications/ZLaunchManager.app",
            NSHomeDirectory() + "/Applications/ZLaunchManager.app",
        ]

        for path in appPaths {
            if fm.fileExists(atPath: path) {
                let result = shell("/usr/bin/open", [path])
                return result.isEmpty ? "Opened Launch Manager GUI" : "Error: \(result)"
            }
        }

        // Try by bundle ID
        let result = shell("/usr/bin/open", ["-b", "com.zavora.zlaunchmanager"])
        if !result.contains("Unable") && !result.contains("error") {
            return "Opened Launch Manager GUI"
        }

        return "ZLaunch Manager.app not found. Install with: zlm gui"
    }
}
