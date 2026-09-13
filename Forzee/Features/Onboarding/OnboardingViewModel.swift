// ============================================================
// OnboardingViewModel.swift
// Forzee — Features/Onboarding
//
// Holds all user selections made during onboarding and
// persists them to Supabase on completion.
//
// Ownership: created once in OnboardingFlowView and passed
// down via @EnvironmentObject so all step screens share state.
// ============================================================

import SwiftUI
import Combine

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Step 1: Fitness Level

    @Published var fitnessLevel: FitnessLevel? = nil

    // MARK: - Step 2: Goals (multi-select)

    @Published var selectedGoals: Set<TrainingGoal> = []

    // MARK: - Step 3: Equipment (multi-select)

    @Published var selectedEquipment: Set<Equipment> = []

    // MARK: - Step 4: Schedule

    @Published var selectedDays: Set<Weekday> = [.monday, .wednesday, .friday]
    @Published var preferredTime: TimeOfDay = .morning

    // MARK: - Step 5: Coach Mode

    @Published var coachMode: CoachMode = .guided

    // MARK: - Permissions

    @Published var healthKitGranted: Bool = false
    @Published var sleepDataGranted: Bool = false
    @Published var calendarGranted: Bool = false
    @Published var locationGranted: Bool = false
    @Published var notificationsGranted: Bool = false

    // MARK: - Saving State

    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil

    // MARK: - Computed

    var canContinueFromGoals: Bool { !selectedGoals.isEmpty }
    var canContinueFromEquipment: Bool { !selectedEquipment.isEmpty }
    var canContinueFromSchedule: Bool { !selectedDays.isEmpty }

    // MARK: - Complete Onboarding

    /// Saves all onboarding selections to the user's Supabase profile.
    /// Called from MeetKaiView when the user taps "Let's go".
    func complete(userId: String) async {
        isSaving = true
        saveError = nil

        let updates: [String: Any] = [
            "fitness_level":          fitnessLevel?.rawValue ?? "novice",
            "goals":                  selectedGoals.map(\.rawValue),
            "equipment":              selectedEquipment.map(\.rawValue),
            "preferred_days":         selectedDays.map(\.rawValue),
            "coach_mode":             coachMode.rawValue,
            "onboarding_complete":    true
        ]

        do {
            try await ForzeeDataService.shared.updateProfile(updates, userId: userId)
        } catch {
            saveError = "Couldn't save your profile. You can update this later in Settings."
        }

        if notificationsGranted {
            NotificationManager.shared.scheduleWorkoutReminders(days: selectedDays, time: preferredTime)
        }

        isSaving = false
    }
}

// MARK: - FitnessLevel

enum FitnessLevel: String, CaseIterable, Identifiable {
    case justStarting  = "novice"
    case gettingBack   = "returning"
    case intermediate  = "intermediate"
    case advanced      = "advanced"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .justStarting:  return "Just Starting"
        case .gettingBack:   return "Getting Back"
        case .intermediate:  return "Intermediate"
        case .advanced:      return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .justStarting:  return "New to fitness or starting fresh"
        case .gettingBack:   return "Returning after a break"
        case .intermediate:  return "Regular training, solid foundation"
        case .advanced:      return "Experienced, pushing limits"
        }
    }

    /// Lucide icon name used in the design
    var iconSystemName: String {
        switch self {
        case .justStarting:  return "figure.walk"
        case .gettingBack:   return "arrow.counterclockwise"
        case .intermediate:  return "dumbbell.fill"
        case .advanced:      return "flame.fill"
        }
    }
}

// MARK: - TrainingGoal

