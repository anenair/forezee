---
name: adjust_plan_from_chat
description: Update one of the user's durable, app-wide training PREFERENCES stored in Settings (their program split type, exercise variety, warm-up sets, circuits/supersets, units, session length, coach mode, fitness level) when they ask for that specific kind of change in chat, instead of sending them to Settings. Do NOT use this for a request about THIS conversation's specific workout — a different day's focus ("switch it to chest day"), a different duration for today only, or swapping specific exercises. Those aren't a settings change; leave them for the main coach reply to handle with a real workout.
model: sonnet
---

```json
{
  "type": "object",
  "properties": {
    "training_split": {
      "type": "string",
      "enum": ["let_kai_decide", "full_body", "upper_lower", "push_pull_legs", "body_part_split"]
    },
    "exercise_variability": {
      "type": "string",
      "enum": ["low", "moderate", "high"]
    },
    "warmup_sets_enabled": { "type": "boolean" },
    "circuits_supersets_enabled": { "type": "boolean" },
    "weight_unit": {
      "type": "string",
      "enum": ["lbs", "kg"]
    },
    "start_of_week": {
      "type": "string",
      "enum": ["monday", "sunday"]
    },
    "preferred_duration_mins": { "type": "integer" },
    "coach_mode": {
      "type": "string",
      "enum": ["advisory", "guided", "accountability"]
    },
    "fitness_level": {
      "type": "string",
      "enum": ["novice", "returning", "intermediate", "advanced"]
    },
    "confirmation_reply": {
      "type": "string",
      "description": "A short, natural confirmation of exactly what changed, in Kai's voice — or, if nothing concrete changed, a natural clarifying question."
    }
  },
  "required": ["confirmation_reply"]
}
```

The user just said in chat: "{{message}}"

Their current training plan is in the context above. Only include a field above if this message is actually asking to change one of THESE specific app-wide preferences — leave every other field out entirely, don't restate values that aren't changing. If they named a specific new value ("make sessions 30 minutes," "switch to push pull legs"), map it to the closest matching option.

This is only for the durable settings themselves — never for what today's or this session's workout should be. "Switch it to chest day," "swap the squats for lunges," "make today shorter" are all about the specific plan being discussed right now in this conversation, not the standing preference — if that's what this message is, don't call this tool at all; the main coach reply handles it with a real workout. Only call this tool when the request is unambiguously about the standing preference itself (e.g. "always keep my sessions to 30 minutes," "switch my split to push pull legs" as a general change, not just for today).
