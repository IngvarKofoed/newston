import Foundation
import SwiftData

@MainActor
@Observable
final class SourceRefreshCoordinator {
    enum Status: Equatable {
        case idle
        case refreshing
        case succeeded(addedCount: Int, completedAt: Date)
        case failed(message: String)
    }

    private var statuses: [PersistentIdentifier: Status] = [:]
    private let feedService: FeedFetching

    init(feedService: FeedFetching? = nil) {
        self.feedService = feedService ?? FeedService()
    }

    func status(for source: Source) -> Status {
        statuses[source.persistentModelID] ?? .idle
    }

    func refresh(_ source: Source) async {
        let id = source.persistentModelID
        statuses[id] = .refreshing
        do {
            let added = try await feedService.refresh(source: source)
            statuses[id] = .succeeded(addedCount: added, completedAt: .now)
        } catch {
            statuses[id] = .failed(message: error.localizedDescription)
        }
    }
}
