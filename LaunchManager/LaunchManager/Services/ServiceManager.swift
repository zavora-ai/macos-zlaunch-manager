import Foundation
import AppKit

/// Core service manager that interfaces with launchctl to manage launchd services
@Observable
class ServiceManager {
    var services: [LaunchdService] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var lastRefresh: Date? = nil

    private let fileManager = FileManager.default

    // MARK: - Loading Services

    /// Load all services from all domains
    func loadAllServices() async {
        isLoading = true
        errorMessage = nil

        var allServices: [LaunchdService] = []

        for domain in ServiceDomain.allCases {
            let domainServices = await loadServices(for: domain)
            allServices.append(contentsOf: domainServices)
        }

        // Update status for all services
        await updateServiceStatuses(for: allServices)

        services = allServices
        lastRefresh = Date()
        isLoading = false
    }

    /// Load services for a specific domain
    func loadServices(for domain: ServiceDomain) async -> [LaunchdService] {
        let path = domain.path
        var domainServices: [LaunchdService] = []

        guard fileManager.fileExists(atPath: path) else { return [] }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: path)
            let plistFiles = files.filter { $0.hasSuffix(".plist") }

            for file in plistFiles {
                let fullPath = (path as NSString).appendingPathComponent(file)
                if let service = parsePlist(at: fullPath, domain: domain) {
                    domainServices.append(service)
                }
            }
        } catch {
            print("Error loading services from \(path): \(error)")
        }

        return domainServices
    }

    /// Parse a plist file into a LaunchdService
    private func parsePlist(at path: String, domain: ServiceDomain) -> LaunchdService? {
        guard let data = fileManager.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else {
            return nil
        }

        let service = LaunchdService(label: label, domain: domain, plistPath: path)

        service.program = plist["Program"] as? String
        service.programArguments = plist["ProgramArguments"] as? [String]
        service.runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        service.standardOutPath = plist["StandardOutPath"] as? String
        service.standardErrorPath = plist["StandardErrorPath"] as? String
        service.workingDirectory = plist["WorkingDirectory"] as? String
        service.userName = plist["UserName"] as? String
        service.groupName = plist["GroupName"] as? String
        service.environmentVariables = plist["EnvironmentVariables"] as? [String: String]
        service.startInterval = plist["StartInterval"] as? Int
        service.disabled = plist["Disabled"] as? Bool ?? false

        // Handle KeepAlive - can be bool or dict
        if let keepAlive = plist["KeepAlive"] as? Bool {
            service.keepAlive = keepAlive
        } else if plist["KeepAlive"] != nil {
            service.keepAlive = true
        }

        return service
    }

    // MARK: - Status Updates

    /// Update the status of all services using launchctl list
    func updateServiceStatuses(for services: [LaunchdService]) async {
        // Get the list output from launchctl
        let userListOutput = await runCommand("/bin/launchctl", arguments: ["list"])
        let userLines = parseListOutput(userListOutput)

        for service in services {
            if let info = userLines[service.label] {
                service.pid = info.pid
                service.lastExitStatus = info.exitStatus
                service.isLoaded = true

                if let pid = info.pid, pid > 0 {
                    service.status = .running
                } else if info.exitStatus != nil && info.exitStatus != 0 {
                    service.status = .error
                } else {
                    service.status = .loaded
                }
            } else {
                service.isLoaded = false
                service.status = .stopped
            }
        }
    }

    /// Parse launchctl list output into a dictionary
    private func parseListOutput(_ output: String) -> [String: (pid: Int?, exitStatus: Int?)] {
        var result: [String: (pid: Int?, exitStatus: Int?)] = [:]

        let lines = output.components(separatedBy: "\n")
        for line in lines.dropFirst() { // Skip header
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let pidStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let exitStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)

            let pid = pidStr == "-" ? nil : Int(pidStr)
            let exitStatus = exitStr == "-" ? nil : Int(exitStr)

            result[label] = (pid: pid, exitStatus: exitStatus)
        }

        return result
    }

    // MARK: - Service Actions

    /// Start a service
    func startService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        // If not loaded, load it first
        if !service.isLoaded {
            let loadResult: String
            if service.domain.requiresPrivilege {
                loadResult = await runPrivilegedCommand("/bin/launchctl", arguments: ["bootstrap", domainTarget, service.plistPath])
            } else {
                loadResult = await runCommand("/bin/launchctl", arguments: ["bootstrap", domainTarget, service.plistPath])
            }
            print("[LaunchManager] bootstrap: \(loadResult)")
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        // Now kickstart it
        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["kickstart", "-kp", serviceTarget])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["kickstart", "-kp", serviceTarget])
        }
        print("[LaunchManager] kickstart: \(result)")

        try? await Task.sleep(nanoseconds: 500_000_000)
        await refreshService(service)
        return !result.lowercased().contains("error") && !result.contains("Could not")
    }

    /// Stop a service
    func stopService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        // Try kill first
        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["kill", "SIGTERM", serviceTarget])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["kill", "SIGTERM", serviceTarget])
        }
        print("[LaunchManager] kill SIGTERM: \(result)")

        // Give it a moment to stop
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await refreshService(service)

        // If still running, try SIGKILL
        if service.isRunning {
            let killResult: String
            if service.domain.requiresPrivilege {
                killResult = await runPrivilegedCommand("/bin/launchctl", arguments: ["kill", "SIGKILL", serviceTarget])
            } else {
                killResult = await runCommand("/bin/launchctl", arguments: ["kill", "SIGKILL", serviceTarget])
            }
            print("[LaunchManager] kill SIGKILL: \(killResult)")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshService(service)
        }

        return !service.isRunning
    }

    /// Load (bootstrap) a service
    func loadService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget

        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["bootstrap", domainTarget, service.plistPath])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["bootstrap", domainTarget, service.plistPath])
        }
        print("[LaunchManager] bootstrap: \(result)")

        try? await Task.sleep(nanoseconds: 500_000_000)
        await refreshService(service)
        return service.isLoaded
    }

    /// Unload (bootout) a service
    func unloadService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["bootout", serviceTarget])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["bootout", serviceTarget])
        }
        print("[LaunchManager] bootout: \(result)")

        try? await Task.sleep(nanoseconds: 500_000_000)
        await refreshService(service)
        return !service.isLoaded
    }

    /// Enable a service (mark it to load on boot/login)
    func enableService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["enable", serviceTarget])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["enable", serviceTarget])
        }
        print("[LaunchManager] enable: \(result)")

        service.disabled = false
        return true
    }

    /// Disable a service (prevent it from loading on boot/login)
    func disableService(_ service: LaunchdService) async -> Bool {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        let result: String
        if service.domain.requiresPrivilege {
            result = await runPrivilegedCommand("/bin/launchctl", arguments: ["disable", serviceTarget])
        } else {
            result = await runCommand("/bin/launchctl", arguments: ["disable", serviceTarget])
        }
        print("[LaunchManager] disable: \(result)")

        service.disabled = true
        return true
    }

    /// Refresh a single service's status
    func refreshService(_ service: LaunchdService) async {
        await updateServiceStatuses(for: [service])
    }

    // MARK: - Service Info

    /// Get detailed info about a service using launchctl print
    func getServiceInfo(_ service: LaunchdService) async -> String {
        let domainTarget = service.domain.domainTarget
        let serviceTarget = "\(domainTarget)/\(service.label)"

        let output = await runCommand("/bin/launchctl", arguments: ["print", serviceTarget])
        return output
    }

    // MARK: - Plist Management

    /// Read the raw plist content as a string
    func readPlistContent(_ service: LaunchdService) -> String? {
        guard let data = fileManager.contents(atPath: service.plistPath) else { return nil }

        // Try to convert binary plist to XML for display
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            return String(data: xmlData, encoding: .utf8)
        }

        return String(data: data, encoding: .utf8)
    }

    /// Save plist content
    func savePlistContent(_ service: LaunchdService, content: String) async -> Bool {
        guard let data = content.data(using: .utf8) else { return false }

        // Validate it's valid plist
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else {
            errorMessage = "Invalid plist format"
            return false
        }

        if service.domain.requiresPrivilege {
            // Write to temp file then move with privileges
            let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".plist"
            fileManager.createFile(atPath: tempPath, contents: data)
            let _ = await runPrivilegedCommand("/bin/cp", arguments: [tempPath, service.plistPath])
            try? fileManager.removeItem(atPath: tempPath)
        } else {
            do {
                try data.write(to: URL(fileURLWithPath: service.plistPath))
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                return false
            }
        }

        return true
    }

    /// Create a new service plist
    func createService(label: String, domain: ServiceDomain, program: String,
                       arguments: [String], runAtLoad: Bool, keepAlive: Bool,
                       startInterval: Int?, workingDirectory: String?,
                       standardOutPath: String?, standardErrorPath: String?,
                       environmentVariables: [String: String]?) async -> Bool {

        var plist: [String: Any] = [
            "Label": label,
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive
        ]

        if !program.isEmpty {
            var args = [program]
            args.append(contentsOf: arguments.filter { !$0.isEmpty })
            plist["ProgramArguments"] = args
        }

        if let interval = startInterval, interval > 0 {
            plist["StartInterval"] = interval
        }

        if let dir = workingDirectory, !dir.isEmpty {
            plist["WorkingDirectory"] = dir
        }

        if let outPath = standardOutPath, !outPath.isEmpty {
            plist["StandardOutPath"] = outPath
        }

        if let errPath = standardErrorPath, !errPath.isEmpty {
            plist["StandardErrorPath"] = errPath
        }

        if let env = environmentVariables, !env.isEmpty {
            plist["EnvironmentVariables"] = env
        }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            errorMessage = "Failed to serialize plist"
            return false
        }

        let fileName = "\(label).plist"
        let filePath = (domain.path as NSString).appendingPathComponent(fileName)

        if domain.requiresPrivilege {
            let tempPath = NSTemporaryDirectory() + fileName
            fileManager.createFile(atPath: tempPath, contents: data)
            let _ = await runPrivilegedCommand("/bin/cp", arguments: [tempPath, filePath])
            try? fileManager.removeItem(atPath: tempPath)
        } else {
            // Ensure directory exists
            try? fileManager.createDirectory(atPath: domain.path, withIntermediateDirectories: true)
            fileManager.createFile(atPath: filePath, contents: data)
        }

        // Reload services
        await loadAllServices()
        return true
    }

    /// Delete a service (unload first, then remove plist)
    func deleteService(_ service: LaunchdService) async -> Bool {
        // Unload first if loaded
        if service.isLoaded {
            let _ = await unloadService(service)
        }

        if service.domain.requiresPrivilege {
            let _ = await runPrivilegedCommand("/bin/rm", arguments: [service.plistPath])
        } else {
            do {
                try fileManager.removeItem(atPath: service.plistPath)
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
                return false
            }
        }

        await loadAllServices()
        return true
    }

    // MARK: - Log Reading

    /// Get logs for a service from its configured log paths or system log
    func getServiceLogs(_ service: LaunchdService, lines: Int = 100) async -> String {
        var logs = ""

        // Try stdout log
        if let outPath = service.standardOutPath, fileManager.fileExists(atPath: outPath) {
            let output = await runCommand("/usr/bin/tail", arguments: ["-n", "\(lines)", outPath])
            if !output.isEmpty {
                logs += "=== Standard Output (\(outPath)) ===\n\(output)\n\n"
            }
        }

        // Try stderr log
        if let errPath = service.standardErrorPath, fileManager.fileExists(atPath: errPath) {
            let output = await runCommand("/usr/bin/tail", arguments: ["-n", "\(lines)", errPath])
            if !output.isEmpty {
                logs += "=== Standard Error (\(errPath)) ===\n\(output)\n\n"
            }
        }

        // Also check system log
        let syslogOutput = await runCommand("/usr/bin/log", arguments: [
            "show", "--predicate", "subsystem == '\(service.label)' OR senderImagePath CONTAINS '\(service.label)'",
            "--last", "1h", "--style", "compact"
        ])

        if !syslogOutput.isEmpty && !syslogOutput.contains("No log messages") {
            logs += "=== System Log ===\n\(syslogOutput)\n"
        }

        if logs.isEmpty {
            logs = "No logs found for this service.\n\nTip: Configure StandardOutPath and StandardErrorPath in the plist to capture output."
        }

        return logs
    }

    // MARK: - Command Execution

    /// Run a command and return its output
    @discardableResult
    func runCommand(_ command: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(returning: "Error: \(error.localizedDescription)")
            }
        }
    }

    /// Run a command with elevated privileges using Authorization Services
    @discardableResult
    func runPrivilegedCommand(_ command: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            PrivilegedHelper.shared.runWithPrivileges(command: command, arguments: arguments) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Filtering

    /// Get services filtered by domain
    func services(for domain: ServiceDomain) -> [LaunchdService] {
        services.filter { $0.domain == domain }
    }

    /// Search services by label
    func searchServices(query: String) -> [LaunchdService] {
        guard !query.isEmpty else { return services }
        let lowercased = query.lowercased()
        return services.filter {
            $0.label.lowercased().contains(lowercased) ||
            $0.executablePath?.lowercased().contains(lowercased) == true
        }
    }
}
