import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Int = 30
    @AppStorage("showSystemServices") private var showSystemServices: Bool = true
    @AppStorage("confirmDestructiveActions") private var confirmDestructiveActions: Bool = true
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra: Bool = false
    @AppStorage("defaultDomain") private var defaultDomain: String = ServiceDomain.userAgents.rawValue

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            displaySettings
                .tabItem {
                    Label("Display", systemImage: "eye")
                }

            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 450, height: 300)
    }

    private var generalSettings: some View {
        Form {
            Section("Refresh") {
                Picker("Auto-refresh interval", selection: $refreshInterval) {
                    Text("Never").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
            }

            Section("Default View") {
                Picker("Default domain", selection: $defaultDomain) {
                    ForEach(ServiceDomain.allCases) { domain in
                        Text(domain.rawValue).tag(domain.rawValue)
                    }
                }
            }

            Section("Safety") {
                Toggle("Confirm destructive actions", isOn: $confirmDestructiveActions)
                    .help("Show confirmation dialogs before stopping, unloading, or deleting services")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var displaySettings: some View {
        Form {
            Section("Visibility") {
                Toggle("Show system services", isOn: $showSystemServices)
                    .help("Show Apple system agents and daemons (read-only)")
            }

            Section("Menu Bar") {
                Toggle("Show menu bar extra", isOn: $showMenuBarExtra)
                    .help("Show a quick-access icon in the menu bar")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var advancedSettings: some View {
        Form {
            Section("Paths") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ServiceDomain.allCases) { domain in
                        HStack {
                            Text(domain.rawValue)
                                .frame(width: 140, alignment: .trailing)
                            Text(domain.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("macOS")
                    Spacer()
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
