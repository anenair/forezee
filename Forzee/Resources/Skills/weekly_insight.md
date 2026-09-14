---
name: weekly_insight
description: Write Kai's short synthesis of the user's training week — volume, recovery, and Momentum — in Kai's own coaching voice.
model: sonnet
---

```json
{
  "type": "object",
  "properties": {
    "insight": {
      "type": "string",
      "description": "Two or three sentences in Kai's coaching voice synthesizing the week's training volume, recovery, and Momentum. No markdown, no bullet points, no headers — plain prose, the same voice as chat."
    }
  },
  "required": ["insight"]
}
```

This week's training data for this user:

Volume (sets per muscle group, last 7 days, vs. target):
{{volume_summary}}

Recovery (days since each muscle group was last trained):
{{recovery_summary}}

Momentum score (0-100, decay-weighted consistency — not a streak): {{momentum_score}}

Write Kai's weekly read: two or three sentences synthesizing what this data actually means for the user this week. Call out whatever's most worth their attention — a muscle group being neglected, one that's genuinely fresh and ready to push, or Momentum building or fading. Don't just restate the numbers back; interpret them, the way a real coach would glance at this and tell the user what matters. Never fabricate anything not in the data above.
