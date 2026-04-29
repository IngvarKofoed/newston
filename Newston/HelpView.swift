import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Newston is voice-driven. Tap the mic in Now Listening, then speak any of the commands below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Navigation") {
                    ForEach(Self.navigationLevels, id: \.level) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.level).font(.headline)
                            Text(entry.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Voice commands") {
                    ForEach(Self.commandEntries, id: \.command) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label).font(.headline)
                            Text(entry.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(phrases(for: entry.command).map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Help")
        }
    }

    private func phrases(for command: VoiceCommand) -> [String] {
        CommandParser.patterns.first(where: { $0.0 == command })?.1 ?? []
    }

    private struct NavigationEntry {
        let level: String
        let description: String
    }

    private struct CommandEntry {
        let command: VoiceCommand
        let label: String
        let description: String
    }

    private static let navigationLevels: [NavigationEntry] = [
        .init(level: "Sources", description: "List of news sources you've added. Browse with next/previous, open with go."),
        .init(level: "Headlines", description: "Articles from the current source. Browse with next/previous, open with go, leave with back."),
        .init(level: "Article", description: "Reads the article body aloud. Use pause, resume, and stop. Say back to leave the article.")
    ]

    private static let commandEntries: [CommandEntry] = [
        .init(command: .next, label: "Next", description: "Move to the next source or headline."),
        .init(command: .previous, label: "Previous", description: "Move to the previous source or headline."),
        .init(command: .back, label: "Back", description: "Leave the current view and go up one level."),
        .init(command: .go, label: "Go", description: "Open the highlighted source or headline."),
        .init(command: .pause, label: "Pause", description: "Pause the current reading."),
        .init(command: .resume, label: "Resume", description: "Resume a paused reading."),
        .init(command: .stop, label: "Stop", description: "Stop the current reading. Stays on the current view.")
    ]
}

#Preview {
    HelpView()
}
