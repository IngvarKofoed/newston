import Foundation

enum VoiceCommand: Equatable {
    case next
    case previous
    case go
    case stop
    case pause
    case resume
}

struct CommandParser {
    func parse(_ utterance: String) -> VoiceCommand? {
        let phrase = normalize(utterance)
        guard !phrase.isEmpty else { return nil }
        for (command, patterns) in Self.patterns {
            for pattern in patterns where matches(pattern, in: phrase) {
                return command
            }
        }
        return nil
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
         .components(separatedBy: CharacterSet.alphanumerics.inverted)
         .filter { !$0.isEmpty }
         .joined(separator: " ")
    }

    private func matches(_ pattern: String, in phrase: String) -> Bool {
        if phrase == pattern { return true }
        if phrase.hasPrefix(pattern + " ") { return true }
        if phrase.hasSuffix(" " + pattern) { return true }
        if phrase.contains(" " + pattern + " ") { return true }
        return false
    }

    // Multi-word patterns must come before their single-word substrings.
    private static let patterns: [(VoiceCommand, [String])] = [
        (.go, ["read this", "go", "okay", "ok", "open", "read", "yes"]),
        (.stop, ["stop", "cancel", "quit", "shut up"]),
        (.pause, ["pause", "wait"]),
        (.resume, ["resume", "continue", "go on", "play"]),
        (.previous, ["previous", "prev", "back", "before"]),
        (.next, ["next", "forward", "skip"]),
    ]
}
