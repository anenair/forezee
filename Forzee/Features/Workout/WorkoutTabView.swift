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
    @ObservedObject private var sessionManager = WorkoutSessionManager.shared
    @ObservedObject private var voiceManager = VoiceManager.shared
    @ObservedObject private var voiceSynthesizer = KaiVoiceSynthesizer.shared
    @ObservedObject private var syncManager = SyncManager.shared

    @State private var companionComment: String?
    @State private var report: String?

    @State private var isGenerating = false
    @State private var isSavingSession = false
    @State private var showFeedbackSheet = false
    @State private var isVoiceModeOn = false
    @State private var errorMessage: String?
    @State private var showEmptySessionGuard = false
    @State private var showPlateCalculator = false
    @State private var showAddExercise = false
    @State private var historyExercise: WorkoutExercise?

    // Rest timer — foreground countdown lives here; the background half
    // (a local notification if the app gets backgrounded mid-rest) is
    // NotificationManager.scheduleRestTimerAlert.
    @State private var restTimerEndDate: Date?
    @State private var restTimerTotalSecs: Int = 0

    // PR announcement — a transient toast. The PR *check* itself lives in
    // WorkoutSessionManager (isPersonalRecord), against the same frozen
    // personalBests baseline it loads; this is only the "show it, then
    // fade it out" UI reaction to a true result.
    @State private var prAnnouncement: String?

    /// Tracks which workout this view has already synced its own
    /// UI-only state against — a workout can become active from three
    /// different places (this view's own Generate, Coach chat's Build
    /// Workout, or "Repeat This Workout" from a past session), and
    /// whichever one it was, this view still needs to reset its
    /// companion-comment/report state and load a personal-bests baseline
    /// exactly once for it. See `syncIfNewWorkout`.
    @State private var syncedWorkoutId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: ForzeeSpacing.sectionGap) {
                        if let restTimerEndDate {
                            RestTimerBanner(
                                endDate: restTimerEndDate,
                                totalSecs: restTimerTotalSecs,
                                onDone: { self.restTimerEndDate = nil },
                                onSkip: cancelRestTimer
                            )
                        }

                        if let workout = sessionManager.workout {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showPlateCalculator = true }) {
                        Image(systemName: "scalemass")
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }
                if sessionManager.workout != nil {
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
            if sessionManager.workout != nil {
                SessionFeedbackSheet(isSaving: isSavingSession) { feedback in
                    Task { await saveSession(feedback: feedback) }
                }
            }
        }
        .sheet(isPresented: $showPlateCalculator) {
            PlateCalculatorSheet()
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(onAdd: addExercise)
        }
        .sheet(item: $historyExercise) { exercise in
            ExerciseHistorySheet(userId: appState.userId, exerciseName: exercise.name)
        }
        .alert("No sets logged", isPresented: $showEmptySessionGuard) {
            Button("Resume Workout", role: .cancel) {}
            Button("Discard Workout", role: .destructive) { reset() }
        } message: {
            Text("You haven't logged any sets yet — finishing now would only save the exercises you checked off, not real weights or reps.")
        }
        .onDisappear { stopVoiceMode() }
        .onAppear { syncIfNewWorkout() }
        .onChange(of: sessionManager.workout?.id) { _, _ in syncIfNewWorkout() }
    }

    /// A workout becoming active — from this view's own Generate, from
    /// Coach chat's Build Workout, or from "Repeat This Workout" — always
    /// needs the same two things done once: reset this view's own
    /// companion-comment/report/error state, and load a fresh
    /// personal-bests baseline to check future sets against. Runs at most
    /// once per workout id, whether this view was already open when the
    /// workout started or just appeared afterward.
    private func syncIfNewWorkout() {
        guard sessionManager.workout?.id != syncedWorkoutId else { return }
        syncedWorkoutId = sessionManager.workout?.id
        companionComment = nil
        report = nil
        errorMessage = nil
        guard sessionManager.workout != nil, let userId = appState.userId else { return }
        Task { await sessionManager.loadPersonalBests(userId: userId) }
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
                    state: sessionManager.currentContext()
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

    /// Applies the structured decision via WorkoutSessionManager — the
    /// resolution logic itself ("same as previous," the prescribed-weight
    /// fallback, marking the exercise complete on the last set) lives
    /// there now, shared with manual entry and, eventually, Coach chat's
    /// log_set. This is just the voice-specific reaction to the outcome:
    /// speaking a confirmation, starting the rest timer, checking for a PR.
    private func applyLogSet(_ result: WorkoutVoiceCommandResult) {
        guard let outcome = sessionManager.logNextSet(
            weightValue: result.weightValue,
            weightUnit: result.weightUnit,
            reps: result.reps,
            sameAsPrevious: result.sameAsPrevious
        ) else {
            speak("You've already finished every exercise in this workout.")
            return
        }

        if outcome.exerciseJustCompleted {
            fetchCompanionComment(for: outcome.exercise)
        }
        if let weightValue = outcome.weightValue, let weightUnit = outcome.weightUnit, let reps = outcome.reps {
            checkForPR(exerciseName: outcome.exercise.name, weight: weightValue, unit: weightUnit, reps: reps)
        }
        startRestTimer(seconds: outcome.restSecs ?? outcome.exercise.restSecs)

        speak(result.spokenReply.isEmpty ? "Set \(outcome.setNumber) logged for \(outcome.exercise.name)." : result.spokenReply)
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
                        isCompleted: sessionManager.completedExerciseIds.contains(exercise.id),
                        loggedSets: sessionManager.sets(for: exercise.id),
                        onToggle: { toggle(exercise) },
                        onLogSet: { setNumber, weight, unit, reps, restSecs in
                            logSet(
                                exercise: exercise, setNumber: setNumber,
                                weight: weight, unit: unit, reps: reps, restSecs: restSecs
                            )
                        },
                        onRemoveSet: { setNumber in removeSet(exercise: exercise, setNumber: setNumber) },
                        onShowHistory: { historyExercise = exercise }
                    )
                }

                if !sessionManager.isFinished {
                    ForzeeTextButton(title: "+ Add Exercise", action: { showAddExercise = true })
                }
            }

            if let prAnnouncement {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").foregroundStyle(Color.fzPrimary)
                    Text(prAnnouncement)
                        .font(.fzBody(13, weight: .semibold))
                        .foregroundStyle(Color.fzPrimary)
                }
                .transition(.opacity)
            }

            if let companionComment {
                Text(companionComment)
                    .font(.fzBody(13, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.fzPrimary)
                    .transition(.opacity)
            }

            if sessionManager.isFinished {
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
                    action: finishOrGuard,
                    isDisabled: sessionManager.completedExerciseIds.isEmpty
                )
                ForzeeTextButton(title: "Discard & Start Over", action: discardOrGuard)
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
        if sessionManager.toggleExerciseComplete(exercise.id) {
            fetchCompanionComment(for: exercise)
        }
    }

    /// Manual per-set entry from ExerciseRow's expanded editor — the tap
    /// alternative to voice logging. The upsert-by-(exercise, setNumber)
    /// and complete-on-last-set logic both live in WorkoutSessionManager
    /// now, shared with voice's applyLogSet; this just reacts to the
    /// outcome the same way applyLogSet does, minus the spoken confirmation.
    private func logSet(
        exercise: WorkoutExercise,
        setNumber: Int,
        weight: Double?,
        unit: WeightUnit,
        reps: Int?,
        restSecs: Int?
    ) {
        guard let outcome = sessionManager.logSet(
            exerciseId: exercise.id, setNumber: setNumber,
            weight: weight, unit: unit, reps: reps, restSecs: restSecs
        ) else { return }

        if outcome.exerciseJustCompleted {
            fetchCompanionComment(for: exercise)
        }
        if let weight, let reps {
            checkForPR(exerciseName: exercise.name, weight: weight, unit: unit, reps: reps)
        }
        startRestTimer(seconds: restSecs ?? exercise.restSecs)
    }

    private func removeSet(exercise: WorkoutExercise, setNumber: Int) {
        sessionManager.removeSet(exerciseId: exercise.id, setNumber: setNumber)
    }

    // MARK: - Add Exercise

    private func addExercise(_ exercise: WorkoutExercise) {
        sessionManager.addExercise(exercise)
    }

    // MARK: - Rest Timer

    private func startRestTimer(seconds: Int) {
        guard seconds > 0 else { return }
        restTimerTotalSecs = seconds
        restTimerEndDate = Date().addingTimeInterval(TimeInterval(seconds))
        NotificationManager.shared.scheduleRestTimerAlert(seconds: seconds)
    }

    private func cancelRestTimer() {
        restTimerEndDate = nil
        NotificationManager.shared.cancelRestTimerAlert()
    }

    // MARK: - PR Detection

    /// The comparison itself lives in WorkoutSessionManager, against the
    /// frozen personalBests baseline it loads once per session; this is
    /// only the "show a toast, then fade it out" UI reaction to a true result.
    private func checkForPR(exerciseName: String, weight: Double, unit: WeightUnit, reps: Int) {
        guard sessionManager.isPersonalRecord(exerciseName: exerciseName, weight: weight, unit: unit, reps: reps) else { return }

        withAnimation { prAnnouncement = "New PR on \(exerciseName)!" }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { prAnnouncement = nil }
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
                let workout = try await KaiEngine.shared.generateWorkout(userId: userId)
                sessionManager.start(workout)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The final save. Always succeeds locally regardless of connectivity
    /// (see SyncManager) — that's what "Session saved" reflects, immediately,
    /// before the AI report (which does need a live network call) resolves.
    private func saveSession(feedback: SessionFeedback) async {
        guard let userId = appState.userId else { return }
        isSavingSession = true

        guard let finished = try? await sessionManager.finish(userId: userId, feedback: feedback) else {
            isSavingSession = false
            errorMessage = "Couldn't save this session — try again."
            return
        }

        isSavingSession = false
        showFeedbackSheet = false

        do {
            report = try await KaiEngine.shared.generateWorkoutReport(
                userId: userId,
                workout: finished.workout,
                completedExerciseNames: finished.completedExerciseNames
            )
        } catch {
            report = "Workout logged. (Report unavailable: \(error.localizedDescription))"
        }
    }

    /// Cheap insurance against a stray tap: toggling exercises "complete"
    /// with no real weight/reps behind them (see the ExerciseRow checkbox)
    /// would otherwise let Finish silently save a session made entirely of
    /// saveCompletedWorkout's placeholder-set fallback. Route both exits
    /// through the same guard rather than trusting completedExerciseIds
    /// alone to mean "there's something here."
    private func finishOrGuard() {
        if sessionManager.loggedSets.isEmpty {
            showEmptySessionGuard = true
        } else {
            showFeedbackSheet = true
        }
    }

    private func discardOrGuard() {
        if sessionManager.loggedSets.isEmpty {
            showEmptySessionGuard = true
        } else {
            reset()
        }
    }

    private func reset() {
        sessionManager.discard()
        companionComment = nil
        report = nil
        errorMessage = nil
        prAnnouncement = nil
        syncedWorkoutId = nil
        cancelRestTimer()
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
    let onShowHistory: () -> Void

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

                Button(action: onShowHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.fzTextSecondary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)

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
                    SetColumnHeader()

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

// MARK: - SetColumnHeader

/// Labels the columns above the per-set editor rows — without this, a row of
/// bare number boxes (weight / reps / rest) gives no clue which is which.
private struct SetColumnHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Set").frame(width: 40, alignment: .leading)
            Text("Weight").frame(width: SetInputRow.weightColumnWidth, alignment: .leading)
            Text("Reps").frame(width: SetInputRow.smallColumnWidth, alignment: .center)
            Text("Rest").frame(width: SetInputRow.smallColumnWidth, alignment: .center)
            Spacer(minLength: 44)
        }
        .font(.fzBody(10, weight: .semibold))
        .foregroundStyle(Color.fzTextSecondary.opacity(0.7))
        .textCase(.uppercase)
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

    static let weightColumnWidth: CGFloat = 108
    static let smallColumnWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            Text("Set \(setNumber)")
                .font(.fzMono(11, weight: .medium))
                .foregroundStyle(Color.fzTextSecondary)
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 4) {
                fieldBox(text: $weightText, placeholder: "wt", keyboard: .decimalPad, width: 44)

                // A native Picker(.menu) here would wrap its label vertically,
                // letter by letter, once squeezed this narrow — no amount of
                // .fixedSize() kept it from happening. A plain tap-to-toggle
                // button has no menu chrome to get squeezed, so it can't.
                Button(action: { unit = unit == .lbs ? .kg : .lbs }) {
                    Text(unit == .lbs ? "lb" : "kg")
                        .font(.fzMono(11, weight: .medium))
                        .foregroundStyle(Color.fzTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.fzSurface)
                        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                }
                .buttonStyle(.plain)
            }
            .frame(width: Self.weightColumnWidth, alignment: .leading)

            fieldBox(text: $repsText, placeholder: prescribedReps, keyboard: .numberPad, width: Self.smallColumnWidth)
            fieldBox(text: $restText, placeholder: "\(prescribedRestSecs)", keyboard: .numberPad, width: Self.smallColumnWidth)

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

