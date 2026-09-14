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
// Voice logging: "Hi Kai, mark a set complete, 135 lbs, 8 reps" /
// "same as previous" / "what's my next exercise" / "how am I doing".
// Real LLM understanding, not pattern matching — a single Haiku
// tool-use call (KaiEngine.interpretWorkoutVoiceCommand) classifies
// the intent and extracts weight/reps in one round-trip. Genuinely
// open-ended questions escalate to a full Sonnet chat call. Exercise
// completion still also works by tapping a row; voice adds real
// per-set weight/reps on top of that.
// ============================================================

import SwiftUI

struct WorkoutTabView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var voiceManager = VoiceManager.shared
    @ObservedObject private var voiceSynthesizer = KaiVoiceSynthesizer.shared
    @ObservedObject private var syncManager = SyncManager.shared

    @State private var workout: GeneratedWorkout?
    @State private var completedExerciseIds: Set<UUID> = []
    @State private var loggedSets: [LoggedSet] = []
    @State private var companionComment: String?
    @State private var report: String?

    @State private var isGenerating = false
    @State private var isSavingSession = false
    @State private var didSaveSession = false
    @State private var showFeedbackSheet = false
    @State private var isVoiceModeOn = false
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

                        if isVoiceModeOn {
                            voiceStatusBar
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
            .toolbar {
                if workout != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: toggleVoiceMode) {
                            Image(systemName: isVoiceModeOn ? "mic.fill" : "mic")
                                .foregroundStyle(isVoiceModeOn ? Color.fzPrimary : Color.fzTextSecondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFeedbackSheet) {
            if let workout {
                SessionFeedbackSheet(isSaving: isSavingSession) { feedback in
                    Task { await saveSession(workout, feedback: feedback) }
                }
            }
        }
        .onDisappear { stopVoiceMode() }
        .onAppear {
            // Picks up a workout the Coach chat's "Build Workout" button just
            // created, since that sets AppState.activeWorkout rather than this
            // view's own local state.
            if workout == nil, let active = appState.activeWorkout {
                workout = active
                completedExerciseIds = []
                loggedSets = []
                companionComment = nil
                report = nil
            }
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
    }

    private var voiceStatusText: String {
        if voiceSynthesizer.isSpeaking { return "Kai is speaking..." }
        // Connection can drop mid-workout even if it was fine when voice mode
        // started — surface that instead of letting commands fail silently.
        if !syncManager.isOnline { return "No connection — voice commands need one right now." }
        switch voiceManager.state {
        case .idle:                return "Voice mode on — say \"Hi Kai\""
        case .listeningForWake:    return "Listening for \"Hi Kai\"..."
        case .listeningForCommand: return voiceManager.liveTranscript.isEmpty
            ? "Go ahead — \"mark a set complete\", \"what's next\", \"how am I doing\"..."
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
            handleVoiceCommand(command)
        }
    }

    /// Real LLM understanding — no local pattern matching. A single Haiku
    /// tool-use call classifies the intent AND extracts weight/reps in one
    /// round-trip (see KaiEngine.interpretWorkoutVoiceCommand); genuinely
    /// open-ended questions escalate to a full Sonnet chat call.
    private func handleVoiceCommand(_ command: String) {
        guard let userId = appState.userId else {
            speak("You need to be signed in for that.")
            return
        }
        Task {
            do {
                let result = try await KaiEngine.shared.interpretWorkoutVoiceCommand(
                    userId: userId,
                    transcript: command,
                    state: currentVoiceState()
                )
                switch result.action {
                case .logSet:
                    applyLogSet(result)
                case .nextExercise, .progress:
                    speak(result.spokenReply)
                case .chat:
                    askKai(command)
                }
            } catch {
                // The command reached here, so voice mode was on when we
                // started — but a live network call is what actually failed,
                // and "I couldn't understand that" would misattribute a
                // dead connection to bad speech recognition.
                if syncManager.isOnline {
                    speak("I couldn't understand that — try again.")
                } else {
                    stopVoiceMode()
                    errorMessage = "Lost connection — voice mode needs one. Your logged sets are still saved."
                }
            }
        }
    }

    private func speak(_ text: String) {
        voiceSynthesizer.speak(text, isPremium: appState.subscriptionTier.isPremium) {
            listenForWakePhrase()
        }
    }

    private func askKai(_ command: String) {
        guard let userId = appState.userId else {
            speak("You need to be signed in for that.")
            return
        }
        Task {
            do {
                try await KaiEngine.shared.chat(
                    message: command,
                    userId: userId,
                    history: [],
                    onToken: { _ in },
                    onComplete: { reply in speak(reply.content) }
                )
            } catch {
                speak("I couldn't get an answer to that — try again in the Coach tab.")
            }
        }
    }

    // MARK: - Voice Commands

    private var currentExercise: WorkoutExercise? {
        workout?.exercises.first { !completedExerciseIds.contains($0.id) }
    }

    private func sets(for exerciseId: UUID) -> [LoggedSet] {
        loggedSets.filter { $0.exerciseId == exerciseId }.sorted { $0.setNumber < $1.setNumber }
    }

    /// A compact snapshot of where things stand, handed to Claude so it can
    /// resolve "same as previous" / "what's next" / "how am I doing" against
    /// real state instead of guessing.
    private func currentVoiceState() -> WorkoutVoiceState {
        let totalExercises = workout?.exercises.count ?? 0

        guard let exercise = currentExercise else {
            return WorkoutVoiceState(
                currentExerciseName: nil,
                currentExercisePrescription: nil,
                setsLoggedForCurrent: 0,
                totalSetsForCurrent: nil,
                lastLoggedSetDescription: nil,
                remainingExerciseNames: [],
                totalExercises: totalExercises,
                completedExercises: completedExerciseIds.count
            )
        }

        let existing = sets(for: exercise.id)
        let remaining = workout?.exercises
            .filter { $0.id != exercise.id && !completedExerciseIds.contains($0.id) }
            .map(\.name) ?? []

        return WorkoutVoiceState(
            currentExerciseName: exercise.name,
            currentExercisePrescription: "\(exercise.sets) sets of \(exercise.reps)",
            setsLoggedForCurrent: existing.count,
            totalSetsForCurrent: exercise.sets,
            lastLoggedSetDescription: existing.last.map(describe),
            remainingExerciseNames: remaining,
            totalExercises: totalExercises,
            completedExercises: completedExerciseIds.count
        )
    }

    private func describe(_ set: LoggedSet) -> String {
        var text = ""
        if let weight = set.weightValue, let unit = set.weightUnit {
            text = "\(formatted(weight)) \(unit.spokenName)"
        }
        if let reps = set.reps {
            text += text.isEmpty ? "\(reps) reps" : ", \(reps) reps"
        }
        return text.isEmpty ? "no weight or reps recorded" : text
    }

    /// Applies the structured decision to actual state — this is normal app
    /// logic reacting to a parsed command, the same as any voice-assistant
    /// integration, not a return to pattern matching (the understanding
    /// itself happened in interpretWorkoutVoiceCommand). "Same as previous"
    /// and the prescribed-weight fallback are resolved here rather than
    /// trusted blind from the model, since this is the data that gets saved.
    private func applyLogSet(_ result: WorkoutVoiceCommandResult) {
        guard let exercise = currentExercise else {
            speak("You've already finished every exercise in this workout.")
            return
        }

        let existing = sets(for: exercise.id)
        let setNumber = existing.count + 1

        var weightValue = result.weightValue
        var weightUnit = result.weightUnit
        var reps = result.reps

        if result.sameAsPrevious, let last = existing.last {
            weightValue = weightValue ?? last.weightValue
            weightUnit = weightUnit ?? last.weightUnit
            reps = reps ?? last.reps
        }
        if weightValue == nil, let prescribed = exercise.weightKg {
            weightValue = prescribed
            weightUnit = .kg
        }

        loggedSets.append(LoggedSet(
            exerciseId: exercise.id,
            setNumber: setNumber,
            weightValue: weightValue,
            weightUnit: weightUnit,
            reps: reps
        ))

        if setNumber >= exercise.sets {
            completedExerciseIds.insert(exercise.id)
            fetchCompanionComment(for: exercise)
        }

        speak(result.spokenReply.isEmpty ? "Set \(setNumber) logged for \(exercise.name)." : result.spokenReply)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ForzeeSpacing.itemGap) {
            Text("No workout yet today.")
                .font(.fzBody(15))
                .foregroundStyle(Color.fzTextSecondary)

            if !syncManager.isOnline {
                ConnectivityNotice(message: "No connection — Kai needs one to generate a workout.")
            } else {
                ForzeeButton(title: "Generate Today's Workout", action: generate, isLoading: isGenerating)
            }
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
                        isCompleted: completedExerciseIds.contains(exercise.id),
                        loggedSets: sets(for: exercise.id),
                        onToggle: { toggle(exercise) },
                        onLogSet: { setNumber, weight, unit, reps, restSecs in
                            logSet(
                                exercise: exercise, setNumber: setNumber,
                                weight: weight, unit: unit, reps: reps, restSecs: restSecs
                            )
                        },
                        onRemoveSet: { setNumber in removeSet(exercise: exercise, setNumber: setNumber) }
                    )
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

    /// Manual per-set entry from ExerciseRow's expanded editor — the tap
    /// alternative to voice logging. Upserts by (exercise, setNumber) so
    /// editing an already-logged set overwrites it rather than duplicating.
    private func logSet(
        exercise: WorkoutExercise,
        setNumber: Int,
        weight: Double?,
        unit: WeightUnit,
        reps: Int?,
        restSecs: Int?
    ) {
        if let index = loggedSets.firstIndex(where: { $0.exerciseId == exercise.id && $0.setNumber == setNumber }) {
            loggedSets[index].weightValue = weight
            loggedSets[index].weightUnit = weight == nil ? nil : unit
            loggedSets[index].reps = reps
            loggedSets[index].restSecs = restSecs
        } else {
            loggedSets.append(LoggedSet(
                exerciseId: exercise.id,
                setNumber: setNumber,
                weightValue: weight,
                weightUnit: weight == nil ? nil : unit,
                reps: reps,
                restSecs: restSecs
            ))
        }

        let alreadyCompleted = completedExerciseIds.contains(exercise.id)
        if !alreadyCompleted, sets(for: exercise.id).count >= exercise.sets {
            completedExerciseIds.insert(exercise.id)
            fetchCompanionComment(for: exercise)
        }
    }

    private func removeSet(exercise: WorkoutExercise, setNumber: Int) {
        loggedSets.removeAll { $0.exerciseId == exercise.id && $0.setNumber == setNumber }
        completedExerciseIds.remove(exercise.id)
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
                appState.activeWorkout = workout
                completedExerciseIds = []
                loggedSets = []
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
            loggedSets: loggedSets,
            feedback: feedback,
            userId: userId
        )

        isSavingSession = false
        showFeedbackSheet = false
        didSaveSession = true
        appState.activeWorkout = nil  // completed — no longer "active"

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
        appState.activeWorkout = nil
        completedExerciseIds = []
        loggedSets = []
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
                ForzeeButton(
                    title: "Save Session",
                    action: {
                        onSave(SessionFeedback(
                            perceivedEffort: Int(perceivedEffort),
                            mood: mood,
                            notes: notes,
                            rating: rating > 0 ? rating : nil
                        ))
                    },
                    isLoading: isSaving
                )
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
    let loggedSets: [LoggedSet]
    let onToggle: () -> Void
    let onLogSet: (Int, Double?, WeightUnit, Int?, Int?) -> Void  // setNumber, weight, unit, reps, restSecs
    let onRemoveSet: (Int) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isCompleted ? Color.fzGreen : Color.fzBorder)
                }
                .buttonStyle(.plain)

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

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fzTextSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(1...max(exercise.sets, 1), id: \.self) { setNumber in
                        SetInputRow(
                            setNumber: setNumber,
                            prescribedReps: exercise.reps,
                            prescribedRestSecs: exercise.restSecs,
                            logged: loggedSets.first { $0.setNumber == setNumber },
                            onSave: { weight, unit, reps, rest in
                                onLogSet(setNumber, weight, unit, reps, rest)
                            },
                            onClear: { onRemoveSet(setNumber) }
                        )
                    }
                }
                .padding(.leading, 32)
            } else if !loggedSets.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(loggedSets) { set in
                        Text(loggedSetText(set))
                            .font(.fzMono(12))
                            .foregroundStyle(Color.fzPrimary)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(12)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private func loggedSetText(_ set: LoggedSet) -> String {
        var text = "Set \(set.setNumber):"
        if let weight = set.weightValue, let unit = set.weightUnit {
            let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weight)) : String(format: "%.1f", weight)
            text += " \(formatted) \(unit.rawValue)"
        }
        if let reps = set.reps {
            text += " × \(reps)"
        }
        if let rest = set.restSecs {
            text += " · rest \(rest)s"
        }
        return text
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

