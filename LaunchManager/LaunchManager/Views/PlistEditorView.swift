import SwiftUI

struct PlistEditorView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let service: LaunchdService

    @State private var plistContent: String = ""
    @State private var originalContent: String = ""
    @State private var isSaving: Bool = false
    @State private var saveResult: SaveResult? = nil
    @State private var showSaveConfirmation: Bool = false

    enum SaveResult {
        case success
        case failure(String)
    }

    var hasChanges: Bool {
        plistContent != originalContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar
            HStack {
                Text("Property List Editor")
                    .font(.headline)

                if service.domain.isSystemOwned {
                    Label("Read Only", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if hasChanges {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.1))
                        .clipShape(Capsule())
                }

                Button("Revert") {
                    plistContent = originalContent
                }
                .disabled(!hasChanges)

                Button("Validate") {
                    validatePlist()
                }

                Button("Save") {
                    showSaveConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || service.domain.isSystemOwned)
            }

            // Editor
            TextEditor(text: $plistContent)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .disabled(service.domain.isSystemOwned)

            // Status bar
            HStack {
                if let result = saveResult {
                    switch result {
                    case .success:
                        Label("Saved successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Spacer()

                Text("\(plistContent.components(separatedBy: "\n").count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            loadContent()
        }
        .alert("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                savePlist()
            }
        } message: {
            if service.isLoaded {
                Text("The service is currently loaded. You may need to unload and reload it for changes to take effect.")
            } else {
                Text("Save changes to \(service.label)?")
            }
        }
    }

    private func loadContent() {
        if let content = serviceManager.readPlistContent(service) {
            plistContent = content
            originalContent = content
        } else {
            plistContent = "// Unable to read plist file"
            originalContent = plistContent
        }
    }

    private func validatePlist() {
        guard let data = plistContent.data(using: .utf8) else {
            saveResult = .failure("Invalid encoding")
            return
        }

        do {
            let _ = try PropertyListSerialization.propertyList(from: data, format: nil)
            saveResult = .success
        } catch {
            saveResult = .failure("Invalid plist: \(error.localizedDescription)")
        }
    }

    private func savePlist() {
        isSaving = true
        Task {
            let success = await serviceManager.savePlistContent(service, content: plistContent)
            if success {
                originalContent = plistContent
                saveResult = .success
            } else {
                saveResult = .failure(serviceManager.errorMessage ?? "Unknown error")
            }
            isSaving = false
        }
    }
}