// MARK: - RestTimerBanner

/// The foreground half of the rest timer — a live countdown from
/// `endDate`, driven by TimelineView rather than a hand-rolled Timer/Combine
/// publisher. The background half (a local notification if the app gets
/// backgrounded mid-rest) is NotificationManager.scheduleRestTimerAlert,
/// already scheduled by the time this appears.
private struct RestTimerBanner: View {
    let endDate: Date
    let totalSecs: Int
    let onDone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endDate.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .foregroundStyle(Color.fzPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest")
                        .font(.fzBody(11, weight: .semibold))
                        .foregroundStyle(Color.fzTextSecondary)
                        .textCase(.uppercase)
                    Text(timeText(remaining))
                        .font(.fzMono(20, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                }

                Spacer()

                ProgressCircle(fraction: totalSecs > 0 ? Double(remaining) / Double(totalSecs) : 0)
                    .frame(width: 32, height: 32)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.fzBody(13, weight: .medium))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.fzSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                    .strokeBorder(Color.fzPrimary.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: remaining) { _, newValue in
                if newValue <= 0 { onDone() }
            }
        }
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ProgressCircle: View {
    /// 1.0 = just started, 0.0 = done.
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.fzBorder, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.fzPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - AddExerciseSheet

/// Appends a manually-added exercise mid-workout — the modal counterpart to
/// the generated exercise list. Muscle group is optional but recommended: it
/// keeps a manually-added exercise counting toward Insights' weekly set
/// targets the same as anything Kai tagged at generation time.
private struct AddExerciseSheet: View {
    let onAdd: (WorkoutExercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sets = 3
    @State private var reps = "8-12"
    @State private var restSecs = 90
    @State private var muscleGroup: MuscleGroup?

    private var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                        nameField
                        setsStepper
                        repsField
                        restStepper
                        muscleGroupPicker
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.fzTextSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ForzeeButton(title: "Add to Workout", action: add, isDisabled: !canAdd)
                    .padding(ForzeeSpacing.screenPadding)
                    .background(Color.fzBg)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Exercise Name")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            TextField("e.g. Cable Lateral Raise", text: $name)
                .font(.fzBody(15))
                .foregroundStyle(Color.fzText)
                .padding(12)
                .background(Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
    }

    private var setsStepper: some View {
        Stepper(value: $sets, in: 1...10) {
            HStack {
                Text("Sets")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(sets)")
                    .font(.fzMono(15))
                    .foregroundStyle(Color.fzText)
            }
        }
    }

    private var repsField: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Reps")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            TextField("e.g. 8-12", text: $reps)
                .font(.fzBody(15))
                .foregroundStyle(Color.fzText)
                .padding(12)
                .background(Color.fzSurface)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
    }

    private var restStepper: some View {
        Stepper(value: $restSecs, in: 0...300, step: 15) {
            HStack {
                Text("Rest")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(restSecs)s")
                    .font(.fzMono(15))
                    .foregroundStyle(Color.fzText)
            }
        }
    }

    private var muscleGroupPicker: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Muscle Group (Optional)")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            Picker("Muscle Group", selection: $muscleGroup) {
                Text("None").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Text(group.displayName).tag(MuscleGroup?.some(group))
                }
            }
            .pickerStyle(.menu)
            .tint(Color.fzText)
        }
    }

    private func add() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        onAdd(WorkoutExercise(
            name: trimmedName,
            sets: sets,
            reps: reps.trimmingCharacters(in: .whitespaces).isEmpty ? "8-12" : reps,
            restSecs: restSecs,
            primaryMuscleGroup: muscleGroup
        ))
        dismiss()
    }
}

#Preview {
    WorkoutTabView()
        .environmentObject(AppState())
}
