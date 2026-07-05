import SwiftUI

struct SidebarView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @Binding var selectedDomain: ServiceDomain?

    var body: some View {
        List(selection: $selectedDomain) {
            Section("Domains") {
                ForEach(ServiceDomain.allCases) { domain in
                    HStack(spacing: 10) {
                        Image(systemName: domain.icon)
                            .foregroundStyle(domain.isSystemOwned ? .orange : .accentColor)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(domain.rawValue)
                                .font(.subheadline)
                            Text("\(serviceCount(for: domain)) services")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        let running = runningCount(for: domain)
                        if running > 0 {
                            Text("\(running)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(domain)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Divider()
                HStack(spacing: 14) {
                    StatPill(label: "Total", value: serviceManager.services.count, color: .primary)
                    StatPill(label: "Running", value: totalRunningCount, color: .green)
                }
                HStack(spacing: 14) {
                    StatPill(label: "Loaded", value: totalLoadedCount, color: .yellow)
                    StatPill(label: "Errors", value: totalErrorCount, color: .orange)
                }

                if let lastRefresh = serviceManager.lastRefresh {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("Launch Manager")
    }

    private func serviceCount(for domain: ServiceDomain) -> Int {
        serviceManager.services(for: domain).count
    }

    private func runningCount(for domain: ServiceDomain) -> Int {
        serviceManager.services(for: domain).filter { $0.status == .running }.count
    }

    private var totalRunningCount: Int {
        serviceManager.services.filter { $0.status == .running }.count
    }

    private var totalLoadedCount: Int {
        serviceManager.services.filter { $0.status == .loaded }.count
    }

    private var totalStoppedCount: Int {
        serviceManager.services.filter { $0.status == .stopped }.count
    }

    private var totalErrorCount: Int {
        serviceManager.services.filter { $0.status == .error }.count
    }
}

struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
