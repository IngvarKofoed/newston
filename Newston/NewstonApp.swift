import SwiftUI
import SwiftData

@main
struct NewstonApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Source.self,
            Headline.self,
            Article.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var refreshCoordinator = SourceRefreshCoordinator()
    @State private var player = NowListeningPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(refreshCoordinator)
                .environment(player)
        }
        .modelContainer(sharedModelContainer)
    }
}
