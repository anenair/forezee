// ============================================================
// VoiceManager.swift
// Forzee — Integrations/Voice
//
// Wake-phrase ("Hi Kai" / "Hey Kai") detection and speech-to-text,
// built on Speech + AVAudioEngine.
//
// IMPORTANT — foreground only. iOS does not let third-party apps
// listen in the background or with the screen locked the way Siri
// does; there is no public always-on wake-word API. This only
// listens while the Coach screen is open and Voice Mode is on.
//
// Also not true "always on": SFSpeechRecognitionTask has to be
// restarted periodically (~1 min of audio per task), which this
// does transparently, but a word spoken in the small gap between
// restarts can be missed. Acceptable for a first pass, not Siri-grade.
// ============================================================

import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceManager: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = VoiceManager()

    // MARK: - State

    enum State: Equatable {
        case idle                 // not listening
        case listeningForWake     // mic on, watching for the wake phrase
        case listeningForCommand  // wake phrase heard, capturing the request
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published var isAuthorized = false
    @Published var lastError: String?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var commandSilenceTimer: Timer?
    private var onCommandCaptured: ((String) -> Void)?

    private let wakePhrases = ["hi kai", "hey kai", "hi, kai", "hey, kai", "hi cai", "hey cai"]

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        isAuthorized = (speechStatus == .authorized) && micGranted
        return isAuthorized
    }

    // MARK: - Listening

    /// Starts listening for the wake phrase. `onCommand` fires once with the
    /// captured request after "Hi Kai" is heard and the user pauses.
    /// Automatically stops after one command — call again to keep listening.
    func startListeningForWake(onCommand: @escaping (String) -> Void) {
        guard isAuthorized, state == .idle else { return }
        onCommandCaptured = onCommand
        lastError = nil
        do {
            try startRecognition()
            state = .listeningForWake
        } catch {
            lastError = error.localizedDescription
            stopListening()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        commandSilenceTimer?.invalidate()
        commandSilenceTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        liveTranscript = ""
        state = .idle
    }

    // MARK: - Private — Recognition

    private func startRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionUpdate(result: result, error: error)
            }
        }
    }

    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?) {
        guard state != .idle else { return }

        if let result {
            processTranscript(result.bestTranscription.formattedString)
        }

        // A task ends after ~1 min of audio or on error — restart transparently
        // so listening effectively continues across the boundary.
        if error != nil || (result?.isFinal ?? false) {
            guard state != .idle else { return }
            try? startRecognition()
        }
    }

    private func processTranscript(_ transcript: String) {
        liveTranscript = transcript
        let lower = transcript.lowercased()

        switch state {
        case .listeningForWake:
            guard let range = wakePhrases.compactMap({ lower.range(of: $0) }).first else { return }
            state = .listeningForCommand
            let trailing = String(transcript[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            liveTranscript = trailing
            resetSilenceTimer(currentText: trailing)

        case .listeningForCommand:
            resetSilenceTimer(currentText: transcript)

        case .idle:
            break
        }
    }

    /// Fires the captured command 1.2s after the user stops talking —
    /// long enough for a natural pause, short enough to feel responsive.
    private func resetSilenceTimer(currentText: String) {
        commandSilenceTimer?.invalidate()
        commandSilenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listeningForCommand else { return }
                let command = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.stopListening()
                if !command.isEmpty {
                    self.onCommandCaptured?(command)
                }
            }
        }
    }
}
