import SwiftUI
import SwiftData

struct SourcesListView: View {
    @Environment(NowListeningPlayer.self) private var player
    let sources: [Source]

    var body: some View {
        Group {
            if sources.isEmpty {
                ContentUnavailableView(
                    "No sources",
                    systemImage: "newspaper",
                    description: Text("Add a news source from the Sources tab to start listening.")
                )
            } else {
                List {
                    ForEach(Array(sources.enumerated()), id: \.element.persistentModelID) { index, source in
                        NavigationLink(value: NowListeningPlayer.NavStep.source(source)) {
                            sourceRow(source, isSpeaking: isSpeaking(at: index))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Newston")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            VoiceTranscriptStatus()
                .padding(.bottom, 8)
        }
        .toolbar {
            if !player.availableVoices.isEmpty {
                ToolbarItem(placement: .topBarLeading) { VoicePickerMenu() }
            }
            ToolbarItem(placement: .topBarTrailing) { MicToolbarButton() }
        }
    }

    private func sourceRow(_ source: Source, isSpeaking: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                Text("\(source.headlines.count) headlines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Reading aloud")
            }
        }
        .padding(.vertical, 2)
    }

    private func isSpeaking(at index: Int) -> Bool {
        player.speechState == .speaking && index == player.sourceIndex
    }
}

#Preview {
    NavigationStack {
        SourcesListView(sources: [])
    }
    .environment(NowListeningPlayer())
}
