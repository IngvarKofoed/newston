import Foundation

protocol ArticleCleaning: Sendable {
    func clean(_ raw: String, language: String?) -> String
}

struct DefaultArticleCleaner: ArticleCleaning {
    func clean(_ raw: String, language: String?) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { collapseInlineWhitespace(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !isDroppable($0) }

        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: " "))
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func collapseInlineWhitespace(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var lastWasSpace = false
        for ch in s {
            if ch == " " || ch == "\t" || ch == "\u{00A0}" {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(ch)
                lastWasSpace = false
            }
        }
        return result
    }

    private func isDroppable(_ line: String) -> Bool {
        if line.isEmpty { return false }
        let hasLetterOrDigit = line.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
        return !hasLetterOrDigit
    }
}
