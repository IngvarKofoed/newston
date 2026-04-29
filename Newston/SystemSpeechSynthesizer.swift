import Foundation
import AVFoundation
import NaturalLanguage

enum SpeechEvent: Sendable {
    case didStart
    case didFinish
    case didCancel
    case didPause
    case didContinue
}

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var events: AsyncStream<SpeechEvent> { get }
    var isSpeaking: Bool { get }
    func speak(_ text: String, language: String?)
    func stop()
    func pause()
    func resume()
}

@MainActor
@Observable
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    private let synth = AVSpeechSynthesizer()
    private let eventsContinuation: AsyncStream<SpeechEvent>.Continuation
    let events: AsyncStream<SpeechEvent>

    var isSpeaking: Bool { synth.isSpeaking }

    private static let voiceIdentifierKey = "Newston.preferredVoiceIdentifier"

    private(set) var availableVoices: [AVSpeechSynthesisVoice] = []
    private(set) var currentVoiceIdentifier: String?

    var shouldSuggestBetterVoice: Bool {
        guard let voice = currentVoice else { return true }
        return voice.quality.rawValue < AVSpeechSynthesisVoiceQuality.enhanced.rawValue
    }

    override init() {
        var continuation: AsyncStream<SpeechEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { c in
            continuation = c
        }
        self.eventsContinuation = continuation
        super.init()
        synth.delegate = self
        configureAudioSession()
        loadVoices()
    }

    func speak(_ text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = voice(for: text, languageHint: language)
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func pause() {
        synth.pauseSpeaking(at: .word)
    }

    func resume() {
        synth.continueSpeaking()
    }

    // MARK: - Voice picker

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoiceIdentifier = voice.identifier
        UserDefaults.standard.set(voice.identifier, forKey: Self.voiceIdentifierKey)
    }

    private var currentVoice: AVSpeechSynthesisVoice? {
        guard let id = currentVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    private func voice(for text: String, languageHint: String? = nil) -> AVSpeechSynthesisVoice? {
        guard let language = languageHint ?? detectLanguage(text) else { return currentVoice }
        let prefix = language.lowercased()
        if let currentVoice, currentVoice.language.lowercased().hasPrefix(prefix) {
            return currentVoice
        }
        let candidates = availableVoices.filter { $0.language.lowercased().hasPrefix(prefix) }
        if let best = candidates.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return best
        }
        return currentVoice
    }

    private func detectLanguage(_ text: String) -> String? {
        guard text.count >= 10 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func loadVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices().sorted { lhs, rhs in
            if lhs.language != rhs.language { return lhs.language < rhs.language }
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name < rhs.name
        }
        currentVoiceIdentifier = pickInitialVoice()?.identifier
    }

    private func pickInitialVoice() -> AVSpeechSynthesisVoice? {
        if let saved = UserDefaults.standard.string(forKey: Self.voiceIdentifierKey),
           let voice = AVSpeechSynthesisVoice(identifier: saved) {
            return voice
        }
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        let candidates = availableVoices.filter { $0.language.lowercased().hasPrefix(langCode.lowercased()) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? availableVoices.max { $0.quality.rawValue < $1.quality.rawValue }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP]
            )
            try session.setActive(true, options: [])
        } catch {
            // Audio session failure is non-fatal — TTS will still attempt to play.
            print("AVAudioSession configuration failed: \(error)")
        }
    }
}

extension SystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        eventsContinuation.yield(.didStart)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        eventsContinuation.yield(.didFinish)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        eventsContinuation.yield(.didCancel)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        eventsContinuation.yield(.didPause)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        eventsContinuation.yield(.didContinue)
    }
}
