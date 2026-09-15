// ============================================================
// WorkoutDetailView.swift
// Forzee — Features/Progress
//
// One generated workout's full history — every session that used
// it, and how the numbers moved across repeats. "Times used" here
// is exact (a full fetchSessionsForWorkout, no window limit),
// unlike the approximate count shown inline on the Log feed's
// history rows.
//
// "Repeat This Workout" is the other half of the mechanism: it
// reuses the same workout row (via WorkoutSessionManager's isRepeat
// flag) rather than generating a new one, which is what lets a real
// times-used count exist at all — see
// ForzeeDataService.saveCompletedWorkout.
// ============================================================

import SwiftUI

struct WorkoutDetailView: View {

    let workoutId: String
    let userId: String?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [SessionHistoryEntry] = []
    @State private var isLoading = true

    /// Sessions come back newest-first.
    private var latest: SessionHistoryEntry? { sessions.first }
    private var earliest: SessionHistoryEntry? { sessions.last }

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.fzPrimary)
            } else if sessions.isEmpty {
                Text("Couldn't load this workout's history.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else {
                ScrollView {
                    VStack(spacing: ForzeeSpacing.sectionGap) {
                        headerCard
                        impactCard
                        historyCard
                        ForzeeButton(title: "Repeat This Workout", action: repeatWorkout)
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
        }
        .navigationTitle(latest?.workout?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text(latest?.workout?.name ?? "Workout")
                .font(.fzHeading(20, weight: .bold))
                .foregroundStyle(Color.fzText)
            if let type = latest?.workout?.workoutType {
                Text(type.capitalized)
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }
            if let generatedAt = latest?.workout?.generatedAt {
                Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.fzBody(12))
                    .foregroundStyle(Color.fzTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Impact

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Impact")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            Text("Used \(sessions.count) time\(sessions.count == 1 ? "" : "s")")
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)

            if let volumeChangeText {
                Text(volumeChangeText)
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
            } else if sessions.count == 1 {
                Text("Repeat it to see how your numbers move over time.")
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzPrimaryDim)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
    }

    private var volumeChangeText: String? {
        guard sessions.count > 1, let earliest, let latest, earliest.totalVolumeKg > 0 else { return nil }
        let change = ((latest.totalVolumeKg - earliest.totalVolumeKg) / earliest.totalVolumeKg) * 100
        let direction = change >= 0 ? "up" : "down"
        return "Volume \(direction) \(abs(Int(change.rounded())))% since the first time"
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Every Time")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    HistoryRow(session: session, occurrence: sessions.count - index)
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let userId else { return }
        sessions = (try? await ForzeeDataService.shared.fetchSessionsForWorkout(workoutId: workoutId, userId: userId)) ?? []
    }

    private func repeatWorkout() {
        guard let workoutUUID = UUID(uuidString: workoutId),
              let info = latest?.workout,
              let exercises = info.exercises else { return }

        let workout = GeneratedWorkout(
            id: workoutUUID,
            name: info.name,
            workoutType: info.workoutType,
            estimatedDurationMins: info.estimatedDurationMins ?? 45,
            exercises: exercises,
            generatedAt: info.generatedAt ?? .now
        )
        WorkoutSessionManager.shared.start(workout, isRepeat: true)
        appState.activeTab = .workout
        dismiss()
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let session: SessionHistoryEntry
    /// 1 = first time it was ever done, counting up — sessions arrive
    /// newest-first, so this is (total count - position from the top).
    let occurrence: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time \(occurrence)")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzText)
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.fzBody(12))
                    .foregroundStyle(Color.fzTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if session.totalVolumeKg > 0 {
                    Text("\(Int(session.totalVolumeKg)) kg vol")
                        .font(.fzMono(12))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                if let mins = session.durationMins {
                    Text("\(mins) min")
                        .font(.fzMono(12))
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}
