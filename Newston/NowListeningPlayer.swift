import Foundation
import AVFoundation
import NaturalLanguage
import SwiftData

@MainActor
@Observable
final class NowListeningPlayer {
    enum NavLevel: Equatable {
        case sources
        case headlines
        case article
    }

    enum SpeechState: Equatable {
        case idle
        case speaking
        case paused
    }

    private(set) var level: NavLevel = .sources
    private(set) var speechState: SpeechState = .idle
    private(set) var lastError: String?

    private(set) var allSources: [Source] = []
    private(set) var sourceIndex: Int = 0

    private(set) var sortedHeadlines: [Headline] = []
    private(set) var headlineIndex: Int = 0

    var currentSource: Source? {
        guard allSources.indices.contains(sourceIndex) else { return nil }
        return allSources[sourceIndex]
    }

    var currentHeadline: Headline? {
        guard sortedHeadlines.indices.contains(headlineIndex) else { return nil }
        return sortedHeadlines[headlineIndex]
    }

    private(set) var availableVoices: [AVSpeechSynthesisVoice] = []
    private(set) var currentVoiceIdentifier: String?

    var shouldSuggestBetterVoice: Bool {
        guard let voice = currentVoice else { return true }
        return voice.quality.rawValue < AVSpeechSynthesisVoiceQuality.enhanced.rawValue
    }

    var voiceListeningEnabled: Bool { recognizer.isEnabled }
    var voicePermissionStatus: SpeechPermissionStatus { recognizer.permissionStatus }
    var lastRecognizedText: String { recognizer.lastTranscript }
    var voiceStartupError: String? { recognizer.startupError }

    private static let voiceIdentifierKey = "Newston.preferredVoiceIdentifier"

    private let synthesizer: SpeechSynthesizing
    private let extractor: ArticleExtracting
    private let recognizer: SpeechRecognizing
    private let commandParser = CommandParser()
    private weak var modelContext: ModelContext?
    private var eventsTask: Task<Void, Never>?
    private var transcriptsTask: Task<Void, Never>?

    init(
        synthesizer: SpeechSynthesizing? = nil,
        extractor: ArticleExtracting? = nil,
        recognizer: SpeechRecognizing? = nil
    ) {
        self.synthesizer = synthesizer ?? SpeechSynthesizerService()
        self.extractor = extractor ?? ArticleExtractor()
        self.recognizer = recognizer ?? SpeechRecognizerService()
        loadVoices()
        startEventLoop()
        startTranscriptsLoop()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setAllSources(_ sources: [Source]) {
        allSources = sources
        if sourceIndex >= sources.count {
            sourceIndex = max(sources.count - 1, 0)
        }
    }

    // MARK: - Navigation (level-aware)

    func next() {
        switch level {
        case .sources:
            guard !allSources.isEmpty else { return }
            sourceIndex = (sourceIndex + 1) % allSources.count
            speakCurrentSourceName()
        case .headlines:
            guard !sortedHeadlines.isEmpty else { return }
            headlineIndex = (headlineIndex + 1) % sortedHeadlines.count
            speakCurrentHeadlineTitle()
        case .article:
            break
        }
    }

    func previous() {
        switch level {
        case .sources:
            guard !allSources.isEmpty else { return }
            sourceIndex = (sourceIndex - 1 + allSources.count) % allSources.count
            speakCurrentSourceName()
        case .headlines:
            guard !sortedHeadlines.isEmpty else { return }
            headlineIndex = (headlineIndex - 1 + sortedHeadlines.count) % sortedHeadlines.count
            speakCurrentHeadlineTitle()
        case .article:
            break
        }
    }

    func go() async {
        switch level {
        case .sources:
            guard let source = currentSource else { return }
            loadHeadlines(for: source)
            level = .headlines
            speakCurrentHeadlineTitle()
        case .headlines:
            guard let headline = currentHeadline else { return }
            level = .article
            await readArticle(headline: headline)
        case .article:
            break
        }
    }

    func stop() {
        synthesizer.stop()
        if level == .article {
            level = .headlines
        }
    }

    func pause() {
        if speechState == .speaking {
            synthesizer.pause()
        }
    }

    func resume() {
        if speechState == .paused {
            synthesizer.resume()
        }
    }

    func backToSources() {
        synthesizer.stop()
        level = .sources
        sortedHeadlines = []
        headlineIndex = 0
    }

    // MARK: - Tap-driven source picking (toolbar)

    func selectSource(_ source: Source) {
        guard let idx = allSources.firstIndex(where: { $0.persistentModelID == source.persistentModelID }) else { return }
        synthesizer.stop()
        sourceIndex = idx
        level = .sources
        sortedHeadlines = []
        headlineIndex = 0
    }

    // MARK: - Voice listening

    func toggleVoiceListening() async {
        if recognizer.isEnabled {
            recognizer.stopListening()
            return
        }
        if recognizer.permissionStatus == .notDetermined {
            _ = await recognizer.requestAuthorization()
        }
        if recognizer.permissionStatus == .authorized {
            recognizer.startListening()
        } else {
            lastError = "Voice recognition permission denied. Enable it in Settings."
        }
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

    // MARK: - Speech actions

    private func loadHeadlines(for source: Source) {
        sortedHeadlines = source.headlines.sorted { lhs, rhs in
            (lhs.publishedAt ?? lhs.fetchedAt) > (rhs.publishedAt ?? rhs.fetchedAt)
        }
        headlineIndex = 0
    }

    private func speakCurrentSourceName() {
        guard let source = currentSource else { return }
        synthesizer.stop()
        synthesizer.speak(source.name, voice: voice(for: source.name))
    }

    private func speakCurrentHeadlineTitle() {
        guard let headline = currentHeadline else { return }
        synthesizer.stop()
        synthesizer.speak(headline.title, voice: voice(for: headline.title))
    }

    private func readArticle(headline: Headline) async {
        synthesizer.stop()
        lastError = nil
        do {
            let body = try await ensureArticleBody(for: headline)
            synthesizer.speak(body, voice: voice(for: body))
        } catch {
            lastError = error.localizedDescription
            level = .headlines
        }
    }

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

    // MARK: - Event loops

    private func startEventLoop() {
        eventsTask = Task { @MainActor [weak self, events = synthesizer.events] in
            for await event in events {
                self?.handleEvent(event)
            }
        }
    }

    private func startTranscriptsLoop() {
        transcriptsTask = Task { @MainActor [weak self, transcripts = recognizer.transcripts] in
            for await text in transcripts {
                self?.handleTranscript(text)
            }
        }
    }

    private func handleEvent(_ event: SpeechEvent) {
        switch event {
        case .didStart:
            speechState = .speaking
            recognizer.pauseCapture()
        case .didFinish:
            speechState = .idle
            recognizer.resumeCapture()
            if level == .article {
                level = .headlines
            }
        case .didCancel:
            speechState = .idle
            recognizer.resumeCapture()
        case .didPause:
            speechState = .paused
        case .didContinue:
            speechState = .speaking
        }
    }

    private func handleTranscript(_ text: String) {
        guard let command = commandParser.parse(text) else { return }
        dispatch(command)
    }

    private func dispatch(_ command: VoiceCommand) {
        switch command {
        case .next: next()
        case .previous: previous()
        case .go: Task { await go() }
        case .stop: stop()
        case .pause: pause()
        case .resume: resume()
        }
    }
}
