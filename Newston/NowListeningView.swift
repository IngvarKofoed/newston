import SwiftUI
import SwiftData

struct NowListeningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NowListeningPlayer.self) private var player
    @Query(sort: \Source.addedAt) private var sources: [Source]

    var body: some View {
        @Bindable var player = player

        NavigationStack(path: $player.path) {
            SourcesListView(sources: sources)
                .navigationDestination(for: NowListeningPlayer.NavStep.self) { step in
                    switch step {
                    case .source(let source):
                        HeadlinesListView(source: source)
                    case .headline(let headline):
                        ArticleView(headline: headline)
                    }
                }
        }
        .onAppear {
            player.setModelContext(modelContext)
            player.setAllSources(sources)
        }
        .onChange(of: sources) { _, newSources in
            player.setAllSources(newSources)
        }
    }
}

#Preview {
    NowListeningView()
        .modelContainer(for: Source.self, inMemory: true)
        .environment(NowListeningPlayer())
}
