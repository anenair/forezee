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
    @State private var isNearBottom = true
    @State private var isBuildingWorkout = false
    @State private var workoutBuildError: String?
    @State private var workoutBuiltConfirmation: String?

    private static let bottomAnchorId = "bottom"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                                briefingCard

                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                        let isNewTurn = index == 0 || messages[index - 1].role != message.role
                                        MessageBubble(message: message, showAvatar: isNewTurn)
                                            .padding(.top, isNewTurn ? 10 : 0)
                                    }

                                    if kaiEngine.isResponding {
                                        let isNewTurn = messages.last?.role != .assistant
                                        if streamingReply.isEmpty {
                                            KaiThinkingBubble(showAvatar: isNewTurn)
                                                .padding(.top, isNewTurn ? 10 : 0)
                                        } else {
                                            MessageBubble(
                                                message: KaiMessage(role: .assistant, content: streamingReply),
                                                showAvatar: isNewTurn
                                            )
                                            .padding(.top, isNewTurn ? 10 : 0)
                                        }
                                    }
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.fzBody(13))
                                        .foregroundStyle(Color.fzPink)
                                }

                                if !kaiEngine.isResponding, messages.contains(where: { $0.role == .assistant }) {
                                    BuildWorkoutRow(
                                        isBuilding: isBuildingWorkout,
                                        confirmation: workoutBuiltConfirmation,
                                        error: workoutBuildError,
                                        onBuild: { Task { await buildWorkoutFromChat() } },
                                        onOpenWorkoutTab: { appState.activeTab = .workout }
                                    )
                                }

                                Color.clear.frame(height: 1).id(Self.bottomAnchorId)
                            }
                            .padding(ForzeeSpacing.screenPadding)
                        }
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y + geometry.containerSize.height
                                >= geometry.contentSize.height - 60
                        } action: { _, nearBottom in
                            isNearBottom = nearBottom
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if !isNearBottom {
                                Button(action: { scrollToBottom(proxy: proxy, animated: true) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color(hex: "0A0A0F"))
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.fzPrimary))
                                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                                }
                                .padding(.trailing, ForzeeSpacing.screenPadding)
                                .padding(.bottom, 12)
                            }
                        }
                        .onChange(of: messages.count) { _, _ in
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                        .onChange(of: streamingReply) { _, _ in
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                        .onAppear {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
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
        .task { await loadChatHistory() }
        .onDisappear { stopVoiceMode() }
    }

    private func loadChatHistory() async {
        guard let userId = appState.userId else { return }
        messages = await kaiEngine.loadRecentHistory(userId: userId)
    }

    // MARK: - Build Workout

    /// Extracts whatever workout the conversation has settled on so far and
    /// hands it to WorkoutTabView via AppState — the exercises as actually
    /// negotiated in chat (added/removed/adjusted), not a generic re-roll.
    private func buildWorkoutFromChat() async {
        guard let userId = appState.userId else { return }
        isBuildingWorkout = true
        workoutBuildError = nil
        defer { isBuildingWorkout = false }

        do {
            guard let workout = try await kaiEngine.extractWorkoutFromChat(userId: userId, history: messages) else {
                workoutBuildError = "Couldn't find a clear plan yet — ask Kai to lay out the exercises first."
                return
            }
            appState.activeWorkout = workout
            workoutBuiltConfirmation = "Added \"\(workout.name)\" (\(workout.exercises.count) exercises) to your Workout tab."
        } catch {
            workoutBuildError = error.localizedDescription
        }
    }

    // MARK: - Scrolling

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation { proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
        }
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
                KaiRingsView(size: 40)
                    .frame(height: 40)
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
                .submitLabel(.send)
                .onChange(of: draftMessage) { _, newValue in
                    // A vertical-axis TextField treats Return as "insert a
                    // newline" — .onSubmit never fires for it. Detect the
                    // newline Return appends, strip it, and send instead.
                    // Deferred to the next runloop turn: mutating draftMessage
                    // synchronously from inside its own onChange re-triggers
                    // onChange within the same frame (SwiftUI warns on this).
                    guard newValue.hasSuffix("\n") else { return }
                    DispatchQueue.main.async {
                        draftMessage.removeLast()
                        guard canSend else { return }
                        sendMessage(draftMessage, speakReply: false)
                    }
                }

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
        workoutBuiltConfirmation = nil
        workoutBuildError = nil
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

// MARK: - BuildWorkoutRow

/// The "Build Workout" affordance shown under the conversation — lets the
/// user turn whatever's been negotiated in chat (exercises added/removed,
/// duration changed) into a real workout on demand, rather than losing that
/// context to a generic re-roll from the Workout tab's own Generate button.
private struct BuildWorkoutRow: View {
    let isBuilding: Bool
    let confirmation: String?
    let error: String?
    let onBuild: () -> Void
    let onOpenWorkoutTab: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let confirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.fzGreen)
                    Text(confirmation)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                ForzeeTextButton(title: "Open Workout Tab", action: onOpenWorkoutTab)
            } else {
                Button(action: onBuild) {
                    HStack(spacing: 8) {
                        if isBuilding {
                            ProgressView().tint(Color.fzPrimary).scaleEffect(0.8)
                        } else {
                            Image(systemName: "dumbbell.fill")
                        }
                        Text(isBuilding ? "Building..." : "Build Workout From This Chat")
                            .font(.fzBody(14, weight: .medium))
                    }
                    .foregroundStyle(Color.fzPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.fzPrimaryDim)
                    .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.pill))
                }
                .disabled(isBuilding)

                if let error {
                    Text(error)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
    }
}

