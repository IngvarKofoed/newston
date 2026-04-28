import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            NowListeningView()
                .tabItem { Label("Now Listening", systemImage: "headphones") }

            SourcesView()
                .tabItem { Label("Sources", systemImage: "newspaper") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Source.self, inMemory: true)
        .environment(SourceRefreshCoordinator())
}
