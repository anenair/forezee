// ============================================================
// MyPlanView.swift
// Forzee — Features/Settings
//
// Roadmap Phase 4 "Training preferences, made editable" — the
// real gap this whole session kept hitting: onboarding answers
// landed once and were effectively frozen (the session-length
// card that turned out to be decoration, equipment silently
// resetting to bodyweight-only). Every field here is editable
// anytime, not just at signup, and feeds Kai's generation prompt
// as structured fields (see WorkoutGenerationPrompt) rather than
// a free-text blob.
// ============================================================

import SwiftUI

struct MyPlanView: View {

    @EnvironmentObject private var appState: AppState

    @State private var fitnessLevel: FitnessLevel = .justStarting
    @State private var goals: Set<TrainingGoal> = []
    @State private var equipment: Set<Equipment> = []
    @State private var preferredDays: Set<Weekday> = []
    @State private var sessionLengthMinutes: Int = 45

    @State private var trainingSplit: TrainingSplit = .letKaiDecide
    @State private var exerciseVariability: ExerciseVariability = .moderate
    @State private var warmupSetsEnabled = true
    @State private var circuitsSupersetsEnabled = false
    @State private var weightUnit: WeightUnit = .lbs
    @State private var startOfWeek: StartOfWeek = .monday

    @State private var isSaving = false
    @State private var didSave = false

