// ============================================================
// WorkoutBuilder.swift
// Forzee — Core/AI/CoachProtocol
//
// The one place a Kai-proposed CoachWorkout becomes a real,
// canonical GeneratedWorkout — the app's existing, authoritative
// workout model (see Core/Models/GeneratedWorkout.swift), not a
// parallel one. This is the "proposal -> domain layer -> authoritative
// state" boundary described at the top of CoachResponse.swift: a
// CoachWorkout inside a chat message is never itself treated as a
// workout the app can run; only what this function produces is —
// and even then, only once the user actually starts it (see
// CoachActionExecutor).
// ============================================================

import Foundation

enum WorkoutBuilder {

    static func build(from coachWorkout: CoachWorkout, context: UserContextSnapshot? = nil) -> GeneratedWorkout {
        GeneratedWorkout(
            id: coachWorkout.id.flatMap { UUID(uuidString: $0) } ?? UUID(),
            name: coachWorkout.title.isEmpty ? "Workout" : coachWorkout.title,
            workoutType: "strength",
            estimatedDurationMins: coachWorkout.estimatedDurationMinutes ?? 30,
            exercises: coachWorkout.exercises.map(buildExercise),
            contextSnapshot: context
        )
    }

    private static func buildExercise(_ coachExercise: CoachExercise) -> WorkoutExercise {
        // The LLM's exerciseId (if any) is never trusted as-is — re-resolve
        // by name against the catalog, same as if only a display name had
        // been given. A catalog hit also fills in muscle-group tags Kai
        // didn't have to supply itself, and those flow straight into
        // Insights (weekly set volume, recovery) the same as any other
        // tagged exercise.
        let catalogMatch = ExerciseCatalog.resolve(name: coachExercise.name)
        let muscleGroups = catalogMatch?.muscleGroups ?? []

        return WorkoutExercise(
            exerciseId: catalogMatch?.id ?? coachExercise.exerciseId,
            name: coachExercise.name,
            sets: coachExercise.prescription.legacySets,
            reps: coachExercise.prescription.legacyRepsText,
            restSecs: coachExercise.prescription.legacyRestSeconds,
            notes: coachExercise.notes,
            primaryMuscleGroup: muscleGroups.first,
            secondaryMuscleGroups: Array(muscleGroups.dropFirst()),
            prescription: coachExercise.prescription
        )
    }
}
