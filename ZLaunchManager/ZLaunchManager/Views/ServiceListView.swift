import SwiftUI

struct ServiceListView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let selectedDomain: ServiceDomain
    @Binding var selectedService: LaunchdService?
    @Binding var searchText: String

    @State private var sortOrder: SortOrder = .name
    @State private var showOnlyRunning: Bool = false
    @State private var showOnlyLoaded: Bool = false

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case status = "Status"
        case domain = "Domain"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                // Running filter - circular icon
                Button {
                    showOnlyRunning.toggle()
                    if showOnlyRunning { showOnlyLoaded = false }
                } label: {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .padding(6)
                        .background(showOnlyRunning ? Color.green.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(showOnlyRunning ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Show only running services")

                // Loaded filter - circular icon
                Button {
                    showOnlyLoaded.toggle()
                    if showOnlyLoaded { showOnlyRunning = false }
                } label: {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 10, height: 10)
                        .padding(6)
                        .background(showOnlyLoaded ? Color.yellow.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(showOnlyLoaded ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Show only loaded services")

                Text("\(filteredServices.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Service list
            List(selection: $selectedService) {
                ForEach(filteredServices) { service in
                    ServiceRowView(service: service)
                        .tag(service)
                        .contextMenu {
                            ServiceContextMenu(service: service, onDelete: {
                                selectedService = nil
                            })
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationTitle(selectedDomain.rawValue)
        .navigationSubtitle(selectedDomain.description)
    }

    private var filteredServices: [LaunchdService] {
        var result = serviceManager.services(for: selectedDomain)

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.label.lowercased().contains(query) ||
                $0.executablePath?.lowercased().contains(query) == true
            }
        }

        // Apply filters
        if showOnlyRunning {
            result = result.filter { $0.status == .running }
        }
        if showOnlyLoaded {
            result = result.filter { $0.isLoaded }
        }

        // Apply sort
        switch sortOrder {
        case .name:
            result.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .status:
            result.sort { statusPriority($0.status) < statusPriority($1.status) }
        case .domain:
            result.sort { $0.domain.rawValue < $1.domain.rawValue }
        }

        return result
    }

    private func statusPriority(_ status: ServiceStatus) -> Int {
        switch status {
        case .running: return 0
        case .error: return 1
        case .loaded: return 2
        case .stopped: return 3
        case .unknown: return 4
        }
    }
}

// MARK: - Service Row

struct ServiceRowView: View {
    let service: LaunchdService

    var body: some View {
        HStack(spacing: 10) {
            ServiceStatusBadge(status: service.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let path = service.executablePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if let pid = service.pid, pid > 0 {
                Text("\(pid)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if service.domain.isSystemOwned {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("System-owned (read-only)")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Context Menu

struct ServiceContextMenu: View {
    @Environment(ServiceManager.self) private var serviceManager
    let service: LaunchdService
    var onDelete: (() -> Void)? = nil

    var body: some View {
        if service.isRunning {
            Button("Stop") {
                Task { await serviceManager.stopService(service) }
            }
        } else {
            Button("Start") {
                Task { await serviceManager.startService(service) }
            }
        }

        Divider()

        if service.isLoaded {
            Button("Unload") {
                Task { await serviceManager.unloadService(service) }
            }
        } else {
            Button("Load") {
                Task { await serviceManager.loadService(service) }
            }
        }

        Divider()

        if service.disabled {
            Button("Enable") {
                Task { await serviceManager.enableService(service) }
            }
        } else {
            Button("Disable") {
                Task { await serviceManager.disableService(service) }
            }
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(service.plistPath, inFileViewerRootedAtPath: "")
        }

        Button("Copy Label") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(service.label, forType: .string)
        }

        if !service.domain.isSystemOwned {
            Divider()
            Button("Delete", role: .destructive) {
                Task {
                    await serviceManager.deleteService(service)
                    onDelete?()
                }
            }
        }
    }
}
