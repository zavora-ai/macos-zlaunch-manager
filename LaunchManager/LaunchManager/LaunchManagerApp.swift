import SwiftUI

@main
struct LaunchManagerApp: App {
    @State private var serviceManager = ServiceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serviceManager)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1300, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Services") {
                Button("Refresh All") {
                    Task { await serviceManager.loadAllServices() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Start Selected") {}
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Stop Selected") {}
                    .keyboardShortcut("x", modifiers: [.command, .shift])

                Divider()

                Button("Load Selected") {}
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Unload Selected") {}
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
