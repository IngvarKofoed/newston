import Foundation
import AVFoundation

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
    func speak(_ text: String, voice: AVSpeechSynthesisVoice?)
    func stop()
    func pause()
    func resume()
}

@MainActor
final class SpeechSynthesizerService: NSObject, SpeechSynthesizing {
    private let synth = AVSpeechSynthesizer()
    private let eventsContinuation: AsyncStream<SpeechEvent>.Continuation
    let events: AsyncStream<SpeechEvent>

    var isSpeaking: Bool { synth.isSpeaking }

    override init() {
        var continuation: AsyncStream<SpeechEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { c in
            continuation = c
        }
        self.eventsContinuation = continuation
        super.init()
        synth.delegate = self
        configureAudioSession()
    }

    func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = voice
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

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Audio session failure is non-fatal — TTS will still attempt to play.
            print("AVAudioSession configuration failed: \(error)")
        }
    }
}

extension SpeechSynthesizerService: AVSpeechSynthesizerDelegate {
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