// MARK: - SetInputRow

/// One editable set within an expanded ExerciseRow — weight, reps, and rest,
/// all overridable regardless of what was prescribed. The tap alternative to
/// voice logging ("Hi Kai, mark a set complete, 135 lbs, 8 reps").
private struct SetInputRow: View {
    let setNumber: Int
    let prescribedReps: String
    let prescribedRestSecs: Int
    let logged: LoggedSet?
    let onSave: (Double?, WeightUnit, Int?, Int?) -> Void
    let onClear: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var restText = ""
    @State private var unit: WeightUnit = .lbs

    private var isLogged: Bool { logged != nil }

    var body: some View {
        HStack(spacing: 6) {
            Text("Set \(setNumber)")
                .font(.fzMono(11, weight: .medium))
                .foregroundStyle(Color.fzTextSecondary)
                .frame(width: 40, alignment: .leading)

            fieldBox(text: $weightText, placeholder: "wt", keyboard: .decimalPad, width: 44)

            Picker("", selection: $unit) {
                Text("lbs").tag(WeightUnit.lbs)
                Text("kg").tag(WeightUnit.kg)
            }
            .pickerStyle(.menu)
            .font(.fzBody(11))
            .tint(Color.fzTextSecondary)
            .frame(width: 50)

            Text("×")
                .font(.fzBody(12))
                .foregroundStyle(Color.fzTextSecondary)

            fieldBox(text: $repsText, placeholder: prescribedReps, keyboard: .numberPad, width: 36)

            Text("rest")
                .font(.fzBody(11))
                .foregroundStyle(Color.fzTextSecondary)

            fieldBox(text: $restText, placeholder: "\(prescribedRestSecs)", keyboard: .numberPad, width: 36)

            Text("s")
                .font(.fzBody(11))
                .foregroundStyle(Color.fzTextSecondary)

            Spacer(minLength: 4)

            if isLogged {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: save) {
                Image(systemName: isLogged ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isLogged ? Color.fzGreen : Color.fzPrimary)
            }
            .buttonStyle(.plain)
        }
        .onAppear(perform: loadFromLogged)
        .onChange(of: logged) { _, _ in loadFromLogged() }
    }

    private func fieldBox(text: Binding<String>, placeholder: String, keyboard: UIKeyboardType, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.fzMono(13))
            .foregroundStyle(Color.fzText)
            .frame(width: width)
            .padding(.vertical, 6)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private func loadFromLogged() {
        weightText = logged?.weightValue.map(formatted) ?? ""
        repsText = logged?.reps.map(String.init) ?? ""
        restText = logged?.restSecs.map(String.init) ?? ""
        unit = logged?.weightUnit ?? .lbs
    }

    private func save() {
        onSave(Double(weightText), unit, Int(repsText), Int(restText))
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    WorkoutTabView()
        .environmentObject(AppState())
}
