import Foundation

struct HeadlineScraper {
    func scrape(html: String, base: URL) -> [ParsedItem] {
        let pattern = #"<a\s[^>]*?href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let baseHost = base.host()
        var seen = Set<URL>()
        var items: [ParsedItem] = []

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }

            let href = String(html[hrefRange])
            let rawText = String(html[textRange])
            let text = decodeEntities(stripTags(rawText)).trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.count >= 20, text.count <= 200 else { continue }
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            guard let host = url.host(), host == baseHost else { continue }

            let path = url.path()
            guard path.count > 1 else { continue }

            if Self.excludedPathFragments.contains(where: { path.lowercased().contains($0) }) {
                continue
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            let dedupURL = components?.url ?? url

            guard !seen.contains(dedupURL) else { continue }
            seen.insert(dedupURL)

            items.append(ParsedItem(title: text, url: dedupURL, publishedAt: nil))
        }

        return items
    }

    private static let excludedPathFragments = [
        "/tag/", "/tags/", "/category/", "/categories/",
        "/author/", "/authors/", "/about", "/contact",
        "/login", "/signup", "/sign-up", "/subscribe",
        "/privacy", "/terms", "/feed", "/rss", "/sitemap"
    ]

    private func stripTags(_ html: String) -> String {
        let pattern = #"<[^>]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
    }

    private func decodeEntities(_ html: String) -> String {
        var result = html
        for (entity, char) in Self.entityReplacements {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }

    private static let entityReplacements: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
        ("&apos;", "'"), ("&nbsp;", " "),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ("&lsquo;", "‘"), ("&rsquo;", "’"),
        ("&ldquo;", "“"), ("&rdquo;", "”")
    ]
}
