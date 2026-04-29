import Foundation
import AVFoundation
import NaturalLanguage

@MainActor
@Observable
final class ElevenLabsSpeechSynthesizer: SpeechSynthesizing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eventsContinuation: AsyncStream<SpeechEvent>.Continuation
    let events: AsyncStream<SpeechEvent>

    private var playbackTask: Task<Void, Never>?
    private(set) var isSpeaking: Bool = false
    private var isPaused: Bool = false

    // ElevenLabs default output is 44.1kHz mono MP3 (request via output_format).
    // We connect the player node with that format so scheduled buffers match.
    private static let outputFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!
    }()

    init() {
        var continuation: AsyncStream<SpeechEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { c in
            continuation = c
        }
        self.eventsContinuation = continuation
        configureAudioSession()
        setupEngine()
    }

    deinit {
        // Engine and player are stopped via the cleanup paths in stop(); this
        // is a final safety net for synth swap / app termination.
        if engine.isRunning {
            engine.stop()
        }
    }

    // MARK: - SpeechSynthesizing

    func speak(_ text: String, language: String?) {
        stop()
        guard let apiKey = Keychain.read(SettingsKey.elevenLabsAPIKey), !apiKey.isEmpty else {
            eventsContinuation.yield(.didCancel)
            return
        }
        let voiceId = Self.voiceId(for: language)
        let sentences = Self.splitSentences(text, language: language)
        guard !sentences.isEmpty else {
            eventsContinuation.yield(.didFinish)
            return
        }
        startPlayback(sentences: sentences, voiceId: voiceId, apiKey: apiKey)
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        if player.isPlaying {
            player.stop()
        }
        let wasSpeaking = isSpeaking
        isSpeaking = false
        isPaused = false
        if wasSpeaking {
            eventsContinuation.yield(.didCancel)
        }
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        player.pause()
        isPaused = true
        eventsContinuation.yield(.didPause)
    }

    func resume() {
        guard isPaused else { return }
        player.play()
        isPaused = false
        eventsContinuation.yield(.didContinue)
    }

    // MARK: - Audio setup

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
            print("AVAudioSession configuration failed: \(error)")
        }
    }

    private func setupEngine() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.outputFormat)
    }

    // MARK: - Playback loop

    private func startPlayback(sentences: [String], voiceId: String, apiKey: String) {
        playbackTask = Task { [weak self] in
            await self?.runPlaybackLoop(sentences: sentences, voiceId: voiceId, apiKey: apiKey)
        }
    }

    private func runPlaybackLoop(sentences: [String], voiceId: String, apiKey: String) async {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            print("AVAudioEngine failed to start: \(error)")
            eventsContinuation.yield(.didCancel)
            return
        }
        player.play()

        isSpeaking = true
        eventsContinuation.yield(.didStart)

        var nextFetch: Task<AVAudioPCMBuffer?, Never> = startFetch(sentences[0], voiceId: voiceId, apiKey: apiKey)

        for i in 0..<sentences.count {
            if Task.isCancelled { break }
            let buffer = await nextFetch.value
            if i + 1 < sentences.count {
                nextFetch = startFetch(sentences[i + 1], voiceId: voiceId, apiKey: apiKey)
            }
            guard let buffer, !Task.isCancelled else { continue }
            await scheduleAndAwait(buffer)
        }

        if Task.isCancelled { return }

        if isSpeaking {
            isSpeaking = false
            eventsContinuation.yield(.didFinish)
        }
        if player.isPlaying { player.stop() }
    }

    private func startFetch(_ sentence: String, voiceId: String, apiKey: String) -> Task<AVAudioPCMBuffer?, Never> {
        Task.detached {
            do {
                let mp3 = try await Self.fetchTTS(text: sentence, voiceId: voiceId, apiKey: apiKey)
                return try Self.decodeMP3(mp3)
            } catch {
                print("ElevenLabs fetch/decode failed: \(error)")
                return nil
            }
        }
    }

    private func scheduleAndAwait(_ buffer: AVAudioPCMBuffer) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) {
                cont.resume()
            }
        }
    }

    // MARK: - HTTP + decode

    private nonisolated static func fetchTTS(text: String, voiceId: String, apiKey: String) async throws -> Data {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        guard let url = components.url else {
            throw NSError(domain: "ElevenLabs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "ElevenLabs", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }

    private nonisolated static func decodeMP3(_ data: Data) throws -> AVAudioPCMBuffer {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = try AVAudioFile(forReading: temp)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "ElevenLabs", code: -1, userInfo: [NSLocalizedDescriptionKey: "PCM buffer alloc failed"])
        }
        try file.read(into: buffer)
        return buffer
    }

    // MARK: - Helpers

    private static func splitSentences(_ text: String, language: String?) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        if let code = language {
            tokenizer.setLanguage(NLLanguage(rawValue: code))
        }
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    private static func voiceId(for language: String?) -> String {
        let prefix = language?.lowercased().prefix(2) ?? ""
        switch prefix {
        case "da": return "kmSVBPu7loj4ayNinwWM"
        default:   return "UaYTS0wayjmO9KD1LR4R"
        }
    }
}
