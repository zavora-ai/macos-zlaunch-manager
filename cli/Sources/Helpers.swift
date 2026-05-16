import Foundation
import ArgumentParser

// MARK: - Domain

enum Domain: String, CaseIterable, ExpressibleByArgument {
    case user = "user"
    case globalAgents = "global-agents"
    case globalDaemons = "global-daemons"
    case systemAgents = "system-agents"
    case systemDaemons = "system-daemons"
    case all = "all"

    var path: String {
        switch self {
        case .user: return NSHomeDirectory() + "/Library/LaunchAgents"
        case .globalAgents: return "/Library/LaunchAgents"
        case .globalDaemons: return "/Library/LaunchDaemons"
        case .systemAgents: return "/System/Library/LaunchAgents"
        case .systemDaemons: return "/System/Library/LaunchDaemons"
        case .all: return ""
        }
    }

    var displayName: String {
        switch self {
        case .user: return "User Agents"
        case .globalAgents: return "Global Agents"
        case .globalDaemons: return "Global Daemons"
        case .systemAgents: return "System Agents"
        case .systemDaemons: return "System Daemons"
        case .all: return "All"
        }
    }

    var domainTarget: String {
        switch self {
        case .user, .globalAgents, .systemAgents:
            return "gui/\(getuid())"
        case .globalDaemons, .systemDaemons:
            return "system"
        case .all:
            return "gui/\(getuid())"
        }
    }

    var requiresPrivilege: Bool {
        switch self {
        case .user: return false
        default: return true
        }
    }

    static var scannable: [Domain] {
        [.user, .globalAgents, .globalDaemons, .systemAgents, .systemDaemons]
    }
}

// MARK: - Service Info

struct ServiceInfo {
    let label: String
    let domain: Domain
    let plistPath: String
    var pid: Int?
    var exitStatus: Int?
    var isLoaded: Bool = false
    var program: String?
    var runAtLoad: Bool = false
    var keepAlive: Bool = false
    var disabled: Bool = false

    var isRunning: Bool { pid != nil && pid! > 0 }

    var statusSymbol: String {
        if isRunning { return "●" }
        if isLoaded { return "◐" }
        return "○"
    }

    var statusColor: ANSIColor {
        if isRunning { return .green }
        if isLoaded && exitStatus != nil && exitStatus != 0 { return .yellow }
        if isLoaded { return .blue }
        return .gray
    }

    var statusText: String {
        if isRunning { return "running" }
        if isLoaded && exitStatus != nil && exitStatus != 0 { return "error(\(exitStatus!))" }
        if isLoaded { return "loaded" }
        return "stopped"
    }
}

// MARK: - Shell Execution

@discardableResult
func shell(_ command: String, _ arguments: [String]) -> (output: String, exitCode: Int32) {
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
        return ("Error: \(error.localizedDescription)", 1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, process.terminationStatus)
}

func shellPrivileged(_ command: String, _ arguments: [String]) -> (output: String, exitCode: Int32) {
    let args = arguments.map { $0.replacingOccurrences(of: "\"", with: "\\\"") }
    let argString = args.map { "\"\($0)\"" }.joined(separator: " ")
    let script = "do shell script \"\(command) \(argString)\" with administrator privileges"

    let appleScript = Process()
    let pipe = Pipe()
    appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    appleScript.arguments = ["-e", script]
    appleScript.standardOutput = pipe
    appleScript.standardError = pipe

    do {
        try appleScript.run()
        appleScript.waitUntilExit()
    } catch {
        return ("Error: \(error.localizedDescription)", 1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, appleScript.terminationStatus)
}

// MARK: - Service Discovery

func discoverServices(in domain: Domain) -> [ServiceInfo] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: domain.path) else { return [] }

    guard let files = try? fm.contentsOfDirectory(atPath: domain.path) else { return [] }

    return files.filter { $0.hasSuffix(".plist") }.compactMap { file in
        let path = (domain.path as NSString).appendingPathComponent(file)
        guard let data = fm.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }

        var info = ServiceInfo(label: label, domain: domain, plistPath: path)
        info.program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        info.runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        info.keepAlive = plist["KeepAlive"] as? Bool ?? false
        info.disabled = plist["Disabled"] as? Bool ?? false
        return info
    }
}

func discoverAllServices(domains: [Domain]? = nil) -> [ServiceInfo] {
    let targets = domains ?? Domain.scannable
    var services: [ServiceInfo] = []
    for domain in targets {
        services.append(contentsOf: discoverServices(in: domain))
    }
    return services
}

func updateStatuses(_ services: inout [ServiceInfo]) {
    let (output, _) = shell("/bin/launchctl", ["list"])
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

func findService(label: String) -> ServiceInfo? {
    var all = discoverAllServices()
    updateStatuses(&all)
    return all.first { $0.label.localizedCaseInsensitiveContains(label) || $0.label == label }
}

func findServiceExact(label: String) -> ServiceInfo? {
    var all = discoverAllServices()
    updateStatuses(&all)
    return all.first { $0.label == label }
}

// MARK: - ANSI Colors

enum ANSIColor: String {
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case gray = "\u{001B}[90m"
    case white = "\u{001B}[37m"
    case bold = "\u{001B}[1m"
    case reset = "\u{001B}[0m"
}

func colored(_ text: String, _ color: ANSIColor) -> String {
    "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
}

func bold(_ text: String) -> String {
    "\(ANSIColor.bold.rawValue)\(text)\(ANSIColor.reset.rawValue)"
}
