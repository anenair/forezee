// ============================================================
// WorkoutTabView.swift
// Forzee — Features/Workout
//
// The core gym-facing screen: generate today's workout, check
// off exercises as they're done (with a live Haiku "companion"
// comment after each), then log the session and get a Sonnet
// post-workout report. Replaces the Workout tab placeholder.
//
// MVP scope: completion is tracked per exercise, not per set —
// good enough for a first real-world gym test; per-set logging
// (actual reps/weight) is a natural next iteration.
// ============================================================

import SwiftUI

struct WorkoutTabView: View {

    @EnvironmentObject private var appState: AppState

    @State private var workout: GeneratedWorkout?
    @State private var completedExerciseIds: Set<UUID> = []
    @State private var companionComment: String?
    @State private var report: String?

    @State private var isGenerating = false
    @State private var isFinishing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: ForzeeSpacing.sectionGap) {
                        if let workout {
                            workoutCard(workout)
                        } else {
                            emptyState
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.fzBody(13))
                                .foregroundStyle(Color.fzPink)
                        }
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
            .navigationTitle("Workout")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ForzeeSpacing.itemGap) {
            Text("No workout yet today.")
                .font(.fzBody(15))
                .foregroundStyle(Color.fzTextSecondary)
            ForzeeButton(title: "Generate Today's Workout", isLoading: isGenerating, action: generate)
        }
        .padding(.top, ForzeeSpacing.sectionGap)
    }

    // MARK: - Workout Card

    private func workoutCard(_ workout: GeneratedWorkout) -> some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text(workout.name)
                .font(.fzHeading(22, weight: .bold))
                .foregroundStyle(Color.fzText)

            HStack(spacing: 16) {
                Label("\(workout.estimatedDurationMins) min", systemImage: "clock")
                Label(workout.workoutType.capitalized, systemImage: "figure.strengthtraining.traditional")
            }
            .font(.fzBody(12))
            .foregroundStyle(Color.fzTextSecondary)

            if let note = workout.coachingNote {
                Text(note)
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fzPrimaryDim)
                    .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
            }

            VStack(spacing: ForzeeSpacing.itemGap) {
                ForEach(workout.exercises) { exercise in
                    ExerciseRow(
                        exercise: exercise,
                        isCompleted: completedExerciseIds.contains(exercise.id)
                    ) {
                        toggle(exercise)
                    }
                }
            }

            if let companionComment {
                Text(companionComment)
                    .font(.fzBody(13, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.fzPrimary)
                    .transition(.opacity)
            }

            if let report {
                Text(report)
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fzSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
            } else {
                ForzeeButton(
                    title: "Finish Workout",
                    action: { Task { await finish(workout) } },
                    isDisabled: completedExerciseIds.isEmpty,
                    isLoading: isFinishing
                )
                ForzeeTextButton(title: "Discard & Start Over", action: reset)
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func toggle(_ exercise: WorkoutExercise) {
        let wasCompleted = completedExerciseIds.contains(exercise.id)
        if wasCompleted {
            completedExerciseIds.remove(exercise.id)
        } else {
            completedExerciseIds.insert(exercise.id)
            fetchCompanionComment(for: exercise)
        }
    }

    private func fetchCompanionComment(for exercise: WorkoutExercise) {
        guard let userId = appState.userId else { return }
        let fitnessLevel = appState.userProfile?.fitnessLevel ?? "novice"
        companionComment = nil

        Task {
            let comment = try? await KaiEngine.shared.generateGymCompanionComment(
                userId: userId,
                exerciseName: exercise.name,
                fitnessLevel: fitnessLevel
            )
            withAnimation { companionComment = comment }
        }
    }

    private func generate() {
        guard let userId = appState.userId else { return }
        isGenerating = true
        errorMessage = nil

        Task {
            defer { isGenerating = false }
            do {
                workout = try await KaiEngine.shared.generateWorkout(userId: userId)
                completedExerciseIds = []
                companionComment = nil
                report = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finish(_ workout: GeneratedWorkout) async {
        guard let userId = appState.userId else { return }
        isFinishing = true
        defer { isFinishing = false }

        let completedNames = workout.exercises
            .filter { completedExerciseIds.contains($0.id) }
            .map(\.name)

        try? await ForzeeDataService.shared.saveCompletedWorkout(
            workout,
            completedExerciseIds: completedExerciseIds,
            userId: userId
        )

        do {
            report = try await KaiEngine.shared.generateWorkoutReport(
                userId: userId,
                workout: workout,
                completedExerciseNames: completedNames
            )
        } catch {
            report = "Workout logged. (Report unavailable: \(error.localizedDescription))"
        }
    }

    private func reset() {
        workout = nil
        completedExerciseIds = []
        companionComment = nil
        report = nil
        errorMessage = nil
    }
}

// MARK: - ExerciseRow

private struct ExerciseRow: View {
    let exercise: WorkoutExercise
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isCompleted ? Color.fzGreen : Color.fzBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.fzBody(15, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                        .strikethrough(isCompleted)
                    Text(setsRepsText)
                        .font(.fzMono(13))
                        .foregroundStyle(Color.fzTextSecondary)
                    if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.fzBody(12))
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private var setsRepsText: String {
        var text = "\(exercise.sets) × \(exercise.reps)"
        if let weight = exercise.weightKg {
            text += " · \(Int(weight))kg"
        }
        text += " · rest \(exercise.restSecs)s"
        return text
    }
}

#Preview {
    WorkoutTabView()
        .environmentObject(AppState())
}
