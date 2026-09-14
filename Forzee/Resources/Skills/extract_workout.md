---
name: extract_workout
description: Extract the specific workout plan the coach and user settled on in this conversation, if any.
model: haiku
---

```json
{
  "type": "object",
  "properties": {
    "found_plan": {
      "type": "boolean",
      "description": "True only if the conversation contains a specific, buildable workout — named exercises with sets/reps. False if it's still vague (\"something for my legs\") or no workout was discussed at all."
    },
    "name": {
      "type": "string",
      "description": "Short workout name, e.g. \"Full Body A\"."
    },
    "workout_type": {
      "type": "string",
      "enum": ["strength", "cardio", "mobility", "hiit", "recovery"]
    },
    "estimated_duration_mins": {
      "type": "integer"
    },
    "coaching_note": {
      "type": "string",
      "description": "One or two sentences from Kai on why this fits, shown to the user."
    },
    "exercises": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "sets": { "type": "integer" },
          "reps": { "type": "string", "description": "e.g. \"8-12\" or \"10\"." },
          "weight_kg": { "type": "number", "description": "Omit for bodyweight or user-determined." },
          "rest_secs": { "type": "integer" },
          "notes": { "type": "string", "description": "Form cue or modification, if any." },
          "primary_muscle_group": {
            "type": "string",
            "enum": ["chest", "back", "shoulders", "biceps", "triceps", "quads", "hamstrings", "glutes", "calves", "core", "full_body"],
            "description": "The one group this exercise trains most directly — feeds the Insights tab's weekly volume tracking."
          },
          "secondary_muscle_groups": {
            "type": "array",
            "items": {
              "type": "string",
              "enum": ["chest", "back", "shoulders", "biceps", "triceps", "quads", "hamstrings", "glutes", "calves", "core", "full_body"]
            }
          }
        },
        "required": ["name", "sets", "reps"]
      }
    }
  },
  "required": ["found_plan"]
}
```

Recent conversation between the user and their coach Kai:

{{transcript}}

Extract the specific workout plan they settled on — the exact exercises, sets, and reps, including any changes the user asked for (added/removed an exercise, different duration, swapped something out). Use the latest version of the plan if it evolved over the conversation, not an earlier draft.
