import SwiftUI

struct ServiceStatusBadge: View {
    let status: ServiceStatus
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small, regular, large

        var iconFont: Font {
            switch self {
            case .small: return .caption2
            case .regular: return .body
            case .large: return .title2
            }
        }

        var frameSize: CGFloat {
            switch self {
            case .small: return 12
            case .regular: return 20
            case .large: return 32
            }
        }
    }

    var body: some View {
        Image(systemName: status.icon)
            .font(size.iconFont)
            .foregroundStyle(statusColor)
            .frame(width: size.frameSize, height: size.frameSize)
            .help(status.rawValue)
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .loaded: return .yellow
        case .stopped: return .secondary
        case .error: return .orange
        case .unknown: return .gray
        }
    }
}
