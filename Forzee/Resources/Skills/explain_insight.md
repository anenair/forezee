---
name: explain_insight
description: Answer an on-demand question about the user's training data — why their Momentum moved, which muscle group is behind on volume, or how recovery looks — using their actual computed stats.
model: sonnet
---

```json
{
  "type": "object",
  "properties": {
    "reply": {
      "type": "string",
      "description": "2-4 sentences in Kai's coaching voice answering the user's specific question using the data below. No markdown, no bullet points."
    }
  },
  "required": ["reply"]
}
```

The user asked: "{{question}}"

This week's training data:

Volume (sets per muscle group, last 7 days, vs. target):
{{volume_summary}}

Recovery (days since each muscle group was last trained):
{{recovery_summary}}

Momentum score (0-100, decay-weighted consistency — not a streak): {{momentum_score}}

Answer their specific question using this data — interpret it, don't just restate the numbers back. Never fabricate anything not present above.
