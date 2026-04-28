import SwiftUI
import AVFoundation

struct MicToolbarButton: View {
    @Environment(NowListeningPlayer.self) private var player

    var body: some View {
        Button {
            Task { await player.toggleVoiceListening() }
        } label: {
            Image(systemName: player.voiceListeningEnabled ? "mic.fill" : "mic.slash")
                .foregroundStyle(player.voiceListeningEnabled ? .red : .secondary)
        }
        .accessibilityLabel(player.voiceListeningEnabled ? "Disable voice commands" : "Enable voice commands")
    }
}

struct VoicePickerMenu: View {
    @Environment(NowListeningPlayer.self) private var player

    var body: some View {
        let groups = Dictionary(grouping: player.availableVoices, by: \.language)
        let languages = groups.keys.sorted()
        Menu {
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
}

struct VoiceTranscriptStatus: View {
    @Environment(NowListeningPlayer.self) private var player

    var body: some View {
        Group {
            if player.voicePermissionStatus == .denied {
                Text("Voice permission denied — enable in Settings → Privacy → Speech Recognition.")
                    .foregroundStyle(.tertiary)
            } else if let startupError = player.voiceStartupError, player.voiceListeningEnabled {
                Text(startupError)
                    .foregroundStyle(.orange)
            } else if player.voiceListeningEnabled, !player.lastRecognizedText.isEmpty {
                Text("\u{201C}\(player.lastRecognizedText)\u{201D}")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                EmptyView()
            }
        }
        .font(.caption2)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}
