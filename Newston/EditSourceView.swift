import SwiftUI
import SwiftData

struct EditSourceView: View {
    @Bindable var source: Source
    @Environment(SourceRefreshCoordinator.self) private var coordinator

    @State private var urlText: String = ""
    @State private var urlError: String?
    @State private var feedURLText: String = ""
    @State private var feedURLError: String?
    @State private var hasInitialized = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $source.name)
            }
            Section {
                TextField("https://example.com", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onChange(of: urlText) { _, newValue in
                        applyURL(newValue)
                    }
                if let urlError {
                    Text(urlError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("URL")
            } footer: {
                Text("Changing the URL clears the cached feed URL so we re-discover on the next refresh.")
            }
            Section {
                TextField("https://example.com/feed", text: $feedURLText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onChange(of: feedURLText) { _, newValue in
                        applyFeedURL(newValue)
                    }
                if let feedURLError {
                    Text(feedURLError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Feed URL")
            } footer: {
                Text("Optional. Paste a feed URL if auto-discovery fails. Leave empty to scrape headlines from the homepage.")
            }
            Section {
                Button {
                    Task { await coordinator.refresh(source) }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.status(for: source) == .refreshing)
            }
            statusSection
            if !source.headlines.isEmpty {
                Section("Headlines (\(source.headlines.count))") {
                    let recent = source.headlines
                        .sorted { ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt) }
                        .prefix(10)
                    ForEach(Array(recent), id: \.persistentModelID) { headline in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headline.title)
                                .font(.callout)
                                .lineLimit(3)
                            Text(headline.articleURL.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle(source.name.isEmpty ? "Source" : source.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasInitialized {
                urlText = source.url.absoluteString
                feedURLText = source.feedURL?.absoluteString ?? ""
                hasInitialized = true
            }
        }
    }

    private func applyURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            urlError = "URL is required."
            return
        }
        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else {
            urlError = "Enter a valid http(s) URL."
            return
        }
        if url != source.url {
            source.url = url
            source.feedURL = nil
            source.usesHTMLFallback = false
            feedURLText = ""
        }
        urlError = nil
    }

    private func applyFeedURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            source.feedURL = nil
            feedURLError = nil
            return
        }
        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else {
            feedURLError = "Enter a valid http(s) URL."
            return
        }
        source.feedURL = url
        source.usesHTMLFallback = false
        feedURLError = nil
    }

    @ViewBuilder
    private var statusSection: some View {
        switch coordinator.status(for: source) {
        case .idle:
            EmptyView()
        case .refreshing:
            Section {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…")
                }
            }
        case .succeeded(let added, _):
            Section {
                Text(added > 0 ? "Added \(added) new headlines." : "Up to date.")
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            Section("Last refresh failed") {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }
}
