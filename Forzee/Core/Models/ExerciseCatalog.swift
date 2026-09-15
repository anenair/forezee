// ============================================================
// ExerciseCatalog.swift
// Forzee — Core/Models
//
// The beginning of a canonical exercise catalog. Kai's own display
// name for an exercise ("Single Arm Dumbbell Row") is never treated
// as stable identity — WorkoutBuilder resolves it against this
// catalog instead, and only trusts the resulting `id` when there's
// an actual match.
//
// v1 is a flat, hand-seeded list with exact/alias name matching —
// intentionally simple. A real catalog (media, instructions, a
// proper search index) is future scope; this exists so the rest of
// the domain layer (WorkoutBuilder, muscle-group tagging) has
// somewhere real to resolve against today, rather than exerciseId
// being added later as a breaking change once a catalog exists.
// ============================================================

import Foundation

struct ExerciseDefinition: Identifiable, Equatable {
    let id: String
    let canonicalName: String
    let aliases: [String]
    let muscleGroups: [MuscleGroup]
    let equipment: [String]
    let movementPattern: String?
    let instructions: String?
    let mediaURL: String?
}

enum ExerciseCatalog {

    /// Every name (canonical + aliases), normalized, mapped to its
    /// definition — built once from `seed`, not scanned per lookup.
    private static let byNormalizedName: [String: ExerciseDefinition] = {
        var map: [String: ExerciseDefinition] = [:]
        for definition in seed {
            map[normalize(definition.canonicalName)] = definition
            for alias in definition.aliases {
                map[normalize(alias)] = definition
            }
        }
        return map
    }()

    /// Exact match only (case/whitespace-normalized) — no fuzzy matching
    /// yet. A miss is expected and fine: the caller keeps Kai's display
    /// name and simply has no catalog-backed id for it.
    static func resolve(name: String) -> ExerciseDefinition? {
        byNormalizedName[normalize(name)]
    }

    static func definition(id: String) -> ExerciseDefinition? {
        seed.first { $0.id == id }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Seed

    private static let seed: [ExerciseDefinition] = [
        ExerciseDefinition(
            id: "barbell_bench_press", canonicalName: "Barbell Bench Press",
            aliases: ["Bench Press", "Flat Barbell Bench Press"],
            muscleGroups: [.chest, .triceps, .shoulders], equipment: ["barbell", "bench"],
            movementPattern: "horizontal_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "dumbbell_bench_press", canonicalName: "Dumbbell Bench Press",
            aliases: ["DB Bench Press"],
            muscleGroups: [.chest, .triceps, .shoulders], equipment: ["dumbbells", "bench"],
            movementPattern: "horizontal_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "incline_push_up", canonicalName: "Incline Push-Up",
            aliases: ["Incline Pushup"],
            muscleGroups: [.chest, .triceps, .shoulders], equipment: ["bodyweight"],
            movementPattern: "horizontal_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "standard_push_up", canonicalName: "Push-Up",
            aliases: ["Standard Push-Up", "Pushup"],
            muscleGroups: [.chest, .triceps, .shoulders], equipment: ["bodyweight"],
            movementPattern: "horizontal_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "pike_push_up", canonicalName: "Pike Push-Up",
            aliases: [],
            muscleGroups: [.shoulders, .triceps], equipment: ["bodyweight"],
            movementPattern: "vertical_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "overhead_press", canonicalName: "Overhead Press",
            aliases: ["Barbell Overhead Press", "Shoulder Press"],
            muscleGroups: [.shoulders, .triceps], equipment: ["barbell"],
            movementPattern: "vertical_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "barbell_row", canonicalName: "Barbell Row",
            aliases: ["Bent Over Row", "Barbell Bent-Over Row"],
            muscleGroups: [.back, .biceps], equipment: ["barbell"],
            movementPattern: "horizontal_pull", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "single_arm_dumbbell_row", canonicalName: "Single Arm Dumbbell Row",
            aliases: ["One Arm Dumbbell Row", "Single-Arm DB Row"],
            muscleGroups: [.back, .biceps], equipment: ["dumbbells", "bench"],
            movementPattern: "horizontal_pull", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "pull_up", canonicalName: "Pull-Up",
            aliases: ["Pullup"],
            muscleGroups: [.back, .biceps], equipment: ["pull_up_bar"],
            movementPattern: "vertical_pull", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "lat_pulldown", canonicalName: "Lat Pulldown",
            aliases: [],
            muscleGroups: [.back, .biceps], equipment: ["cable_machine"],
            movementPattern: "vertical_pull", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "back_squat", canonicalName: "Back Squat",
            aliases: ["Barbell Back Squat", "Squat"],
            muscleGroups: [.quads, .glutes, .hamstrings], equipment: ["barbell", "squat_rack"],
            movementPattern: "squat", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "goblet_squat", canonicalName: "Goblet Squat",
            aliases: [],
            muscleGroups: [.quads, .glutes], equipment: ["dumbbells", "kettlebell"],
            movementPattern: "squat", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "romanian_deadlift", canonicalName: "Romanian Deadlift",
            aliases: ["RDL"],
            muscleGroups: [.hamstrings, .glutes, .back], equipment: ["barbell"],
            movementPattern: "hip_hinge", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "conventional_deadlift", canonicalName: "Deadlift",
            aliases: ["Conventional Deadlift", "Barbell Deadlift"],
            muscleGroups: [.hamstrings, .glutes, .back], equipment: ["barbell"],
            movementPattern: "hip_hinge", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "walking_lunge", canonicalName: "Walking Lunge",
            aliases: ["Lunge"],
            muscleGroups: [.quads, .glutes], equipment: ["bodyweight", "dumbbells"],
            movementPattern: "lunge", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "plank", canonicalName: "Plank",
            aliases: ["Plank Hold"],
            muscleGroups: [.core], equipment: ["bodyweight"],
            movementPattern: "isometric_core", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "chair_dip", canonicalName: "Chair Dips",
            aliases: ["Tricep Dips using a chair", "Bench Dips"],
            muscleGroups: [.triceps, .shoulders], equipment: ["bodyweight", "chair"],
            movementPattern: "vertical_push", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "bicep_curl", canonicalName: "Bicep Curl",
            aliases: ["Dumbbell Curl", "Barbell Curl"],
            muscleGroups: [.biceps], equipment: ["dumbbells", "barbell"],
            movementPattern: "elbow_flexion", instructions: nil, mediaURL: nil
        ),
        ExerciseDefinition(
            id: "calf_raise", canonicalName: "Calf Raise",
            aliases: ["Standing Calf Raise"],
            muscleGroups: [.calves], equipment: ["bodyweight"],
            movementPattern: "ankle_extension", instructions: nil, mediaURL: nil
        ),
    ]
}