// MARK: - KaiThinkingBubble

/// Shown in place of the assistant bubble during the gap between sending
/// a message and the first streamed token arriving — Kai's visual
/// signature standing in for a generic spinner.
private struct KaiThinkingBubble: View {
    let showAvatar: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KaiAvatarSlot(showAvatar: showAvatar)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    ThinkingDot(delay: Double(i) * 0.15)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingDot: View {
    let delay: Double
    @State private var scale: CGFloat = 0.6

    var body: some View {
        Circle()
            .fill(Color.fzPrimary)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: KaiMessage
    let showAvatar: Bool

    private enum Block {
        case prose(String)
        case listItem(String)
    }

    /// Kai's replies are plain text with blank-line paragraph breaks, and a
    /// "- " prefix on any line that's an exercise in a list rather than
    /// prose (see the system prompt's formatting rule). Rendering list
    /// items distinctly from prose — instead of every block looking like an
    /// identical paragraph — is what actually cuts the clutter on a long
    /// workout rundown.
    private var blocks: [Block] {
        let split = message.content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let paragraphs = split.isEmpty ? [message.content] : split
        return paragraphs.map { text in
            text.hasPrefix("- ") ? .listItem(String(text.dropFirst(2))) : .prose(text)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                KaiAvatarSlot(showAvatar: showAvatar)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .prose(let text):
                            Text(text)
                                .font(.fzBody(15))
                                .foregroundStyle(textColor)
                                .lineSpacing(4)
                                .multilineTextAlignment(.leading)
                        case .listItem(let text):
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(textColor.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(text)
                                    .font(.fzBody(14))
                                    .foregroundStyle(textColor)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 275, alignment: .leading)
                .background(message.role == .user ? Color.fzPrimary : Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                .shadow(color: .black.opacity(message.role == .assistant ? 0.15 : 0), radius: 5, y: 2)

                if showAvatar {
                    Text(message.createdAt, style: .time)
                        .font(.fzBody(11))
                        .foregroundStyle(Color.fzTextSecondary.opacity(0.55))
                        .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var textColor: Color {
        message.role == .user ? Color(hex: "0A0A0F") : Color.fzText
    }
}

// MARK: - KaiAvatarSlot

/// Kai's visual identity in chat: the same living sound-wave/galaxy
/// animation used everywhere else (onboarding, thinking indicator), sized
/// down to an avatar. Only rendered on the first bubble of a consecutive
/// run from Kai — `showAvatar: false` reserves the same width with an
/// empty space so later bubbles in the run still line up underneath it,
/// and so only one instance animates per run rather than one per message.
private struct KaiAvatarSlot: View {
    let showAvatar: Bool

    var body: some View {
        Group {
            if showAvatar {
                KaiRingsView(size: 26)
            } else {
                Color.clear
            }
        }
        .frame(width: 26, height: 26)
    }
}

#Preview {
    CoachView()
        .environmentObject(AppState())
}
