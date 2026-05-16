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
            let _ = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])
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
        let result = shell("/bin/launchctl", ["bootstrap", domainTarget(svc.domain), svc.plistPath])
        return result.isEmpty ? "Loaded \(svc.label)" : "Result: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
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
