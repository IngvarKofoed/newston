import Foundation
import AVFoundation
import NaturalLanguage
import SwiftData

@MainActor
@Observable
final class NowListeningPlayer {
    enum Mode: Equatable {
        case idle
        case announcing
        case reading
    }

    enum PlaybackState: Equatable {
        case stopped
        case playing
        case paused
    }

    private(set) var mode: Mode = .idle
    private(set) var playbackState: PlaybackState = .stopped
    private(set) var currentSource: Source?
    private(set) var currentHeadlineIndex: Int = 0
    private(set) var sortedHeadlines: [Headline] = []
    private(set) var lastError: String?

    var currentHeadline: Headline? {
        guard sortedHeadlines.indices.contains(currentHeadlineIndex) else { return nil }
        return sortedHeadlines[currentHeadlineIndex]
    }

    var canGoPrevious: Bool { currentHeadlineIndex > 0 }
    var canGoNext: Bool { currentHeadlineIndex < sortedHeadlines.count - 1 }

    private(set) var availableVoices: [AVSpeechSynthesisVoice] = []
    private(set) var currentVoiceIdentifier: String?

    var shouldSuggestBetterVoice: Bool {
        guard let voice = currentVoice else { return true }
        return voice.quality.rawValue < AVSpeechSynthesisVoiceQuality.enhanced.rawValue
    }

    private static let voiceIdentifierKey = "Newston.preferredVoiceIdentifier"

    private let synthesizer: SpeechSynthesizing
    private let extractor: ArticleExtracting
    private weak var modelContext: ModelContext?
    private var eventsTask: Task<Void, Never>?

    init(synthesizer: SpeechSynthesizing? = nil, extractor: ArticleExtracting? = nil) {
        self.synthesizer = synthesizer ?? SpeechSynthesizerService()
        self.extractor = extractor ?? ArticleExtractor()
        loadVoices()
        startEventLoop()
    }

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoiceIdentifier = voice.identifier
        UserDefaults.standard.set(voice.identifier, forKey: Self.voiceIdentifierKey)
    }

    private var currentVoice: AVSpeechSynthesisVoice? {
        guard let id = currentVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    private func voice(for text: String) -> AVSpeechSynthesisVoice? {
        guard let detectedLanguage = detectLanguage(text) else { return currentVoice }
        let prefix = detectedLanguage.lowercased()
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

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Selection

    func selectSource(_ source: Source) {
        if currentSource?.persistentModelID != source.persistentModelID {
            stop()
            currentSource = source
            sortedHeadlines = source.headlines.sorted { lhs, rhs in
                let l = lhs.publishedAt ?? lhs.fetchedAt
                let r = rhs.publishedAt ?? rhs.fetchedAt
                return l > r
            }
            currentHeadlineIndex = 0
            lastError = nil
        }
    }

    // MARK: - Transport

    func play() {
        guard !sortedHeadlines.isEmpty else { return }
        if playbackState == .paused {
            synthesizer.resume()
            playbackState = .playing
            return
        }
        playbackState = .playing
        if mode == .idle { mode = .announcing }
        announceCurrentHeadline()
    }

    func pause() {
        synthesizer.pause()
        playbackState = .paused
    }

    func stop() {
        synthesizer.stop()
        playbackState = .stopped
        mode = .idle
    }

    func next() {
        guard canGoNext else { return }
        currentHeadlineIndex += 1
        if playbackState == .playing {
            synthesizer.stop()
            mode = .announcing
            announceCurrentHeadline()
        }
    }

    func previous() {
        guard canGoPrevious else { return }
        currentHeadlineIndex -= 1
        if playbackState == .playing {
            synthesizer.stop()
            mode = .announcing
            announceCurrentHeadline()
        }
    }

    func readCurrentArticle() async {
        guard let headline = currentHeadline else { return }
        synthesizer.stop()
        mode = .reading
        playbackState = .playing
        lastError = nil
        do {
            let body = try await ensureArticleBody(for: headline)
            synthesizer.speak(body, voice: voice(for: body))
        } catch {
            lastError = error.localizedDescription
            mode = .announcing
            playbackState = .stopped
        }
    }

    // MARK: - Private

    private func ensureArticleBody(for headline: Headline) async throws -> String {
        if let cached = headline.article?.bodyText, !cached.isEmpty {
            return cached
        }
        let body = try await extractor.extractBody(from: headline.articleURL)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context = modelContext, !trimmed.isEmpty {
            let article = Article(bodyText: trimmed, extractor: "naive-js", headline: headline)
            context.insert(article)
            try? context.save()
        }
        return trimmed
    }

    private func announceCurrentHeadline() {
        guard let headline = currentHeadline else {
            stop()
            return
        }
        synthesizer.speak(headline.title, voice: voice(for: headline.title))
    }

    private func startEventLoop() {
        eventsTask = Task { @MainActor [weak self, events = synthesizer.events] in
            for await event in events {
                self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SpeechEvent) {
        guard event == .didFinish else { return }
        guard playbackState == .playing else { return }

        switch mode {
        case .announcing:
            if canGoNext {
                currentHeadlineIndex += 1
                announceCurrentHeadline()
            } else {
                playbackState = .stopped
                mode = .idle
            }
        case .reading:
            mode = .announcing
            if canGoNext {
                currentHeadlineIndex += 1
                announceCurrentHeadline()
            } else {
                playbackState = .stopped
                mode = .idle
            }
        case .idle:
            break
        }
    }
}