enum TrainingGoal: String, CaseIterable, Identifiable {
    case loseWeight          = "lose_weight"
    case buildMuscle         = "build_muscle"
    case improveEndurance    = "improve_endurance"
    case getStronger         = "get_stronger"
    case improveFlexibility  = "improve_flexibility"
    case reduceStress        = "reduce_stress"
    case trainForSport       = "train_for_sport"
    case generalHealth       = "general_health"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loseWeight:         return "Lose weight"
        case .buildMuscle:        return "Build muscle"
        case .improveEndurance:   return "Improve endurance"
        case .getStronger:        return "Get stronger"
        case .improveFlexibility: return "Improve flexibility"
        case .reduceStress:       return "Reduce stress"
        case .trainForSport:      return "Train for a sport"
        case .generalHealth:      return "General health"
        }
    }

    /// Goals are displayed in a 2-column pill grid in this order
    static var displayOrder: [[TrainingGoal]] {
        [
            [.loseWeight, .buildMuscle],
            [.improveEndurance, .getStronger],
            [.improveFlexibility, .reduceStress],
            [.trainForSport, .generalHealth]
        ]
    }
}

// MARK: - Equipment

enum Equipment: String, CaseIterable, Identifiable {
    case bodyweight      = "bodyweight"
    case dumbbells       = "dumbbells"
    case resistanceBands = "resistance_bands"
    case barbellRack     = "barbell"
    case fullGym         = "full_gym"
    case cardioMachines  = "cardio_machines"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyweight:      return "Just my body"
        case .dumbbells:       return "Dumbbells"
        case .resistanceBands: return "Resistance\nbands"
        case .barbellRack:     return "Barbell\n& rack"
        case .fullGym:         return "Full gym"
        case .cardioMachines:  return "Cardio\nmachines"
        }
    }

    var iconSystemName: String {
        switch self {
        case .bodyweight:      return "figure.strengthtraining.traditional"
        case .dumbbells:       return "dumbbell"
        case .resistanceBands: return "arrow.left.and.right"
        case .barbellRack:     return "square.grid.2x2.fill"
        case .fullGym:         return "building.2.fill"
        case .cardioMachines:  return "bicycle"
        }
    }

    /// Grid layout: 3 rows × 2 columns
    static var displayGrid: [[Equipment]] {
        [[.bodyweight, .dumbbells], [.resistanceBands, .barbellRack], [.fullGym, .cardioMachines]]
    }
}

// MARK: - Weekday

enum Weekday: String, CaseIterable, Identifiable {
    case monday    = "monday"
    case tuesday   = "tuesday"
    case wednesday = "wednesday"
    case thursday  = "thursday"
    case friday    = "friday"
    case saturday  = "saturday"
    case sunday    = "sunday"

    var id: String { rawValue }

    var short: String {
        switch self {
        case .monday: return "M"; case .tuesday: return "T"
        case .wednesday: return "W"; case .thursday: return "T"
        case .friday: return "F"; case .saturday: return "S"
        case .sunday: return "S"
        }
    }
}

// MARK: - CoachMode

/// How much Kai initiates contact vs. waits to be asked — an axis
/// independent of fitness level. Combines with tone-per-level in
/// KaiSystemPrompt (e.g. "novice + accountability" reads differently
/// than "advanced + accountability").
enum CoachMode: String, CaseIterable, Identifiable {
    case advisory      = "advisory"
    case guided        = "guided"
    case accountability = "accountability"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advisory:      return "Advisory"
        case .guided:        return "Guided"
        case .accountability: return "Accountability"
        }
    }

    var subtitle: String {
        switch self {
        case .advisory:      return "Answer when I ask — don't reach out first"
        case .guided:        return "Suggest things, but let me decide"
        case .accountability: return "Push back when I'm avoiding it"
        }
    }

    var iconSystemName: String {
        switch self {
        case .advisory:      return "bubble.left"
        case .guided:        return "compass.drawing"
        case .accountability: return "flag.checkered"
        }
    }
}

// MARK: - TimeOfDay

enum TimeOfDay: String, CaseIterable, Identifiable {
    case morning   = "morning"
    case afternoon = "afternoon"
    case evening   = "evening"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
