import Foundation
import SwiftData

@Model
final class Source {
    var name: String
    var url: URL
    var feedURL: URL?
    var usesHTMLFallback: Bool = false
    var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Headline.source)
    var headlines: [Headline] = []

    init(name: String, url: URL, feedURL: URL? = nil, addedAt: Date = .now) {
        self.name = name
        self.url = url
        self.feedURL = feedURL
        self.addedAt = addedAt
    }
}
