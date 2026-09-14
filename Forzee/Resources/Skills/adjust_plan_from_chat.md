---
name: adjust_plan_from_chat
description: Update the user's training plan preferences (split, exercise variety, warm-up sets, circuits/supersets, units, session length, coach mode, fitness level) when they ask for a change in chat, instead of sending them to Settings.
model: haiku
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

Their current training plan is in the context above. Only include a field above if this message is actually asking to change it — leave every other field out entirely, don't restate values that aren't changing. If they named a specific new value ("make sessions 30 minutes," "switch to push pull legs"), map it to the closest matching option. If you can't tell what they want changed, leave every preference field out and use confirmation_reply to ask a natural clarifying question instead.
