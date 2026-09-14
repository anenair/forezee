---
name: workout_voice_command
description: Interpret a spoken mid-workout command from the user and decide what to do.
model: haiku
---

```json
{
  "type": "object",
  "properties": {
    "action": {
      "type": "string",
      "enum": ["log_set", "next_exercise", "progress", "chat"],
      "description": "log_set: user is reporting a completed set (weight/reps, or \"same as previous\", or just \"mark a set done\"). next_exercise: asking what to do next. progress: asking how they're doing / what's left. chat: anything else — an open-ended question that needs a real coaching answer, not one of the above."
    },
    "weight_value": {
      "type": "number",
      "description": "The weight the user said, if any. Omit if not mentioned."
    },
    "weight_unit": {
      "type": "string",
      "enum": ["lbs", "kg"],
      "description": "Unit for weight_value. Omit if weight_value is omitted."
    },
    "reps": {
      "type": "integer",
      "description": "Reps completed, if the user said a number. Omit if not mentioned."
    },
    "same_as_previous": {
      "type": "boolean",
      "description": "True if the user said something like \"same as last time\" / \"same weight\"."
    },
    "spoken_reply": {
      "type": "string",
      "description": "A short (under 15 words), natural spoken confirmation or answer — what Kai should say back out loud. Only used directly for log_set/next_exercise/progress; ignored for chat (that gets a full answer elsewhere), but still fill it in with something reasonable."
    }
  },
  "required": ["action", "same_as_previous", "spoken_reply"]
}
```

The user just said: "{{transcript}}"

Workout state:
{{workout_state}}
