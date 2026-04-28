import Foundation
import Speech
import AVFoundation

enum SpeechPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol SpeechRecognizing: AnyObject {
    var isEnabled: Bool { get }
    var isCapturing: Bool { get }
    var permissionStatus: SpeechPermissionStatus { get }
    var lastTranscript: String { get }
    var startupError: String? { get }
    var transcripts: AsyncStream<String> { get }

    func requestAuthorization() async -> SpeechPermissionStatus
    func startListening()
    func stopListening()
    func pauseCapture()
    func resumeCapture()
}

@MainActor
@Observable
final class SpeechRecognizerService: NSObject, SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var endpointTask: Task<Void, Never>?
    private static let silenceEndpoint: Duration = .milliseconds(800)

    private(set) var isEnabled = false
    private(set) var isCapturing = false
    private(set) var lastTranscript: String = ""
    private(set) var startupError: String?
    private(set) var permissionStatus: SpeechPermissionStatus

    private let transcriptsContinuation: AsyncStream<String>.Continuation
    let transcripts: AsyncStream<String>

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        var continuation: AsyncStream<String>.Continuation!
        self.transcripts = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { c in
            continuation = c
        }
        self.transcriptsContinuation = continuation
        self.permissionStatus = Self.currentPermissionStatus()
        super.init()
    }

    func requestAuthorization() async -> SpeechPermissionStatus {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        if speechStatus == .authorized && micGranted {
            permissionStatus = .authorized
        } else if speechStatus == .restricted {
            permissionStatus = .restricted
        } else if speechStatus == .denied || !micGranted {
            permissionStatus = .denied
        } else {
            permissionStatus = .notDetermined
        }
        return permissionStatus
    }

    func startListening() {
        guard permissionStatus == .authorized else { return }
        guard !isEnabled else { return }
        isEnabled = true
        startCapturing()
    }

    func stopListening() {
        isEnabled = false
        stopCapturing()
    }

    func pauseCapture() {
        if isCapturing { stopCapturing() }
    }

    func resumeCapture() {
        if isEnabled && !isCapturing { startCapturing() }
    }

    // MARK: - Private

    private func startCapturing() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            startupError = "Speech recognizer not available."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            startupError = "Microphone returned a zero-sample-rate format. On the simulator, grant Simulator microphone access in macOS System Settings → Privacy & Security → Microphone, then restart the simulator."
            cleanupRecognition()
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            startupError = "Audio engine failed to start: \(error.localizedDescription)"
            cleanupRecognition()
            return
        }
        startupError = nil

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.lastTranscript = text
                    self.scheduleSilenceEndpoint()
                    if result.isFinal {
                        if !text.isEmpty {
                            self.transcriptsContinuation.yield(text)
                        }
                        self.handleSessionEnded()
                    }
                }
                if error != nil {
                    self.handleSessionEnded()
                }
            }
        }

        isCapturing = true
    }

    private func scheduleSilenceEndpoint() {
        endpointTask?.cancel()
        endpointTask = Task { [weak self] in
            try? await Task.sleep(for: Self.silenceEndpoint)
            if !Task.isCancelled {
                self?.recognitionRequest?.endAudio()
            }
        }
    }

    private func stopCapturing() {
        cleanupRecognition()
        isCapturing = false
    }

    private func handleSessionEnded() {
        cleanupRecognition()
        isCapturing = false
        // Auto-restart if user still wants listening on
        if isEnabled {
            startCapturing()
        }
    }

    private func cleanupRecognition() {
        endpointTask?.cancel()
        endpointTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private static func currentPermissionStatus() -> SpeechPermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