    private var canSave: Bool {
        !goals.isEmpty && !equipment.isEmpty && !preferredDays.isEmpty
    }

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: ForzeeSpacing.sectionGap) {
                    PlanCard(title: "Fitness Level") {
                        VStack(spacing: 8) {
                            ForEach(FitnessLevel.allCases) { level in
                                SelectableRow(
                                    title: level.title,
                                    subtitle: level.subtitle,
                                    isSelected: fitnessLevel == level
                                ) { fitnessLevel = level }
                            }
                        }
                    }

                    PlanCard(title: "Goals") {
                        VStack(spacing: 8) {
                            ForEach(TrainingGoal.allCases) { goal in
                                SelectableRow(title: goal.label, subtitle: nil, isSelected: goals.contains(goal)) {
                                    toggle(goal, in: &goals)
                                }
                            }
                        }
                    }

                    PlanCard(title: "Equipment") {
                        VStack(spacing: 8) {
                            ForEach(Equipment.allCases) { item in
                                SelectableRow(
                                    title: item.label.replacingOccurrences(of: "\n", with: " "),
                                    subtitle: nil,
                                    isSelected: equipment.contains(item)
                                ) { toggle(item, in: &equipment) }
                            }
                        }
                    }

                    PlanCard(title: "Training Split") {
                        VStack(spacing: 8) {
                            ForEach(TrainingSplit.allCases) { split in
                                SelectableRow(
                                    title: split.title,
                                    subtitle: split.subtitle,
                                    isSelected: trainingSplit == split
                                ) { trainingSplit = split }
                            }
                        }
                    }

                    PlanCard(title: "Exercise Variety") {
                        VStack(spacing: 8) {
                            ForEach(ExerciseVariability.allCases) { variability in
                                SelectableRow(
                                    title: variability.title,
                                    subtitle: variability.subtitle,
                                    isSelected: exerciseVariability == variability
                                ) { exerciseVariability = variability }
                            }
                        }
                    }

                    PlanCard(title: "Workout Structure") {
                        VStack(spacing: 4) {
                            Toggle(isOn: $warmupSetsEnabled) {
                                Text("Warm-up sets")
                                    .font(.fzBody(14))
                                    .foregroundStyle(Color.fzText)
                            }
                            .tint(Color.fzPrimary)
                            .padding(.vertical, 8)

                            Toggle(isOn: $circuitsSupersetsEnabled) {
                                Text("Circuits & supersets")
                                    .font(.fzBody(14))
                                    .foregroundStyle(Color.fzText)
                            }
                            .tint(Color.fzPrimary)
                            .padding(.vertical, 8)
                        }
                    }

                    PlanCard(title: "Units") {
                        TwoOptionSegment(selected: $weightUnit) { $0.displayName }
                    }

                    PlanCard(title: "Start of Week") {
                        TwoOptionSegment(selected: $startOfWeek) { $0.title }
                    }

                    PlanCard(title: "Training Days") {
                        HStack(spacing: 8) {
                            ForEach(Weekday.allCases) { day in
                                DayToggle(day: day, isSelected: preferredDays.contains(day)) {
                                    toggle(day, in: &preferredDays)
                                }
                            }
                        }
                    }

                    PlanCard(title: "Session Length") {
                        VStack(spacing: 12) {
                            Text("About \(sessionLengthMinutes) minutes")
                                .font(.fzHeading(20, weight: .bold))
                                .foregroundStyle(Color.fzText)
                                .frame(maxWidth: .infinity, alignment: .center)
                            SessionLengthPicker(selected: $sessionLengthMinutes)
                        }
                    }

                    if !canSave {
                        Text("Pick at least one goal, equipment option, and training day to save.")
                            .font(.fzBody(12))
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }
                .padding(ForzeeSpacing.screenPadding)
                .padding(.bottom, 72)
            }
        }
        .navigationTitle("My Plan")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if didSave {
                    Text("Saved")
                        .font(.fzBody(12, weight: .semibold))
                        .foregroundStyle(Color.fzGreen)
                }
                ForzeeButton(
                    title: "Save Changes",
                    action: { Task { await save() } },
                    isDisabled: !canSave,
                    isLoading: isSaving
                )
            }
            .padding(ForzeeSpacing.screenPadding)
            .background(Color.fzBg)
        }
        .onAppear(perform: loadFromProfile)
    }

    // MARK: - Actions

    private func toggle<T: Hashable>(_ item: T, in set: inout Set<T>) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
    }

    private func loadFromProfile() {
        guard let profile = appState.userProfile else { return }
        fitnessLevel = FitnessLevel(rawValue: profile.fitnessLevel) ?? .justStarting
        goals = Set(profile.goals.compactMap(TrainingGoal.init(rawValue:)))
        equipment = Set(profile.equipment.compactMap(Equipment.init(rawValue:)))
        preferredDays = Set(profile.preferredDays.compactMap(Weekday.init(rawValue:)))
        sessionLengthMinutes = profile.preferredDurationMins
        trainingSplit = TrainingSplit(rawValue: profile.trainingSplit) ?? .letKaiDecide
        exerciseVariability = ExerciseVariability(rawValue: profile.exerciseVariability) ?? .moderate
        warmupSetsEnabled = profile.warmupSetsEnabled
        circuitsSupersetsEnabled = profile.circuitsSupersetsEnabled
        weightUnit = WeightUnit(rawValue: profile.weightUnit) ?? .lbs
        startOfWeek = StartOfWeek(rawValue: profile.startOfWeek) ?? .monday
    }

    private func save() async {
        guard let userId = appState.userId, canSave else { return }
        isSaving = true
        didSave = false
        defer { isSaving = false }

        let updates: [String: Any] = [
            "fitness_level": fitnessLevel.rawValue,
            "goals": goals.map(\.rawValue),
            "equipment": equipment.map(\.rawValue),
            "preferred_days": preferredDays.map(\.rawValue),
            "preferred_duration_mins": sessionLengthMinutes,
            "training_split": trainingSplit.rawValue,
            "exercise_variability": exerciseVariability.rawValue,
            "warmup_sets_enabled": warmupSetsEnabled,
            "circuits_supersets_enabled": circuitsSupersetsEnabled,
            "weight_unit": weightUnit.rawValue,
            "start_of_week": startOfWeek.rawValue,
        ]

        guard (try? await ForzeeDataService.shared.updateProfile(updates, userId: userId)) != nil else { return }

        appState.userProfile?.fitnessLevel = fitnessLevel.rawValue
        appState.userProfile?.goals = goals.map(\.rawValue)
        appState.userProfile?.equipment = equipment.map(\.rawValue)
        appState.userProfile?.preferredDays = preferredDays.map(\.rawValue)
        appState.userProfile?.preferredDurationMins = sessionLengthMinutes
        appState.userProfile?.trainingSplit = trainingSplit.rawValue
        appState.userProfile?.exerciseVariability = exerciseVariability.rawValue
        appState.userProfile?.warmupSetsEnabled = warmupSetsEnabled
        appState.userProfile?.circuitsSupersetsEnabled = circuitsSupersetsEnabled
        appState.userProfile?.weightUnit = weightUnit.rawValue
        appState.userProfile?.startOfWeek = startOfWeek.rawValue

        withAnimation { didSave = true }
    }
}

