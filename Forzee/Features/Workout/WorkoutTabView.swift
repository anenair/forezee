// ============================================================
// WorkoutTabView.swift
// Forzee — Features/Workout
//
// The core gym-facing screen: generate today's workout, check
// off exercises as they're done (with a live Haiku "companion"
// comment after each), then a final session save — effort, mood,
// rating, notes — that's the actual completion of the workout,
// followed by a best-effort Sonnet post-workout report. Replaces
// the Workout tab placeholder.
//
// The session save and the AI report are deliberately decoupled:
// the save always succeeds (local-first, see SyncManager) even
// with zero connectivity; the report needs a live network call and
// can fail without taking the save down with it.
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
    @State private var isSavingSession = false
    @State private var didSaveSession = false
    @State private var showFeedbackSheet = false
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
        .sheet(isPresented: $showFeedbackSheet) {
            if let workout {
                SessionFeedbackSheet(isSaving: isSavingSession) { feedback in
                    Task { await saveSession(workout, feedback: feedback) }
                }
            }
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

            if didSaveSession {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fzGreen)
                    Text("Session saved")
                        .font(.fzBody(13, weight: .semibold))
                        .foregroundStyle(Color.fzGreen)
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
                    ProgressView().tint(Color.fzPrimary)
                }

                ForzeeTextButton(title: "Start a New Workout", action: reset)
            } else {
                ForzeeButton(
                    title: "Finish Workout",
                    action: { showFeedbackSheet = true },
                    isDisabled: completedExerciseIds.isEmpty
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

    /// The final save. Always succeeds locally regardless of connectivity
    /// (see SyncManager) — that's what "Session saved" reflects, immediately,
    /// before the AI report (which does need a live network call) resolves.
    private func saveSession(_ workout: GeneratedWorkout, feedback: SessionFeedback) async {
        guard let userId = appState.userId else { return }
        isSavingSession = true

        let completedNames = workout.exercises
            .filter { completedExerciseIds.contains($0.id) }
            .map(\.name)

        try? await ForzeeDataService.shared.saveCompletedWorkout(
            workout,
            completedExerciseIds: completedExerciseIds,
            feedback: feedback,
            userId: userId
        )

        isSavingSession = false
        showFeedbackSheet = false
        didSaveSession = true

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
        didSaveSession = false
        errorMessage = nil
    }
}

// MARK: - SessionFeedbackSheet

private struct SessionFeedbackSheet: View {
    let isSaving: Bool
    let onSave: (SessionFeedback) -> Void

    @State private var mood: SessionFeedback.Mood?
    @State private var perceivedEffort: Double = 5
    @State private var rating: Int = 0
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                        moodPicker
                        effortSlider
                        ratingStars
                        notesField
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
            .navigationTitle("How'd it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSave(.empty) }.foregroundStyle(Color.fzTextSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ForzeeButton(title: "Save Session", isLoading: isSaving) {
                    onSave(SessionFeedback(
                        perceivedEffort: Int(perceivedEffort),
                        mood: mood,
                        notes: notes,
                        rating: rating > 0 ? rating : nil
                    ))
                }
                .padding(ForzeeSpacing.screenPadding)
                .background(Color.fzBg)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("How did you feel?")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(SessionFeedback.Mood.allCases) { option in
                    Button {
                        mood = (mood == option) ? nil : option
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: option.iconSystemName)
                                .font(.system(size: 18))
                            Text(option.label)
                                .font(.fzBody(10))
                        }
                        .foregroundStyle(mood == option ? Color(hex: "0A0A0F") : Color.fzTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mood == option ? Color.fzPrimary : Color.fzSurface)
                        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var effortSlider: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            HStack {
                Text("Effort")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Int(perceivedEffort))/10")
                    .font(.fzMono(13))
                    .foregroundStyle(Color.fzText)
            }
            Slider(value: $perceivedEffort, in: 1...10, step: 1)
                .tint(Color.fzPrimary)
        }
    }

    private var ratingStars: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Rate this session")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = (rating == star) ? 0 : star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(star <= rating ? Color.fzPrimary : Color.fzBorder)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Notes")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            TextField("Optional", text: $notes, axis: .vertical)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzText)
                .padding(12)
                .background(Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                .lineLimit(2...5)
        }
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
