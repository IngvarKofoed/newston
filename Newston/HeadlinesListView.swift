import SwiftUI
import SwiftData

struct HeadlinesListView: View {
    @Environment(NowListeningPlayer.self) private var player
    let source: Source

    private var sortedHeadlines: [Headline] {
        source.headlines.sorted { lhs, rhs in
            (lhs.publishedAt ?? lhs.fetchedAt) > (rhs.publishedAt ?? rhs.fetchedAt)
        }
    }

    var body: some View {
        Group {
            if sortedHeadlines.isEmpty {
                ContentUnavailableView(
                    "No headlines",
                    systemImage: "tray",
                    description: Text("Refresh this source from the Sources tab.")
                )
            } else {
                List {
                    ForEach(Array(sortedHeadlines.enumerated()), id: \.element.persistentModelID) { index, headline in
                        NavigationLink(value: NowListeningPlayer.NavStep.headline(headline)) {
                            headlineRow(headline, isSpeaking: isSpeaking(at: index))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VoiceTranscriptStatus()
                .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MicToolbarButton() }
        }
        .task {
            player.didEnterHeadlines(source: source)
        }
        .onDisappear {
            player.didLeaveHeadlines()
        }
    }

    private func headlineRow(_ headline: Headline, isSpeaking: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline.title)
                    .font(.body)
                    .lineLimit(3)
                if let date = headline.publishedAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Reading aloud")
            }
        }
        .padding(.vertical, 4)
    }

    private func isSpeaking(at index: Int) -> Bool {
        player.speechState == .speaking && index == player.headlineIndex
    }
}
