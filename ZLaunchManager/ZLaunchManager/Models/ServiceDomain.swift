import Foundation

/// Represents the different domains where launchd services can exist
enum ServiceDomain: String, CaseIterable, Identifiable, Codable {
    case userAgents = "User Agents"
    case globalAgents = "Global Agents"
    case globalDaemons = "Global Daemons"
    case systemAgents = "System Agents"
    case systemDaemons = "System Daemons"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .userAgents: return "person.circle"
        case .globalAgents: return "person.2.circle"
        case .globalDaemons: return "gearshape.2"
        case .systemAgents: return "apple.logo"
        case .systemDaemons: return "cpu"
        }
    }

    var path: String {
        switch self {
        case .userAgents:
            return NSHomeDirectory() + "/Library/LaunchAgents"
        case .globalAgents:
            return "/Library/LaunchAgents"
        case .globalDaemons:
            return "/Library/LaunchDaemons"
        case .systemAgents:
            return "/System/Library/LaunchAgents"
        case .systemDaemons:
            return "/System/Library/LaunchDaemons"
        }
    }

    var requiresPrivilege: Bool {
        switch self {
        case .userAgents: return false
        case .globalAgents, .globalDaemons, .systemAgents, .systemDaemons: return true
        }
    }

    var description: String {
        switch self {
        case .userAgents:
            return "Per-user agents loaded when you log in"
        case .globalAgents:
            return "System-wide agents loaded for all users"
        case .globalDaemons:
            return "System-wide daemons running as root"
        case .systemAgents:
            return "Apple system agents (read-only)"
        case .systemDaemons:
            return "Apple system daemons (read-only)"
        }
    }

    var isSystemOwned: Bool {
        switch self {
        case .systemAgents, .systemDaemons: return true
        default: return false
        }
    }

    /// The launchctl domain target for this service domain
    var domainTarget: String {
        switch self {
        case .userAgents, .globalAgents, .systemAgents:
            let uid = getuid()
            return "gui/\(uid)"
        case .globalDaemons, .systemDaemons:
            return "system"
        }
    }
}
