// ============================================================
// KaiVoiceSynthesizer.swift
// Forzee — Integrations/Voice
//
// Speaks Kai's replies aloud. Premium users get Kai's custom
// ElevenLabs voice through the kai-voice Edge Function, which holds
// the ElevenLabs key server-side and re-checks premium status;
// everyone else gets the free system voice (AVSpeechSynthesizer).
//
// Never lets a voice failure block the conversation: any error
// (network, not deployed, not premium, ElevenLabs down) falls back
// to the system voice rather than going silent.
// ============================================================

import Foundation
import AVFoundation

@MainActor
final class KaiVoiceSynthesizer: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = KaiVoiceSynthesizer()

    // MARK: - Published State

    @Published private(set) var isSpeaking = false

    // MARK: - Private

    private let systemSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    private override init() {
        super.init()
        systemSynthesizer.delegate = self
    }

    // MARK: - Public

    /// Speaks the given text aloud. Uses Kai's custom voice for premium
    /// users, otherwise (or on any failure) the free system voice.
    /// `isPremium` only saves free users a round trip — kai-voice
    /// re-checks premium status server-side either way.
    func speak(_ text: String, isPremium: Bool, onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        isSpeaking = true

        guard isPremium else {
            speakWithSystemVoice(text)
            return
        }

        Task {
            do {
                let audioData = try await fetchKaiVoiceAudio(for: text)
                playAudio(audioData, fallbackText: text)
            } catch {
                #if DEBUG
                print("KaiVoiceSynthesizer: ElevenLabs failed, falling back — \(error.localizedDescription)")
                #endif
                speakWithSystemVoice(text)
            }
        }
    }

    /// Interrupts whatever is currently speaking (e.g. the user starts a new command).
    func stop() {
        systemSynthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        isSpeaking = false
    }

    // MARK: - Private — System Voice

    private func speakWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        systemSynthesizer.speak(utterance)
    }

    // MARK: - Private — Kai's voice (kai-voice Edge Function)

    private func fetchKaiVoiceAudio(for text: String) async throws -> Data {
        var request = try await ForzeeDataService.shared.edgeFunctionRequest("kai-voice")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw KaiVoiceError.voiceRequestFailed
        }
        return data
    }

    private func playAudio(_ data: Data, fallbackText: String) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)

            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            player.play()
        } catch {
            #if DEBUG
            print("KaiVoiceSynthesizer: playback failed, falling back — \(error.localizedDescription)")
            #endif
            speakWithSystemVoice(fallbackText)
        }
    }

    private func finishSpeaking() {
        isSpeaking = false
        onFinish?()
        onFinish = nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension KaiVoiceSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }
}

// MARK: - AVAudioPlayerDelegate

extension KaiVoiceSynthesizer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishSpeaking() }
    }
}

// MARK: - KaiVoiceError

enum KaiVoiceError: LocalizedError {
    case voiceRequestFailed

    var errorDescription: String? {
        "Kai's voice is unavailable right now."
    }
}