// MARK: - Training Preference Enums

/// No persisted "which day of the split are we on" state exists yet — Kai
/// infers where the user left off from recent session history instead (see
/// WorkoutGenerationPrompt.trainingSplitRequirement). This is a preference
/// for what pattern to follow, not a tracker of rotation state.
enum TrainingSplit: String, CaseIterable, Identifiable {
    case letKaiDecide  = "let_kai_decide"
    case fullBody      = "full_body"
    case upperLower    = "upper_lower"
    case pushPullLegs  = "push_pull_legs"
    case bodyPartSplit = "body_part_split"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letKaiDecide:  return "Let Kai Decide"
        case .fullBody:      return "Full Body"
        case .upperLower:    return "Upper / Lower"
        case .pushPullLegs:  return "Push / Pull / Legs"
        case .bodyPartSplit: return "Body Part Split"
        }
    }

    var subtitle: String {
        switch self {
        case .letKaiDecide:  return "Kai picks what fits each session"
        case .fullBody:      return "Every session trains the whole body"
        case .upperLower:    return "Alternate upper and lower body days"
        case .pushPullLegs:  return "Rotate push, pull, and leg days"
        case .bodyPartSplit: return "One or two muscle groups per session"
        }
    }
}

enum ExerciseVariability: String, CaseIterable, Identifiable {
    case low      = "low"
    case moderate = "moderate"
    case high     = "high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:      return "Keep It Consistent"
        case .moderate: return "Mix It Up Sometimes"
        case .high:     return "Maximum Variety"
        }
    }

    var subtitle: String {
        switch self {
        case .low:      return "Repeat the same exercises so I can track progress"
        case .moderate: return "Swap in something new every few sessions"
        case .high:     return "Keep every workout fresh"
        }
    }
}

enum StartOfWeek: String, CaseIterable, Identifiable {
    case monday = "monday"
    case sunday = "sunday"

    var id: String { rawValue }
    var title: String { self == .monday ? "Monday" : "Sunday" }
}

// MARK: - PlanCard

private struct PlanCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text(title)
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            content
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

// MARK: - SelectableRow

private struct SelectableRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.fzBody(14, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.fzBody(12))
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzBorder)
            }
            .padding(12)
            .background(Color.fzSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TwoOptionSegment

private struct TwoOptionSegment<T: Hashable & CaseIterable>: View where T.AllCases: RandomAccessCollection {
    @Binding var selected: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(T.allCases), id: \.self) { option in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selected = option }
                }) {
                    Text(label(option))
                        .font(.fzBody(13, weight: .medium))
                        .foregroundStyle(selected == option ? Color(hex: "0A0A0F") : Color.fzTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                                .fill(selected == option ? Color.fzPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.button))
    }
}

// MARK: - DayToggle

private struct DayToggle: View {
    let day: Weekday
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(day.short)
                .font(.fzHeading(14, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: "0A0A0F") : Color.fzText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(isSelected ? Color.fzPrimary : Color.fzSurfaceElevated)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(isSelected ? Color.clear : Color.fzBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SessionLengthPicker

private struct SessionLengthPicker: View {
    @Binding var selected: Int

    private static let presets = [20, 30, 45, 60]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.presets, id: \.self) { minutes in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selected = minutes }
                }) {
                    Text("\(minutes)")
                        .font(.fzBody(13, weight: .medium))
                        .foregroundStyle(selected == minutes ? Color(hex: "0A0A0F") : Color.fzTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                                .fill(selected == minutes ? Color.fzPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.button))
    }
}

#Preview {
    NavigationStack {
        MyPlanView()
            .environmentObject(AppState())
    }
}
