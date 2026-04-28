import Foundation
import SwiftData

@Model
final class Headline {
    var title: String
    var articleURL: URL
    var publishedAt: Date?
    var fetchedAt: Date
    var source: Source?

    @Relationship(deleteRule: .cascade, inverse: \Article.headline)
    var article: Article?

    init(
        title: String,
        articleURL: URL,
        publishedAt: Date? = nil,
        fetchedAt: Date = .now,
        source: Source? = nil
    ) {
        self.title = title
        self.articleURL = articleURL
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.source = source
    }
}
