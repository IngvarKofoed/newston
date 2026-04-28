import Foundation

struct ParsedFeed {
    var items: [ParsedItem]
}

struct ParsedItem {
    var title: String
    var url: URL
    var publishedAt: Date?
}

final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [ParsedItem] = []

    private var inItem = false
    private var currentTitle: String?
    private var currentLink: String?
    private var currentPubDate: String?
    private var currentText = ""

    func parse(data: Data) -> ParsedFeed? {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return ParsedFeed(items: items)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let lower = elementName.lowercased()
        if lower == "item" || lower == "entry" {
            inItem = true
            currentTitle = nil
            currentLink = nil
            currentPubDate = nil
        }
        if inItem, lower == "link" {
            // Atom: <link rel="alternate" href="..."/>
            let rel = attributeDict["rel"]?.lowercased()
            if rel == nil || rel == "alternate", let href = attributeDict["href"], currentLink == nil {
                currentLink = href
            }
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) {
            currentText += s
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let lower = elementName.lowercased()
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard inItem else { return }

        switch lower {
        case "title":
            currentTitle = trimmed
        case "link":
            // RSS: <link>https://...</link>
            if currentLink == nil, !trimmed.isEmpty {
                currentLink = trimmed
            }
        case "pubdate", "published", "updated":
            if currentPubDate == nil, !trimmed.isEmpty {
                currentPubDate = trimmed
            }
        case "item", "entry":
            if let title = currentTitle,
               let linkString = currentLink,
               let url = URL(string: linkString) {
                items.append(ParsedItem(
                    title: title,
                    url: url,
                    publishedAt: currentPubDate.flatMap(Self.parseDate)
                ))
            }
            inItem = false
        default:
            break
        }
    }

    nonisolated private static func parseDate(_ string: String) -> Date? {
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = rfc822.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
