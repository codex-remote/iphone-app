import AVFAudio
import Foundation
import Speech

@MainActor
final class VoiceTranscriptionController: ObservableObject {
    static let maximumRecordingDuration: Duration = .seconds(55)

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
    }

    enum Failure: String, Identifiable {
        case speechPermissionDenied = "Allow speech recognition in Settings to use voice input."
        case microphonePermissionDenied = "Allow microphone access in Settings to use voice input."
        case recognitionUnavailable = "Speech recognition is not available for the selected language."
        case audioInputUnavailable = "No microphone input is currently available."
        case recordingFailed = "Voice input could not start. Please try again."

        var id: String { rawValue }

        var diagnosticCode: String {
            switch self {
            case .speechPermissionDenied: "speech_permission_denied"
            case .microphonePermissionDenied: "microphone_permission_denied"
            case .recognitionUnavailable: "recognition_unavailable"
            case .audioInputUnavailable: "audio_input_unavailable"
            case .recordingFailed: "recording_failed"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var composedText: String?
    @Published private(set) var failure: Failure?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var permissionAttemptID: UUID?
    private var recognitionSessionID: UUID?
    private var recognitionTimeoutTask: Task<Void, Never>?
    private var recordingStartedAt: ContinuousClock.Instant?
    private var tapInstalled = false
    private var initialText = ""
    private var languageCode = "en"

    var isRecording: Bool { phase == .recording }
    var isRequestingPermission: Bool { phase == .requestingPermission }

    func start(locale: Locale, existingText: String) async {
        guard phase == .idle else { return }

        cancelRecognition()
        failure = nil
        composedText = nil
        initialText = existingText
        languageCode = locale.language.languageCode?.identifier ?? "en"
        phase = .requestingPermission

        let attemptID = UUID()
        permissionAttemptID = attemptID

        guard await requestSpeechPermission() else {
            fail(.speechPermissionDenied, attemptID: attemptID)
            return
        }
        guard permissionAttemptID == attemptID else { return }

        guard await requestMicrophonePermission() else {
            fail(.microphonePermissionDenied, attemptID: attemptID)
            return
        }
        guard permissionAttemptID == attemptID else { return }

        beginRecognition(locale: locale, attemptID: attemptID)
    }

    func stop() {
        permissionAttemptID = nil
        guard phase != .idle else { return }

        phase = .idle
        finishRecordingDiagnostics()
        recognitionTimeoutTask?.cancel()
        recognitionTimeoutTask = nil
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
    }

    func cancel() {
        permissionAttemptID = nil
        phase = .idle
        cancelRecognition()
    }

    func dismissFailure() {
        failure = nil
    }

    private func beginRecognition(locale: Locale, attemptID: UUID) {
        guard permissionAttemptID == attemptID else { return }
        permissionAttemptID = nil

        guard let recognizer = makeRecognizer(for: locale), recognizer.isAvailable else {
            fail(.recognitionUnavailable)
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            fail(.audioInputUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["Codex", "Xcode", "SwiftUI", "Git", "Relay"]
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            tapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopAudioCapture()
            fail(.recordingFailed)
            return
        }

        let sessionID = UUID()
        recognitionSessionID = sessionID
        recognitionRequest = request
        speechRecognizer = recognizer
        phase = .recording
        recordingStartedAt = .now
        MemoryDiagnostics.shared.recordVoiceRecognition(started: true)
        recognitionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.maximumRecordingDuration)
            guard !Task.isCancelled else { return }
            self?.stop()
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                self?.handleRecognitionResult(
                    text: text,
                    isFinal: isFinal,
                    hasError: hasError,
                    sessionID: sessionID
                )
            }
        }
    }

    private func handleRecognitionResult(text: String?, isFinal: Bool, hasError: Bool, sessionID: UUID) {
        guard recognitionSessionID == sessionID else { return }

        if let text, !text.isEmpty {
            composedText = appending(transcription: text)
        }

        if isFinal {
            phase = .idle
            finishRecordingDiagnostics()
            recognitionTimeoutTask?.cancel()
            recognitionTimeoutTask = nil
            stopAudioCapture()
            clearRecognitionReferences()
        } else if hasError, phase == .recording {
            phase = .idle
            finishRecordingDiagnostics()
            cancelRecognition()
            failure = .recordingFailed
        } else if hasError {
            clearRecognitionReferences()
        }
    }

    private func appending(transcription: String) -> String {
        guard !initialText.isEmpty else { return transcription }
        guard initialText.last?.isWhitespace != true else { return initialText + transcription }
        let separator = languageCode == "zh" ? "" : " "
        return initialText + separator + transcription
    }

    private func makeRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        let requestedLanguage = locale.language.languageCode?.identifier ?? Locale.current.language.languageCode?.identifier
        let preferredIdentifier: String
        switch requestedLanguage {
        case "zh": preferredIdentifier = "zh-CN"
        case "en": preferredIdentifier = "en-US"
        default: preferredIdentifier = locale.identifier
        }

        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: preferredIdentifier)) {
            return recognizer
        }

        guard let requestedLanguage else { return nil }
        let fallback = SFSpeechRecognizer.supportedLocales().first {
            $0.language.languageCode?.identifier == requestedLanguage
        }
        return fallback.flatMap(SFSpeechRecognizer.init(locale:))
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func fail(_ failure: Failure, attemptID: UUID? = nil) {
        if let attemptID, permissionAttemptID != attemptID { return }
        permissionAttemptID = nil
        phase = .idle
        self.failure = failure
        Diagnostics.shared.record(
            .speechFailed,
            level: .error,
            category: .speech,
            fields: [.reason: .string(failure.diagnosticCode)]
        )
    }

    private func cancelRecognition() {
        finishRecordingDiagnostics()
        recognitionTimeoutTask?.cancel()
        recognitionTimeoutTask = nil
        stopAudioCapture()
        recognitionTask?.cancel()
        clearRecognitionReferences()
    }

    private func finishRecordingDiagnostics() {
        guard let recordingStartedAt else { return }
        self.recordingStartedAt = nil
        let duration = ContinuousClock.now - recordingStartedAt
        MemoryDiagnostics.shared.recordVoiceRecognition(
            started: false,
            duration: Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        )
    }

    private func clearRecognitionReferences() {
        recognitionSessionID = nil
        recognitionRequest = nil
        recognitionTask = nil
        speechRecognizer = nil
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
