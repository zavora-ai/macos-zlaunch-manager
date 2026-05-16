import SwiftUI

struct CreateServiceView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""
    @State private var domain: ServiceDomain = .userAgents
    @State private var program: String = ""
    @State private var arguments: String = ""
    @State private var runAtLoad: Bool = true
    @State private var keepAlive: Bool = false
    @State private var startInterval: String = ""
    @State private var workingDirectory: String = ""
    @State private var standardOutPath: String = ""
    @State private var standardErrorPath: String = ""
    @State private var environmentVariables: [(key: String, value: String)] = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedTemplate: ServiceTemplate = .custom

    enum ServiceTemplate: String, CaseIterable {
        case custom = "Custom"
        case simpleAgent = "Simple Agent"
        case periodicTask = "Periodic Task"
        case daemon = "Background Daemon"
        case webServer = "Web Server"

        var description: String {
            switch self {
            case .custom: return "Start from scratch"
            case .simpleAgent: return "A basic user agent that runs at login"
            case .periodicTask: return "A task that runs at regular intervals"
            case .daemon: return "A background daemon with keep-alive"
            case .webServer: return "A web server with logging configured"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Service")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            Form {
                // Template picker
                Section("Template") {
                    Picker("Start from", selection: $selectedTemplate) {
                        ForEach(ServiceTemplate.allCases, id: \.self) { template in
                            VStack(alignment: .leading) {
                                Text(template.rawValue)
                            }
                            .tag(template)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: selectedTemplate) { _, template in
                        applyTemplate(template)
                    }
                }

                // Basic info
                Section("Basic Configuration") {
                    TextField("Service Label (e.g., com.mycompany.myservice)", text: $label)
                        .textFieldStyle(.roundedBorder)

                    Picker("Domain", selection: $domain) {
                        ForEach(ServiceDomain.allCases.filter { !$0.isSystemOwned }) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }

                    HStack {
                        TextField("Program Path", text: $program)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            browseForProgram()
                        }
                    }

                    TextField("Arguments (space-separated)", text: $arguments)
                        .textFieldStyle(.roundedBorder)
                }

                // Behavior
                Section("Behavior") {
                    Toggle("Run at Load", isOn: $runAtLoad)
                    Toggle("Keep Alive", isOn: $keepAlive)

                    HStack {
                        TextField("Start Interval (seconds)", text: $startInterval)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Text("Leave empty for no interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Paths
                Section("Paths") {
                    HStack {
                        TextField("Working Directory", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForDirectory(binding: $workingDirectory)
                        }
                    }

                    TextField("Standard Output Log Path", text: $standardOutPath)
                        .textFieldStyle(.roundedBorder)

                    TextField("Standard Error Log Path", text: $standardErrorPath)
                        .textFieldStyle(.roundedBorder)
                }

                // Environment variables
                Section("Environment Variables") {
                    ForEach(environmentVariables.indices, id: \.self) { index in
                        HStack {
                            TextField("Key", text: Binding(
                                get: { environmentVariables[index].key },
                                set: { environmentVariables[index].key = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Value", text: Binding(
                                get: { environmentVariables[index].value },
                                set: { environmentVariables[index].value = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button {
                                environmentVariables.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Add Variable") {
                        environmentVariables.append((key: "", value: ""))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create Service") {
                    createService()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty || program.isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 650, height: 700)
    }

    private func applyTemplate(_ template: ServiceTemplate) {
        switch template {
        case .custom:
            break
        case .simpleAgent:
            runAtLoad = true
            keepAlive = false
            startInterval = ""
            domain = .userAgents
        case .periodicTask:
            runAtLoad = false
            keepAlive = false
            startInterval = "3600"
            domain = .userAgents
        case .daemon:
            runAtLoad = true
            keepAlive = true
            startInterval = ""
            domain = .globalDaemons
        case .webServer:
            runAtLoad = true
            keepAlive = true
            startInterval = ""
            standardOutPath = "/tmp/\(label.isEmpty ? "myservice" : label).stdout.log"
            standardErrorPath = "/tmp/\(label.isEmpty ? "myservice" : label).stderr.log"
            domain = .userAgents
        }
    }

    private func browseForProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Program"

        if panel.runModal() == .OK, let url = panel.url {
            program = url.path
        }
    }

    private func browseForDirectory(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Directory"

        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }

    private func createService() {
        guard !label.isEmpty, !program.isEmpty else {
            errorMessage = "Label and program are required"
            return
        }

        // Validate label format
        guard label.contains(".") else {
            errorMessage = "Label should use reverse-DNS format (e.g., com.company.service)"
            return
        }

        isCreating = true
        errorMessage = nil

        let args = arguments.split(separator: " ").map(String.init)
        let interval = Int(startInterval)
        let envVars = environmentVariables.isEmpty ? nil :
            Dictionary(uniqueKeysWithValues: environmentVariables.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        Task {
            let success = await serviceManager.createService(
                label: label,
                domain: domain,
                program: program,
                arguments: args,
                runAtLoad: runAtLoad,
                keepAlive: keepAlive,
                startInterval: interval,
                workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
                standardOutPath: standardOutPath.isEmpty ? nil : standardOutPath,
                standardErrorPath: standardErrorPath.isEmpty ? nil : standardErrorPath,
                environmentVariables: envVars
            )

            isCreating = false

            if success {
                dismiss()
            } else {
                errorMessage = serviceManager.errorMessage ?? "Failed to create service"
            }
        }
    }
}
