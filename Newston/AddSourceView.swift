import SwiftUI
import SwiftData

struct AddSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SourceRefreshCoordinator.self) private var coordinator

    enum Step {
        case urlEntry
        case browser
    }

    @State private var step: Step = .urlEntry
    @State private var urlText: String = ""
    @State private var nameText: String = ""
    @State private var resolvedURL: URL?
    @State private var resolvedName: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .urlEntry: urlEntryForm
                case .browser: browserView
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                switch step {
                case .urlEntry:
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") { proceedToBrowser() }
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                case .browser:
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add source") { commit() }
                    }
                }
            }
        }
    }

    private var urlEntryForm: some View {
        Form {
            Section("Website") {
                TextField("https://example.com", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }
            Section("Name (optional)") {
                TextField("Auto-derived from URL", text: $nameText)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Text("Next you'll see the website in a browser. Accept any cookie banners or log in if needed, then tap **Add source**.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add source")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var browserView: some View {
        if let url = resolvedURL {
            WebView(url: url)
                .navigationTitle(resolvedName)
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func proceedToBrowser() {
        guard let url = normalizedURL(from: urlText) else {
            errorMessage = "Enter a valid http(s) URL."
            return
        }
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? defaultName(for: url) : trimmedName
        resolvedURL = url
        resolvedName = name
        errorMessage = nil
        step = .browser
    }

    private func commit() {
        guard let url = resolvedURL else { return }
        let source = Source(name: resolvedName, url: url)
        modelContext.insert(source)
        Task { await coordinator.refresh(source) }
        dismiss()
    }

    private func normalizedURL(from input: String) -> URL? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else {
            return nil
        }
        return url
    }

    private func defaultName(for url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

#Preview {
    AddSourceView()
        .modelContainer(for: Source.self, inMemory: true)
        .environment(SourceRefreshCoordinator())
}
