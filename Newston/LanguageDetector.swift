import Foundation
import NaturalLanguage

struct LanguageDetector {
    func detect(homepage: URL, titles: [String]) async -> String? {
        if let html = await fetchString(homepage), let lang = parseHTMLLang(html) {
            return lang
        }
        return detectFromTitles(titles)
    }

    func parseHTMLLang(_ html: String) -> String? {
        let pattern = #"<html\b[^>]*\blang\s*=\s*["']([a-zA-Z][a-zA-Z0-9-]*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        let raw = String(html[r])
        return raw.split(separator: "-").first.map { $0.lowercased() }
    }

    func detectFromTitles(_ titles: [String]) -> String? {
        let combined = titles.prefix(20).joined(separator: " ")
        guard combined.count >= 30 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)
        return recognizer.dominantLanguage?.rawValue
    }

    private func fetchString(_ url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
