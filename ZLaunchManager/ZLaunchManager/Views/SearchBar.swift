import SwiftUI

/// A reusable search/filter bar component
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Quick filter chips for common service filters
struct FilterChipsView: View {
    @Binding var showRunning: Bool
    @Binding var showLoaded: Bool
    @Binding var showStopped: Bool

    var body: some View {
        HStack(spacing: 8) {
            FilterChip(label: "Running", isActive: $showRunning, color: .green)
            FilterChip(label: "Loaded", isActive: $showLoaded, color: .yellow)
            FilterChip(label: "Stopped", isActive: $showStopped, color: .secondary)
        }
    }
}

struct FilterChip: View {
    let label: String
    @Binding var isActive: Bool
    var color: Color = .accentColor

    var body: some View {
        Button {
            isActive.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? color.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? color : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
