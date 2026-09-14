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
        \(trainingSplitRequirement(context.user.trainingSplit))
        \(exerciseVariabilityRequirement(context.user.exerciseVariability))
        \(warmupRequirement(context.user.warmupSetsEnabled))
        \(circuitsRequirement(context.user.circuitsSupersetsEnabled))
        - The user thinks in \(context.user.weightUnit) — phrase the coaching_note and any \
        exercise notes accordingly, even though weight_kg is always kilograms in the JSON itself.
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
              "notes": "Optional form cue or coaching note for this exercise.",
              "primary_muscle_group": "chest|back|shoulders|biceps|triceps|quads|hamstrings|glutes|calves|core|full_body",
              "secondary_muscle_groups": ["triceps"]
            }
          ]
        }

        primary_muscle_group is required for every exercise — pick the one group \
        it trains most directly (a bench press is chest, not triceps, even though \
        triceps assist). secondary_muscle_groups lists any other groups it \
        meaningfully trains; use an empty array if there genuinely aren't any, \
        don't pad it out. This tagging feeds the Insights tab's weekly volume \
        and recovery tracking — get it right, don't guess.

        Do not include any prose before or after the JSON.
        """

        return prompt
    }

    // MARK: - Training Preferences (Phase 4 "My Plan")
    //
    // Structured fields from UserContextSnapshot.UserContext, each turned
    // into one concrete instruction rather than left for Kai to infer from
    // a free-text blob. No persisted "which day of the split are we on"
    // state exists yet, so a split preference is advisory — Kai has to
    // infer where the user left off from recent session history/coaching
    // notes, same as it already does for everything else about continuity.

    private static func trainingSplitRequirement(_ split: String) -> String {
        switch split {
        case "let_kai_decide":
            return "- No fixed split requested — choose what fits today, informed by recent training."
        case "full_body":
            return "- The user trains full body each session — hit major muscle groups, not one region."
        case "upper_lower":
            return "- The user follows an upper/lower split — check recent sessions for which half " +
                   "they last trained and continue the rotation, don't repeat the same half."
        case "push_pull_legs":
            return "- The user follows a push/pull/legs split — check recent sessions for where they " +
                   "left off in the rotation and continue it (push → pull → legs → repeat)."
        case "body_part_split":
            return "- The user follows a body-part split (one or two muscle groups per session) — " +
                   "check recent sessions to avoid repeating a group trained in the last day or two."
        default:
            return "- No fixed split requested — choose what fits today, informed by recent training."
        }
    }

    private static func exerciseVariabilityRequirement(_ variability: String) -> String {
        switch variability {
        case "low":
            return "- Keep exercise selection consistent with recent sessions where reasonable — " +
                   "the user wants to track progress on the same lifts, not novelty."
        case "high":
            return "- Vary exercise selection meaningfully from recent sessions — the user wants " +
                   "every workout to feel fresh, not a repeat of last time."
        default: // "moderate"
            return "- Swap in some variety from recent sessions, but don't chase novelty for its own sake."
        }
    }

    private static func warmupRequirement(_ enabled: Bool) -> String {
        enabled
            ? "- Include 1-2 warm-up sets before each main lift, at lighter load than the working sets."
            : "- Skip dedicated warm-up sets — go straight into working sets."
    }

    private static func circuitsRequirement(_ enabled: Bool) -> String {
        enabled
            ? "- Circuits and supersets are fine where they fit — you don't have to keep every exercise sequential."
            : "- Keep exercises sequential, one at a time — no circuits or supersets."
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
