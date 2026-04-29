import Foundation
import AVFoundation
import SwiftData

@MainActor
@Observable
final class NowListeningPlayer {
    enum NavStep: Hashable {
        case source(Source)
        case headline(Headline)
    }

    enum Level: Equatable {
        case sources
        case headlines
        case article
    }

    enum SpeechState: Equatable {
        case idle
        case speaking
        case paused
    }

    var path: [NavStep] = []

    private(set) var speechState: SpeechState = .idle
    var lastError: String?

    private(set) var allSources: [Source] = []
    private(set) var sourceIndex: Int = 0

    private(set) var sortedHeadlines: [Headline] = []
    private(set) var headlineIndex: Int = 0

    private(set) var currentArticleBody: String?
    private(set) var isLoadingArticle: Bool = false
    private(set) var articleError: String?

    // One-shot signal set by voice "go" before path.append, consumed by the
    // destination view's `.task`. Lets us narrate audibly on voice-driven
    // navigation while keeping touch-driven navigation silent.
    private var pendingVoiceNarration: Bool = false

    var level: Level {
        switch path.count {
        case 0: return .sources
        case 1: return .headlines
        default: return .article
        }
    }

    var currentSource: Source? {
        if case .source(let s) = path.first { return s }
        return allSources.indices.contains(sourceIndex) ? allSources[sourceIndex] : nil
    }

    var currentHeadline: Headline? {
        if path.count >= 2, case .headline(let h) = path[1] { return h }
        return sortedHeadlines.indices.contains(headlineIndex) ? sortedHeadlines[headlineIndex] : nil
    }

    var availableVoices: [AVSpeechSynthesisVoice] { systemSynth?.availableVoices ?? [] }
    var currentVoiceIdentifier: String? { systemSynth?.currentVoiceIdentifier }
    var shouldSuggestBetterVoice: Bool { systemSynth?.shouldSuggestBetterVoice ?? false }

    var voiceListeningEnabled: Bool { recognizer.isEnabled }
    var voicePermissionStatus: SpeechPermissionStatus { recognizer.permissionStatus }
    var lastRecognizedText: String { recognizer.lastTranscript }
    var voiceStartupError: String? { recognizer.startupError }

    private var synthesizer: SpeechSynthesizing
    // Typed reference to the AVSpeech synth when active, used for voice
    // picker pass-throughs. Nil when a non-AVSpeech provider is in use.
    private var systemSynth: SystemSpeechSynthesizer?
    private let extractor: ArticleExtracting
    private let cleaner: ArticleCleaning
    private let recognizer: SpeechRecognizing
    private let commandParser = CommandParser()
    private weak var modelContext: ModelContext?
    private var eventsTask: Task<Void, Never>?
    private var transcriptsTask: Task<Void, Never>?

    init(
        synthesizer: SpeechSynthesizing? = nil,
        extractor: ArticleExtracting? = nil,
        cleaner: ArticleCleaning? = nil,
        recognizer: SpeechRecognizing? = nil
    ) {
        let resolvedSynth = synthesizer ?? Self.makeSynthesizer()
        self.synthesizer = resolvedSynth
        self.systemSynth = resolvedSynth as? SystemSpeechSynthesizer
        self.extractor = extractor ?? ArticleExtractor()
        self.cleaner = cleaner ?? DefaultArticleCleaner()
        self.recognizer = recognizer ?? SpeechRecognizerService()
        startEventLoop()
        startTranscriptsLoop()
    }

    func setProvider(_ provider: TTSProvider) {
        synthesizer.stop()
        eventsTask?.cancel()
        eventsTask = nil
        let newSynth = Self.makeSynthesizer(for: provider)
        synthesizer = newSynth
        systemSynth = newSynth as? SystemSpeechSynthesizer
        startEventLoop()
    }

    private static func makeSynthesizer(for provider: TTSProvider? = nil) -> SpeechSynthesizing {
        let resolved = provider ?? Self.currentProvider()
        switch resolved {
        case .iOSVoices:  return SystemSpeechSynthesizer()
        case .elevenLabs: return ElevenLabsSpeechSynthesizer()
        }
    }

    private static func currentProvider() -> TTSProvider {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.ttsProvider),
              let p = TTSProvider(rawValue: raw) else { return .iOSVoices }
        return p
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

    // MARK: - Cursor selection (called from list rows on tap)

    func setSourceCursor(_ source: Source) {
        guard let idx = allSources.firstIndex(where: { $0.persistentModelID == source.persistentModelID }) else { return }
        sourceIndex = idx
    }

    func setHeadlineCursor(_ headline: Headline) {
        guard let idx = sortedHeadlines.firstIndex(where: { $0.persistentModelID == headline.persistentModelID }) else { return }
        headlineIndex = idx
    }

