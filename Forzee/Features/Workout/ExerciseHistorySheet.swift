// ============================================================
// ExerciseHistorySheet.swift
// Forzee — Features/Workout
//
// Roadmap Phase 1 "Per-exercise history" — tapping the clock icon
// on an ExerciseRow shows that exercise's own trend: its top set
// from each recent session it appeared in. Reads the same
// fetchSessionHistory the Progress tab's Log feed uses and filters
// client-side by exercise name — no bespoke per-exercise query.
// ============================================================

import SwiftUI

struct ExerciseHistorySheet: View {

    let userId: String?
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss

    @State private var topSets: [ExerciseTopSet] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Color.fzPrimary)
                } else if topSets.isEmpty {
                    Text("No history yet for \(exerciseName) — log a set here and it'll show up next time.")
                        .font(.fzBody(14))
                        .foregroundStyle(Color.fzTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(ForzeeSpacing.screenPadding)
                } else {
                    ScrollView {
                        VStack(spacing: ForzeeSpacing.smallGap) {
                            ForEach(Array(topSets.enumerated()), id: \.offset) { _, entry in
                                row(entry)
                            }
                        }
                        .padding(ForzeeSpacing.screenPadding)
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.fzTextSecondary)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ entry: ExerciseTopSet) -> some View {
        HStack {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)
            Spacer()
            Text(topSetText(entry))
                .font(.fzMono(13, weight: .semibold))
                .foregroundStyle(Color.fzText)
        }
        .padding(12)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private func topSetText(_ entry: ExerciseTopSet) -> String {
        var text = ""
        if let weight = entry.weightKg {
            text = "\(formatted(weight)) kg"
        }
        if let reps = entry.reps {
            text += text.isEmpty ? "\(reps) reps" : " × \(reps)"
        }
        return text.isEmpty ? "Logged — no weight or reps recorded" : text
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Best set per session — highest weight, ties broken by reps — across
    /// the last 30 sessions that included this exercise, newest first
    /// (fetchSessionHistory already orders that way).
    private func load() async {
        defer { isLoading = false }
        guard let userId else { return }
        let sessions = (try? await ForzeeDataService.shared.fetchSessionHistory(userId: userId, limit: 30)) ?? []
        topSets = sessions.compactMap { session -> ExerciseTopSet? in
            let sets = session.setsLog.filter { $0.exerciseName == exerciseName }
            guard let top = sets.max(by: {
                (($0.weightKg ?? 0), ($0.reps ?? 0)) < (($1.weightKg ?? 0), ($1.reps ?? 0))
            }) else { return nil }
            return ExerciseTopSet(date: session.startedAt, weightKg: top.weightKg, reps: top.reps)
        }
    }
}

private struct ExerciseTopSet {
    let date: Date
    let weightKg: Double?
    let reps: Int?
}

#Preview {
    ExerciseHistorySheet(userId: nil, exerciseName: "Flat Barbell Bench Press")
}
