---
name: show_progress
description: The user is asking about their progress on a specific exercise — how a lift has moved over time.
model: sonnet
---

```json
{
  "type": "object",
  "properties": {
    "exercise_name": {
      "type": "string",
      "description": "The specific exercise the user is asking about, using their own wording (e.g. \"bench press\", \"squat\"). Omit if no specific exercise is named."
    }
  },
  "required": []
}
```

The user just asked something like "how's my bench coming along" or "am I getting stronger on squats" — a question about progress on one specific lift, not a general how-am-I-doing question (that's the weekly read/recovery skills' territory) and not a request to build or change a workout.

Extract only which exercise they mean, in their own words. Do not report any numbers, trends, or a verdict yourself — you have no access to their actual logged data. The app looks up the real numbers separately and reports them; your only job here is identifying the exercise.
