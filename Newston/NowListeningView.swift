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
                    ToolbarItem(placement: .topBarLeading) { voicePicker }
                }
                if !sources.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { sourcePicker }
                }
            }
            .onAppear {
                player.setModelContext(modelContext)
                player.setAllSources(sources)
            }
            .onChange(of: sources) { _, newSources in
                player.setAllSources(newSources)
            }
        }
    }

    private var listeningSurface: some View {
        VStack(spacing: 24) {
            levelBreadcrumb

            Spacer(minLength: 12)

            currentItemCard

            Spacer()

            transportControls

            voiceCommandRow

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

    // MARK: - Level UI

    private var levelBreadcrumb: some View {
        Text(breadcrumbText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var breadcrumbText: String {
        switch player.level {
        case .sources:
            return "Sources"
        case .headlines:
            return "\(player.currentSource?.name ?? "—") · Headlines"
        case .article:
            return "\(player.currentSource?.name ?? "—") · Reading"
        }
    }

    @ViewBuilder
    private var currentItemCard: some View {
        switch player.level {
        case .sources: sourcesCard
        case .headlines: headlinesCard
        case .article: articleCard
        }
    }

    private var sourcesCard: some View {
        VStack(spacing: 8) {
            if let source = player.currentSource {
                Text(source.name)
                    .font(.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if !player.allSources.isEmpty {
                    Text("\(player.sourceIndex + 1) of \(player.allSources.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            hint("Say \u{201C}go\u{201D} to enter, \u{201C}next\u{201D} or \u{201C}previous\u{201D} to browse sources.")
        }
    }

    @ViewBuilder
    private var headlinesCard: some View {
        if let headline = player.currentHeadline {
            VStack(spacing: 8) {
                Text(headline.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("\(player.headlineIndex + 1) of \(player.sortedHeadlines.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                hint("Say \u{201C}go\u{201D} to read the article, \u{201C}next\u{201D} or \u{201C}previous\u{201D} to browse.")
            }
        } else {
            ContentUnavailableView(
                "No headlines",
                systemImage: "tray",
                description: Text("Refresh this source from the Sources tab.")
            )
        }
    }

    @ViewBuilder
    private var articleCard: some View {
        if let headline = player.currentHeadline {
            VStack(spacing: 12) {
                Label("Reading article", systemImage: speechStateIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(headline.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                hint("Say \u{201C}stop\u{201D} to exit, or \u{201C}pause\u{201D} and \u{201C}resume\u{201D}.")
            }
        }
    }

    private var speechStateIcon: String {
        switch player.speechState {
        case .speaking: return "waveform"
        case .paused: return "pause.fill"
        case .idle: return "book"
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title)
            }
            .disabled(player.level == .article)

            Button {
                if player.level == .article {
                    if player.speechState == .paused {
                        player.resume()
                    } else {
                        player.pause()
                    }
                } else {
                    Task { await player.go() }
                }
            } label: {
                Image(systemName: centerButtonIcon)
                    .font(.system(size: 64))
            }

            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.title)
            }
            .disabled(player.level == .article)
        }
        .overlay(alignment: .trailing) {
            if player.level == .article {
                Button { player.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .padding(.trailing)
                .accessibilityLabel("Stop reading")
            }
        }
    }

    private var centerButtonIcon: String {
        switch player.level {
        case .sources, .headlines:
            return "play.circle.fill"
        case .article:
            return player.speechState == .paused ? "play.circle.fill" : "pause.circle.fill"
        }
    }

    // MARK: - Voice row

    private var voiceCommandRow: some View {
        VStack(spacing: 6) {
            Button {
                Task { await player.toggleVoiceListening() }
            } label: {
                Image(systemName: player.voiceListeningEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(
                            player.voiceListeningEnabled ? Color.red : Color.secondary.opacity(0.2)
                        )
                    )
                    .foregroundStyle(player.voiceListeningEnabled ? .white : .secondary)
            }
            .accessibilityLabel(player.voiceListeningEnabled ? "Disable voice commands" : "Enable voice commands")

            if player.voicePermissionStatus == .denied {
                Text("Voice permission denied — enable in Settings → Privacy → Speech Recognition.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if let startupError = player.voiceStartupError, player.voiceListeningEnabled {
                Text(startupError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if player.voiceListeningEnabled, !player.lastRecognizedText.isEmpty {
                Text("\u{201C}\(player.lastRecognizedText)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Pickers

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
