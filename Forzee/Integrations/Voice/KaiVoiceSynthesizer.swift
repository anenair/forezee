// ============================================================
// KaiVoiceSynthesizer.swift
// Forzee — Integrations/Voice
//
// Speaks Kai's replies aloud. Premium users with an ElevenLabs
// key configured get Kai's custom voice; everyone else gets the
// free system voice (AVSpeechSynthesizer) — this split was
// already staged in Secrets.xcconfig.example, just never wired up.
//
// Never lets a voice failure block the conversation: any
// ElevenLabs error (network, quota, bad key) falls back to the
// system voice rather than going silent.
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

    private let elevenLabsAPIKey: String
    private let elevenLabsVoiceId: String

    private override init() {
        self.elevenLabsAPIKey = Bundle.main.infoDictionary?["ELEVENLABS_API_KEY"] as? String ?? ""
        self.elevenLabsVoiceId = Bundle.main.infoDictionary?["ELEVENLABS_VOICE_ID"] as? String ?? ""
        super.init()
        systemSynthesizer.delegate = self
    }

    // MARK: - Public

    /// Speaks the given text aloud. Uses ElevenLabs for premium users when
    /// configured, otherwise (or on any failure) the free system voice.
    func speak(_ text: String, isPremium: Bool, onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
        isSpeaking = true

        guard isPremium, elevenLabsConfigured else {
            speakWithSystemVoice(text)
            return
        }

        Task {
            do {
                let audioData = try await fetchElevenLabsAudio(for: text)
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

    // MARK: - Private — ElevenLabs

    private var elevenLabsConfigured: Bool {
        !elevenLabsAPIKey.isEmpty
            && !elevenLabsAPIKey.hasPrefix("your-elevenlabs")
            && !elevenLabsVoiceId.isEmpty
            && !elevenLabsVoiceId.hasPrefix("your-kai-voice")
    }

    private func fetchElevenLabsAudio(for text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(elevenLabsVoiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ElevenLabsRequest(text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw KaiVoiceError.elevenLabsRequestFailed
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

// MARK: - ElevenLabsRequest

private struct ElevenLabsRequest: Encodable {
    let text: String
    let modelId = "eleven_turbo_v2_5"

    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
    }
}

// MARK: - KaiVoiceError

enum KaiVoiceError: LocalizedError {
    case elevenLabsRequestFailed

    var errorDescription: String? {
        "Kai's voice is unavailable right now."
    }
}
