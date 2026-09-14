// ============================================================
// WorkoutGenerationPrompt.swift
// Forzee — Core/AI
//
// Builds the user message prompt for Kai's workout generator.
// The response is parsed by WorkoutParser into a GeneratedWorkout.
//
// Claude is instructed to return a strict JSON schema so the
// iOS app can decode and render the workout reliably.
// ============================================================

import Foundation

enum WorkoutGenerationPrompt {

    static func build(context: UserContextSnapshot, preferences: WorkoutPreferences?) -> String {
        var prompt = """
        Generate an adaptive workout for this user based on their context.

        Requirements:
        - Use only the equipment they have available
        - Respect any limitations or injuries
        - Match the session to their fitness level and goals
        - Account for their recent training load (avoid overtraining)
        """

        if let prefs = preferences {
            if let duration = prefs.durationMinutes {
                prompt += "\n- Target duration: \(duration) minutes"
            }
            if let muscles = prefs.focusMuscleGroups, !muscles.isEmpty {
                prompt += "\n- Focus on: \(muscles.joined(separator: ", "))"
            }
            if let intensity = prefs.intensityOverride {
                prompt += "\n- Intensity override: \(intensity)"
            }
        }

        prompt += """


        Return ONLY valid JSON in this exact schema:
        {
          "name": "Workout name",
          "workout_type": "strength|cardio|mobility|hiit|recovery",
          "estimated_duration_mins": 45,
          "coaching_note": "A one or two sentence note from Kai explaining why this workout fits the user today.",
          "exercises": [
            {
              "name": "Exercise Name",
              "sets": 3,
              "reps": "8-12",
              "weight_kg": null,
              "rest_secs": 90,
              "notes": "Optional form cue or coaching note for this exercise."
            }
          ]
        }

        Do not include any prose before or after the JSON.
        """

        return prompt
    }
}

// MARK: - DailyBriefingPrompt

enum DailyBriefingPrompt {

    static func build(context: UserContextSnapshot) -> String {
        return """
        Generate today's briefing for this user. It's currently \(context.currentTimeOfDay) \
        (\(context.currentLocalTime)) for them — match the wording to that, rather than \
        assuming it's morning. If it's already evening or night, don't suggest "this morning."

        Keep it short — 2-3 sentences maximum. Warm but not over-the-top.
        Reference their context naturally if relevant (e.g. last session, goals).
        End with one clear, actionable suggestion for today.

        No time-of-day greetings like "Good morning!" or "Good evening!" — just start with the substance.
        """
    }
}

// MARK: - GymCompanionCommentPrompt

/// Fires live, mid-workout — the user just checked off an exercise at the gym.
/// Deliberately skips the full context snapshot: this needs to come back fast
/// while someone's resting between sets, not after a round-trip through
/// HealthKit/EventKit/WeatherKit.
enum GymCompanionCommentPrompt {

    static func build(exerciseName: String, fitnessLevel: String) -> String {
        return """
        The user, a \(fitnessLevel)-level trainee, just finished "\(exerciseName)".

        React in ONE short sentence — under 12 words. A real coach standing next \
        to them between sets, not a chatbot. No exclamation-point spam, no generic \
        hype. Vary it — not the same phrase every time.
        """
    }
}

// MARK: - WorkoutReportPrompt

enum WorkoutReportPrompt {

    static func build(
        context: UserContextSnapshot,
        workout: GeneratedWorkout,
        completedExerciseNames: [String]
    ) -> String {
        let skipped = workout.exercises.map(\.name).filter { !completedExerciseNames.contains($0) }

        return """
        The user just finished this workout: "\(workout.name)" (\(workout.workoutType)).

        Completed: \(completedExerciseNames.isEmpty ? "none logged" : completedExerciseNames.joined(separator: ", "))
        Skipped: \(skipped.isEmpty ? "none" : skipped.joined(separator: ", "))

        Write a short post-workout report — 3-4 sentences. Acknowledge what they \
        actually did (not what was prescribed), note anything skipped without \
        guilt-tripping, and end with one specific thing to focus on next session.
        """
    }
}
