import SwiftUI
import SwiftData
import AVFoundation

struct NowListeningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NowListeningPlayer.self) private var player
    @Query(sort: \Source.addedAt) private var sources: [Source]

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "No sources",
                        systemImage: "newspaper",
                        description: Text("Add a news source from the Sources tab to start listening.")
                    )
                } else {
                    listeningSurface
                }
            }
            .navigationTitle("Now Listening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !player.availableVoices.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        voicePicker
                    }
                }
                if !sources.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        sourcePicker
                    }
                }
            }
            .onAppear {
                player.setModelContext(modelContext)
                if player.currentSource == nil, let first = sources.first {
                    player.selectSource(first)
                }
            }
        }
    }

    private var listeningSurface: some View {
        VStack(spacing: 24) {
            if let source = player.currentSource {
                Text(source.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let headline = player.currentHeadline {
                VStack(spacing: 8) {
                    Text(headline.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text(headlineCounter)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ContentUnavailableView(
                    "No headlines yet",
                    systemImage: "tray",
                    description: Text("Refresh this source from the Sources tab.")
                )
            }

            modeIndicator

            Spacer()

            transportControls

            if player.currentHeadline != nil {
                Button {
                    Task { await player.readCurrentArticle() }
                } label: {
                    Label("Read article", systemImage: "doc.text")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }

            if let error = player.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if player.shouldSuggestBetterVoice {
                Text("For better-quality speech, download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private var headlineCounter: String {
        guard !player.sortedHeadlines.isEmpty else { return "" }
        return "\(player.currentHeadlineIndex + 1) of \(player.sortedHeadlines.count)"
    }

    @ViewBuilder
    private var modeIndicator: some View {
        switch player.mode {
        case .idle:
            EmptyView()
        case .announcing:
            Label(player.playbackState == .paused ? "Paused" : "Announcing headlines",
                  systemImage: player.playbackState == .paused ? "pause.fill" : "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .reading:
            Label(player.playbackState == .paused ? "Paused" : "Reading article",
                  systemImage: player.playbackState == .paused ? "pause.fill" : "book")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title)
            }
            .disabled(!player.canGoPrevious)

            Button {
                switch player.playbackState {
                case .playing: player.pause()
                case .paused, .stopped: player.play()
                }
            } label: {
                Image(systemName: playPauseIcon)
                    .font(.system(size: 64))
            }
            .disabled(player.currentHeadline == nil)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title)
            }
            .disabled(!player.canGoNext)
        }
    }

    private var playPauseIcon: String {
        switch player.playbackState {
        case .playing: return "pause.circle.fill"
        case .paused, .stopped: return "play.circle.fill"
        }
    }

    private var voicePicker: some View {
        let groups = Dictionary(grouping: player.availableVoices, by: \.language)
        let languages = groups.keys.sorted()
        return Menu {
            ForEach(languages, id: \.self) { language in
                Menu(language) {
                    ForEach(groups[language] ?? [], id: \.identifier) { voice in
                        Button {
                            player.selectVoice(voice)
                        } label: {
                            if voice.identifier == player.currentVoiceIdentifier {
                                Label(voiceLabel(voice), systemImage: "checkmark")
                            } else {
                                Text(voiceLabel(voice))
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Voice", systemImage: "person.wave.2")
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let qualityTag: String
        switch voice.quality {
        case .premium: qualityTag = " ★ Premium"
        case .enhanced: qualityTag = " ★ Enhanced"
        default: qualityTag = ""
        }
        return "\(voice.name)\(qualityTag)"
    }

    private var sourcePicker: some View {
        Menu {
            ForEach(sources) { source in
                Button {
                    player.selectSource(source)
                } label: {
                    if source.persistentModelID == player.currentSource?.persistentModelID {
                        Label(source.name, systemImage: "checkmark")
                    } else {
                        Text(source.name)
                    }
                }
            }
        } label: {
            Label("Source", systemImage: "list.bullet")
        }
    }
}

#Preview {
    NowListeningView()
        .modelContainer(for: Source.self, inMemory: true)
        .environment(NowListeningPlayer())
}
