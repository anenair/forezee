// ============================================================
// CoachView.swift
// Forzee — Features/Coach
//
// Phase 1 chat interface + Phase 2 proactive daily briefing.
// The briefing card is what proves the life-signal pipeline
// (HealthKit/EventKit/WeatherKit → ContextBuilder → Kai) is
// actually reaching the model, without the user saying a word.
// Replaces the Coach tab placeholder.
// ============================================================

import SwiftUI

struct CoachView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var kaiEngine = KaiEngine.shared
    @ObservedObject private var voiceManager = VoiceManager.shared
    @ObservedObject private var voiceSynthesizer = KaiVoiceSynthesizer.shared
    @ObservedObject private var syncManager = SyncManager.shared

    @State private var briefing: String?
    @State private var isLoadingBriefing = false
    @State private var messages: [KaiMessage] = []
    @State private var draftMessage: String = ""
    @State private var streamingReply: String = ""
    @State private var errorMessage: String?
    @State private var isVoiceModeOn = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                            briefingCard

                            ForEach(messages) { message in
                                MessageBubble(message: message)
                            }

                            if kaiEngine.isResponding, !streamingReply.isEmpty {
                                MessageBubble(message: KaiMessage(role: .assistant, content: streamingReply))
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.fzBody(13))
                                    .foregroundStyle(Color.fzPink)
                            }
                        }
                        .padding(ForzeeSpacing.screenPadding)
                    }

                    if isVoiceModeOn {
                        voiceStatusBar
                    }

                    if !syncManager.isOnline {
                        ConnectivityNotice(message: "No connection — Kai can't chat or listen right now.")
                            .padding(.horizontal, ForzeeSpacing.screenPadding)
                            .padding(.bottom, 8)
                    }

                    inputBar
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleVoiceMode) {
                        Image(systemName: isVoiceModeOn ? "mic.fill" : "mic")
                            .foregroundStyle(isVoiceModeOn ? Color.fzPrimary : Color.fzTextSecondary)
                    }
                }
            }
        }
        .task { await loadBriefing() }
        .onDisappear { stopVoiceMode() }
    }

    // MARK: - Voice Mode

    private var voiceStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.fzPrimary)
                .symbolEffect(.variableColor.iterative, isActive: voiceManager.state != .idle)

            Text(voiceStatusText)
                .font(.fzBody(13, weight: .medium))
                .foregroundStyle(Color.fzTextSecondary)

            Spacer()
        }
        .padding(.horizontal, ForzeeSpacing.screenPadding)
        .padding(.vertical, 8)
    }

    private var voiceStatusText: String {
        if voiceSynthesizer.isSpeaking { return "Kai is speaking..." }
        switch voiceManager.state {
        case .idle:                return "Voice mode on — say \"Hi Kai\""
        case .listeningForWake:    return "Listening for \"Hi Kai\"..."
        case .listeningForCommand: return voiceManager.liveTranscript.isEmpty
            ? "Go ahead, I'm listening..."
            : voiceManager.liveTranscript
        }
    }

    private func toggleVoiceMode() {
        if isVoiceModeOn {
            stopVoiceMode()
        } else {
            Task { await startVoiceMode() }
        }
    }

    private func startVoiceMode() async {
        guard syncManager.isOnline else {
            errorMessage = "Voice mode needs a connection — Kai has to understand what you say."
            return
        }
        if !voiceManager.isAuthorized {
            guard await voiceManager.requestAuthorization() else {
                errorMessage = "Voice mode needs microphone and speech recognition access — enable it in Settings."
                return
            }
        }
        isVoiceModeOn = true
        listenForWakePhrase()
    }

    private func stopVoiceMode() {
        isVoiceModeOn = false
        voiceManager.stopListening()
        voiceSynthesizer.stop()
    }

    private func listenForWakePhrase() {
        guard isVoiceModeOn else { return }
        voiceManager.startListeningForWake { command in
            sendMessage(command, speakReply: true)
        }
    }

    // MARK: - Briefing

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.fzPrimary)
                Text("Today's Briefing")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
            }

            if isLoadingBriefing {
                ProgressView().tint(Color.fzPrimary)
            } else if let briefing {
                Text(briefing)
                    .font(.fzBody(15))
                    .foregroundStyle(Color.fzText)
            } else if !syncManager.isOnline {
                Text("No connection — Kai needs one to put this together. Reconnect and reopen Coach.")
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzPrimaryDim)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzPrimary.opacity(0.3), lineWidth: 1)
        )
    }

    private func loadBriefing() async {
        guard let userId = appState.userId else { return }
        isLoadingBriefing = true
        defer { isLoadingBriefing = false }
        do {
            briefing = try await kaiEngine.generateDailyBriefing(userId: userId)
        } catch {
            briefing = nil
            #if DEBUG
            print("CoachView: briefing failed — \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask Kai anything...", text: $draftMessage, axis: .vertical)
                .font(.fzBody(15))
                .foregroundStyle(Color.fzText)
                .padding(12)
                .background(Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                .lineLimit(1...4)

            Button(action: { sendMessage(draftMessage, speakReply: false) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.fzPrimary : Color.fzBorder)
            }
            .disabled(!canSend)
        }
        .padding(ForzeeSpacing.screenPadding)
        .background(Color.fzBg)
    }

    private var canSend: Bool {
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !kaiEngine.isResponding
            && syncManager.isOnline
    }

    /// Shared by the text input and voice mode — a voice-captured command
    /// and a typed message both flow through the same chat pipeline and
    /// land in the same conversation thread.
    private func sendMessage(_ rawText: String, speakReply: Bool) {
        guard let userId = appState.userId else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if speakReply { listenForWakePhrase() }
            return
        }

        draftMessage = ""
        errorMessage = nil
        let userMessage = KaiMessage(role: .user, content: text)
        messages.append(userMessage)
        streamingReply = ""

        Task {
            do {
                try await kaiEngine.chat(
                    message: text,
                    userId: userId,
                    history: messages,
                    onToken: { token in
                        streamingReply += token
                    },
                    onComplete: { reply in
                        messages.append(reply)
                        streamingReply = ""
                        if speakReply {
                            voiceSynthesizer.speak(reply.content, isPremium: appState.subscriptionTier.isPremium) {
                                listenForWakePhrase()
                            }
                        }
                    }
                )
            } catch {
                errorMessage = error.localizedDescription
                streamingReply = ""
                if speakReply { listenForWakePhrase() }
            }
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: KaiMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(.fzBody(15))
                .foregroundStyle(message.role == .user ? Color(hex: "0A0A0F") : Color.fzText)
                .padding(12)
                .background(message.role == .user ? Color.fzPrimary : Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    CoachView()
        .environmentObject(AppState())
}
