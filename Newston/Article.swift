import Foundation
import SwiftData

@Model
final class Article {
    var bodyText: String
    var extractedAt: Date
    var extractor: String
    var headline: Headline?

    init(
        bodyText: String,
        extractor: String,
        extractedAt: Date = .now,
        headline: Headline? = nil
    ) {
        self.bodyText = bodyText
        self.extractor = extractor
        self.extractedAt = extractedAt
        self.headline = headline
    }
}
