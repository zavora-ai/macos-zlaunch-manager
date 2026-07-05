import SwiftUI

struct ServiceDetailView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let service: LaunchdService
    var onDelete: (() -> Void)? = nil

    @State private var selectedTab: DetailTab = .overview
    @State private var serviceInfo: String = ""
    @State private var isPerformingAction: Bool = false
    @State private var actionResult: String? = nil
    @State private var showDeleteConfirmation: Bool = false

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case plist = "Plist Editor"
        case logs = "Logs"
        case info = "Raw Info"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            serviceHeader

            Divider()

            // Tab content
            TabView(selection: $selectedTab) {
                overviewTab
                    .tabItem { Label("Overview", systemImage: "info.circle") }
                    .tag(DetailTab.overview)

                PlistEditorView(service: service)
                    .tabItem { Label("Plist", systemImage: "doc.text") }
                    .tag(DetailTab.plist)

                LogViewerView(service: service)
                    .tabItem { Label("Logs", systemImage: "text.alignleft") }
                    .tag(DetailTab.logs)

                rawInfoTab
                    .tabItem { Label("Info", systemImage: "terminal") }
                    .tag(DetailTab.info)
            }
            .padding()
        }
        .alert("Delete Service", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await serviceManager.deleteService(service)
                    onDelete?()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(service.label)\"? This will unload the service and remove its plist file. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var serviceHeader: some View {
        HStack(spacing: 16) {
            ServiceStatusBadge(status: service.status, size: .large)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.label)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Label(service.domain.rawValue, systemImage: service.domain.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pid = service.pid, pid > 0 {
                        Label("PID \(pid)", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let exit = service.lastExitStatus {
                        Label("Exit \(exit)", systemImage: exit == 0 ? "checkmark.circle" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(exit == 0 ? .green : .orange)
                    }
                }
            }

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding()
        .background(.bar)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
            }

            if service.isRunning {
                Button {
                    performAction {
                        let _ = await serviceManager.stopService(service)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    performAction {
                        let _ = await serviceManager.stopService(service)
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        let _ = await serviceManager.startService(service)
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    performAction {
                        let _ = await serviceManager.startService(service)
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Menu {
                if service.isLoaded {
                    Button("Unload") {
                        performAction { let _ = await serviceManager.unloadService(service) }
                    }
                } else {
                    Button("Load") {
                        performAction { let _ = await serviceManager.loadService(service) }
                    }
                }

                Divider()

                if service.disabled {
                    Button("Enable") {
                        performAction { let _ = await serviceManager.enableService(service) }
                    }
                } else {
                    Button("Disable") {
                        performAction { let _ = await serviceManager.disableService(service) }
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

                Button("Copy Plist Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.plistPath, forType: .string)
                }

                if !service.domain.isSystemOwned {
                    Divider()
                    Button("Delete Service", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .disabled(service.domain.isSystemOwned && !service.isLoaded)
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status section
                GroupBox("Status") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatusCard(title: "State", value: service.status.rawValue, icon: service.status.icon)
                        StatusCard(title: "Loaded", value: service.isLoaded ? "Yes" : "No", icon: service.isLoaded ? "checkmark.circle" : "xmark.circle")
                        StatusCard(title: "Enabled", value: service.disabled ? "No" : "Yes", icon: service.disabled ? "xmark.circle" : "checkmark.circle")
                    }
                    .padding(.vertical, 8)
                }

                // Configuration section
                GroupBox("Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Label", value: service.label)
                        DetailRow(label: "Domain", value: service.domain.rawValue)
                        DetailRow(label: "Plist Path", value: service.plistPath)

                        if let program = service.executablePath {
                            DetailRow(label: "Executable", value: program)
                        }

                        if let args = service.programArguments, args.count > 1 {
                            DetailRow(label: "Arguments", value: args.dropFirst().joined(separator: " "))
                        }

                        if let dir = service.workingDirectory {
                            DetailRow(label: "Working Dir", value: dir)
                        }

                        DetailRow(label: "Run at Load", value: service.runAtLoad ? "Yes" : "No")
                        DetailRow(label: "Keep Alive", value: service.keepAlive ? "Yes" : "No")

                        if let interval = service.startInterval {
                            DetailRow(label: "Start Interval", value: "\(interval)s")
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Logging section
                if service.standardOutPath != nil || service.standardErrorPath != nil {
                    GroupBox("Log Paths") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let outPath = service.standardOutPath {
                                DetailRow(label: "Stdout", value: outPath)
                            }
                            if let errPath = service.standardErrorPath {
                                DetailRow(label: "Stderr", value: errPath)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Environment section
                if let env = service.environmentVariables, !env.isEmpty {
                    GroupBox("Environment Variables") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(env.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                DetailRow(label: key, value: value)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Raw Info Tab

    private var rawInfoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("launchctl print output")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { serviceInfo = await serviceManager.getServiceInfo(service) }
                }
            }

            ScrollView {
                Text(serviceInfo.isEmpty ? "Loading..." : serviceInfo)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .task {
            serviceInfo = await serviceManager.getServiceInfo(service)
        }
    }

    // MARK: - Helpers

    private func performAction(_ action: @escaping () async -> Void) {
        isPerformingAction = true
        actionResult = nil
        Task {
            await action()
            isPerformingAction = false
        }
    }
}

// MARK: - Supporting Views

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
