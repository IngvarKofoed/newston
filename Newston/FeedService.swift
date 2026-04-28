import Foundation
import SwiftData

protocol FeedFetching {
    @MainActor
    func refresh(source: Source) async throws -> Int
}

enum FeedError: LocalizedError {
    case noFeedFound
    case parseFailed
    case networkFailed
    case missingModelContext

    var errorDescription: String? {
        switch self {
        case .noFeedFound: return "Could not find a feed or any headlines."
        case .parseFailed: return "Could not parse the feed."
        case .networkFailed: return "Network request failed."
        case .missingModelContext: return "Source is not attached to a model context."
        }
    }
}

@MainActor
struct FeedService: FeedFetching {
    func refresh(source: Source) async throws -> Int {
        guard let modelContext = source.modelContext else {
            throw FeedError.missingModelContext
        }

        let parsedItems: [ParsedItem]

        if let cached = source.feedURL {
            parsedItems = try await fetchAndParseFeed(at: cached)
        } else if !source.usesHTMLFallback,
                  let discovered = try await discoverFeedURL(homepage: source.url) {
            parsedItems = try await fetchAndParseFeed(at: discovered)
            source.feedURL = discovered
        } else {
            guard let html = try await fetchString(source.url) else {
                throw FeedError.networkFailed
            }
            let scraped = HeadlineScraper().scrape(html: html, base: source.url)
            if scraped.isEmpty {
                throw FeedError.noFeedFound
            }
            parsedItems = scraped
            source.usesHTMLFallback = true
        }

        let existing = Set(source.headlines.map(\.articleURL))
        var added = 0
        for item in parsedItems where !existing.contains(item.url) {
            let headline = Headline(
                title: item.title,
                articleURL: item.url,
                publishedAt: item.publishedAt,
                source: source
            )
            modelContext.insert(headline)
            added += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
        return added
    }

    // MARK: - Feed fetch + parse

    private func fetchAndParseFeed(at url: URL) async throws -> [ParsedItem] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FeedError.networkFailed
        }
        guard let parsed = FeedParser().parse(data: data) else {
            throw FeedError.parseFailed
        }
        return parsed.items
    }

    // MARK: - Feed discovery

    private func discoverFeedURL(homepage: URL) async throws -> URL? {
        if try await isFeed(at: homepage) { return homepage }

        if let html = try await fetchString(homepage),
           let linked = findFeedLink(in: html, base: homepage) {
            return linked
        }

        for path in ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml"] {
            if let candidate = URL(string: path, relativeTo: homepage)?.absoluteURL,
               try await isFeed(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isFeed(at url: URL) async throws -> Bool {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return false
        }
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("xml") || contentType.contains("rss") || contentType.contains("atom") {
            return true
        }
        if let prefix = String(data: data.prefix(1024), encoding: .utf8)?.lowercased(),
           prefix.contains("<rss") || prefix.contains("<feed") {
            return true
        }
        return false
    }

    private func fetchString(_ url: URL) async throws -> String? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func findFeedLink(in html: String, base: URL) -> URL? {
        let tagPattern = #"<link\s[^>]*?>"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            guard let r = Range(match.range, in: html) else { continue }
            let tag = String(html[r])
            let lower = tag.lowercased()
            guard lower.contains("rel=\"alternate\"") || lower.contains("rel='alternate'") else { continue }
            guard lower.contains("rss+xml") || lower.contains("atom+xml") else { continue }
            guard let href = extractAttribute("href", from: tag),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            return url
        }
        return nil
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range),
              let r = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }
}