    // MARK: - View lifecycle hooks
    //
    // Each "enter" hook is responsible for stopping any in-flight TTS from the
    // previous level before starting its own. We deliberately do NOT stop TTS
    // in "leave" hooks: SwiftUI fires `.onDisappear` after the navigation
    // animation completes (~0.3s), which can land after the next view's
    // `.task` has already started speaking and silently kill it.

    func didEnterSources() {
        // Safety reset: clear any flag the user abandoned before .task could
        // consume it, e.g. voice "go" → quickly pop back out.
        pendingVoiceNarration = false
        synthesizer.stop()
    }

    func didEnterHeadlines(source: Source) {
        sortedHeadlines = source.headlines.sorted { lhs, rhs in
            (lhs.publishedAt ?? lhs.fetchedAt) > (rhs.publishedAt ?? rhs.fetchedAt)
        }
        setSourceCursor(source)
        if !sortedHeadlines.indices.contains(headlineIndex) {
            headlineIndex = 0
        }
        if pendingVoiceNarration {
            pendingVoiceNarration = false
            speakCurrentHeadlineTitle()
        } else {
            // Touch entry: stop any in-flight TTS (e.g. article body when
            // popping back from article view) and stay silent.
            synthesizer.stop()
        }
    }

    func didEnterArticle(headline: Headline) async {
        setHeadlineCursor(headline)
        synthesizer.stop()
        currentArticleBody = nil
        articleError = nil
        lastError = nil
        isLoadingArticle = true
        // Capture before await — we don't want a later voice command flipping
        // the flag mid-extraction.
        let shouldNarrate = pendingVoiceNarration
        pendingVoiceNarration = false
        do {
            let body = try await ensureArticleBody(for: headline)
            currentArticleBody = body
            isLoadingArticle = false
            if shouldNarrate {
                synthesizer.speak(body, language: headline.source?.languageCode)
            }
        } catch {
            articleError = error.localizedDescription
            isLoadingArticle = false
        }
    }

    func didLeaveArticle() {
        currentArticleBody = nil
        isLoadingArticle = false
        articleError = nil
    }

    // MARK: - Navigation / transport

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

    func go() {
        switch level {
        case .sources:
            guard let source = currentSource else { return }
            // Signal to didEnterHeadlines (fired async by .task) that this
            // entry is voice-driven and should narrate the first title.
            pendingVoiceNarration = true
            path.append(.source(source))
        case .headlines:
            guard let headline = currentHeadline else { return }
            // Signal to didEnterArticle (fired async by .task) that this
            // entry is voice-driven and should auto-read the body.
            pendingVoiceNarration = true
            path.append(.headline(headline))
        case .article:
            break
        }
    }

    func stop() {
        synthesizer.stop()
    }

    func back() {
        synthesizer.stop()
        guard !path.isEmpty else { return }
        path.removeLast()
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

    func togglePauseResume() {
        switch speechState {
        case .speaking: pause()
        case .paused: resume()
        case .idle:
            // Touch users land here at the article view (silent entry). Start
            // reading the body if we have one.
            guard level == .article,
                  let body = currentArticleBody, !body.isEmpty,
                  let headline = currentHeadline else { return }
            synthesizer.speak(body, language: headline.source?.languageCode)
        }
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
        systemSynth?.selectVoice(voice)
    }

    // MARK: - Speech actions

    private func speakCurrentSourceName() {
        guard let source = currentSource else { return }
        synthesizer.stop()
        synthesizer.speak(source.name, language: source.languageCode)
    }

    private func speakCurrentHeadlineTitle() {
        guard let headline = currentHeadline else { return }
        synthesizer.stop()
        synthesizer.speak(headline.title, language: headline.source?.languageCode)
    }

    private func ensureArticleBody(for headline: Headline) async throws -> String {
        if let cached = headline.article?.bodyText, !cached.isEmpty {
            return cached
        }
        let raw = try await extractor.extractBody(from: headline.articleURL)
        let cleaned = cleaner.clean(raw, language: headline.source?.languageCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let context = modelContext, !cleaned.isEmpty {
            let article = Article(bodyText: cleaned, extractor: "readability-v1+cleanup-v1", headline: headline)
            context.insert(article)
            try? context.save()
        }
        return cleaned
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
        // Mic stays live across TTS playback so the user can barge-in
        // ("stop", "pause") mid-utterance. Echo cancellation is handled
        // by the audio engine's voice-processing I/O unit.
        switch event {
        case .didStart:
            speechState = .speaking
        case .didFinish:
            speechState = .idle
        case .didCancel:
            speechState = .idle
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
        case .back: back()
        case .go: go()
        case .stop: stop()
        case .pause: pause()
        case .resume: resume()
        }
    }
}
