import Foundation

/// Represents a single launchd service with all its metadata
@Observable
class LaunchdService: Identifiable, Hashable {
    let id: String
    let label: String
    let domain: ServiceDomain
    let plistPath: String

    var status: ServiceStatus = .unknown
    var pid: Int? = nil
    var lastExitStatus: Int? = nil
    var isLoaded: Bool = false
    var isRunning: Bool { pid != nil && pid != 0 }

    // Plist properties
    var program: String? = nil
    var programArguments: [String]? = nil
    var runAtLoad: Bool = false
    var keepAlive: Bool = false
    var startInterval: Int? = nil
    var standardOutPath: String? = nil
    var standardErrorPath: String? = nil
    var workingDirectory: String? = nil
    var userName: String? = nil
    var groupName: String? = nil
    var environmentVariables: [String: String]? = nil
    var disabled: Bool = false

    init(label: String, domain: ServiceDomain, plistPath: String) {
        self.id = "\(domain.rawValue)/\(label)"
        self.label = label
        self.domain = domain
        self.plistPath = plistPath
    }

    static func == (lhs: LaunchdService, rhs: LaunchdService) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var executablePath: String? {
        program ?? programArguments?.first
    }

    var statusColor: String {
        switch status {
        case .running: return "green"
        case .loaded: return "yellow"
        case .stopped: return "red"
        case .error: return "orange"
        case .unknown: return "gray"
        }
    }
}

enum ServiceStatus: String, Codable {
    case running = "Running"
    case loaded = "Loaded"
    case stopped = "Stopped"
    case error = "Error"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .running: return "circle.fill"
        case .loaded: return "circle.lefthalf.filled"
        case .stopped: return "circle"
        case .error: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .running: return "green"
        case .loaded: return "yellow"
        case .stopped: return "secondary"
        case .error: return "orange"
        case .unknown: return "gray"
        }
    }
}
