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

    @State private var briefing: String?
    @State private var isLoadingBriefing = false
    @State private var messages: [KaiMessage] = []
    @State private var draftMessage: String = ""
    @State private var streamingReply: String = ""
    @State private var errorMessage: String?

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

                    inputBar
                }
            }
            .navigationTitle("Coach")
        }
        .task { await loadBriefing() }
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

            Button(action: send) {
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
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !kaiEngine.isResponding
    }

    private func send() {
        guard let userId = appState.userId else { return }
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

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
                    }
                )
            } catch {
                errorMessage = error.localizedDescription
                streamingReply = ""
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
