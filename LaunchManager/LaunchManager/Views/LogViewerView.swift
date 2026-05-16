import SwiftUI

struct LogViewerView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let service: LaunchdService

    @State private var logContent: String = ""
    @State private var isLoading: Bool = false
    @State private var lineCount: Int = 100
    @State private var autoRefresh: Bool = false
    @State private var refreshTimer: Timer? = nil
    @State private var filterText: String = ""
    @State private var showTimestamps: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                Text("Service Logs")
                    .font(.headline)

                Spacer()

                TextField("Filter", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Picker("Lines", selection: $lineCount) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                }
                .frame(width: 80)

                Toggle(isOn: $autoRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .toggleStyle(.button)
                .help("Auto-refresh every 5 seconds")
                .onChange(of: autoRefresh) { _, newValue in
                    if newValue {
                        startAutoRefresh()
                    } else {
                        stopAutoRefresh()
                    }
                }

                Button {
                    loadLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    copyLogs()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            // Log content
            if isLoading {
                ProgressView("Loading logs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(filteredContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("logBottom")
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .onChange(of: logContent) { _, _ in
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }

            // Status bar
            HStack {
                if let outPath = service.standardOutPath {
                    Label(outPath, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(filteredContent.components(separatedBy: "\n").count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            loadLogs()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private var filteredContent: String {
        guard !filterText.isEmpty else { return logContent }
        let lines = logContent.components(separatedBy: "\n")
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(filterText) }
        return filtered.joined(separator: "\n")
    }

    private func loadLogs() {
        isLoading = true
        Task {
            logContent = await serviceManager.getServiceLogs(service, lines: lineCount)
            isLoading = false
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredContent, forType: .string)
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            loadLogs()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
