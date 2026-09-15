// ============================================================
// SessionDetailView.swift
// Forzee — Features/Progress
//
// The detailed log for one specific day's session — every exercise
// and set actually logged that day, in the order first performed.
// Reached by tapping a marked day on the Progress tab's Report
// calendar (see ReportsSection). Distinct from WorkoutDetailView,
// which shows a workout's history *across every time it's been
// repeated* rather than one day's own log.
// ============================================================

import SwiftUI

struct SessionDetailView: View {
    let session: SessionHistoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                headerCard
                exercisesCard
            }
            .padding(ForzeeSpacing.screenPadding)
        }
        .background(Color.fzBg.ignoresSafeArea())
        .navigationTitle(session.workout?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text(session.startedAt.formatted(date: .complete, time: .omitted))
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)

            HStack(spacing: 16) {
                if let mins = session.durationMins {
                    Label("\(mins) min", systemImage: "clock")
                }
                if session.totalVolumeKg > 0 {
                    Label("\(Int(session.totalVolumeKg)) kg vol", systemImage: "chart.bar.fill")
                }
                if let rating = session.rating {
                    Label("\(rating)/5", systemImage: "star.fill")
                }
            }
            .font(.fzBody(12))
            .foregroundStyle(Color.fzTextSecondary)
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzPrimaryDim)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
    }

    // MARK: - Exercises

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("Exercises")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            if groupedSets.isEmpty {
                Text("No sets were logged for this session.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(groupedSets, id: \.name) { group in
                        ExerciseLogCard(name: group.name, sets: group.sets)
                    }
                }
            }
        }
    }

    /// Grouped in the order each exercise first appears — sets_log is
    /// already chronological (see ForzeeDataService.saveCompletedWorkout),
    /// so the first appearance order is the order it was actually done in.
    private var groupedSets: [(name: String, sets: [SessionSetEntry])] {
        var order: [String] = []
        var byName: [String: [SessionSetEntry]] = [:]
        for set in session.setsLog {
            let name = set.exerciseName ?? "Exercise"
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(set)
        }
        return order.map { (name: $0, sets: byName[$0] ?? []) }
    }
}

// MARK: - ExerciseLogCard

private struct ExerciseLogCard: View {
    let name: String
    let sets: [SessionSetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)

            VStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text("Set \(set.setNumber ?? index + 1)")
                            .font(.fzMono(12))
                            .foregroundStyle(Color.fzTextSecondary)
                        Spacer()
                        Text(setText(set))
                            .font(.fzMono(12, weight: .medium))
                            .foregroundStyle(Color.fzText)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private func setText(_ set: SessionSetEntry) -> String {
        var text = ""
        if let weight = set.weightKg {
            text = "\(formattedNumber(weight)) kg"
        }
        if let reps = set.reps {
            text += text.isEmpty ? "\(reps) reps" : " × \(reps)"
        }
        return text.isEmpty ? "—" : text
    }

    private func formattedNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: SessionHistoryEntry(
            id: "preview",
            workoutId: nil,
            startedAt: .now,
            completedAt: nil,
            durationMins: 45,
            setsLog: [],
            rating: 4,
            workout: nil
        ))
    }
}
