---
name: recovery_check
description: Answer whether the user should train as planned, train lighter, or take a rest day today, based on their recent sleep, HRV, calendar, and training load.
model: haiku
---

```json
{
  "type": "object",
  "properties": {
    "recommendation": {
      "type": "string",
      "enum": ["train_as_planned", "train_lighter", "rest_day"]
    },
    "reply": {
      "type": "string",
      "description": "2-3 sentences in Kai's coaching voice, referencing the specific signal(s) that drove the recommendation. No markdown."
    }
  },
  "required": ["recommendation", "reply"]
}
```

The user just asked: "{{message}}"

Decide whether today should be trained as planned, trained lighter, or a full rest day — based on the sleep, HRV, calendar, and recent-training-load signals in the context above. Reference the specific signal(s) that actually drove your answer; never fabricate anything not present there. If a signal is missing (e.g. no sleep data), say so rather than guessing.
