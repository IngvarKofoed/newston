import SwiftUI
import SwiftData

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourceRefreshCoordinator.self) private var coordinator
    @Query(sort: \Source.addedAt) private var sources: [Source]
    @State private var isAddingSource = false

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "No sources yet",
                        systemImage: "newspaper",
                        description: Text("Add a news website to get started.")
                    )
                } else {
                    List {
                        ForEach(sources) { source in
                            NavigationLink {
                                EditSourceView(source: source)
                            } label: {
                                SourceRowContent(source: source)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await coordinator.refresh(source) }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteSources)
                    }
                    .refreshable { await refreshAll() }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                if !sources.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingSource = true
                    } label: {
                        Label("Add source", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingSource) {
                AddSourceView()
            }
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { await coordinator.refresh(source) }
            }
        }
    }
}

private struct SourceRowContent: View {
    let source: Source
    @Environment(SourceRefreshCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.headline)
            Text(source.url.host() ?? source.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
            statusLabel
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch coordinator.status(for: source) {
        case .idle:
            if source.headlines.isEmpty {
                Text("Not yet refreshed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(source.headlines.count) headlines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .refreshing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        case .succeeded(let added, _):
            Text(added > 0 ? "+\(added) new" : "Up to date")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed(let message):
            Text("Failed: \(message)")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

#Preview {
    SourcesView()
        .modelContainer(for: Source.self, inMemory: true)
        .environment(SourceRefreshCoordinator())
}
