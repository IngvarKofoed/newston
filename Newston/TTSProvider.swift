import Foundation

enum TTSProvider: String, CaseIterable, Identifiable {
    case iOSVoices
    case elevenLabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOSVoices: return "iOS Voices"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

enum SettingsKey {
    static let ttsProvider = "Newston.ttsProvider"
    static let elevenLabsAPIKey = "Newston.elevenlabs.apiKey"
}
