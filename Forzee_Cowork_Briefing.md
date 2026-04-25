# Forzee — Cowork Project Briefing
**Version:** 1.0
**Last Updated:** April 2026

---

## What We Are Building

Forzee is an iOS-first AI fitness coaching app where the AI coach
named **Kai** is the entire product. Not a feature — the product.

Kai is a context-aware, voice and text enabled coaching experience
that adapts to the user's life — not just their workouts. Think of
it as a world-class personal trainer who lives in your pocket, knows
your sleep, your calendar, your stress, and your fitness history,
and guides you intelligently inside and outside the gym.

**Tagline:** See the strength ahead.

---

## Roles

**My role:** Product owner and sole developer.
- I will provide all UI designs as Pencil (.pen) diagram files
- I will provide all product decisions
- Do not make UI or design decisions — implement exactly what the
  diagrams show

**Your role:** Full technical co-builder.
- Implement SwiftUI screens faithfully from .pen diagrams provided
- Build and maintain full Supabase backend integration
- Architect and implement Kai AI coaching engine via Claude API
- Write clean, well documented, production-grade Swift code
- Follow best coding practices at all times
- Always run scripts through the Makefile
- Never write to production unless explicitly asked
- Document all major changes
- Ask clarifying questions before making assumptions

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS App | SwiftUI, iOS 18, Xcode 16 |
| Apple Watch | WatchOS + SwiftUI |
| AI Coach (Kai) | Claude API (Sonnet + Haiku) |
| Backend | Supabase (auth, Postgres, storage) |
| Subscriptions | RevenueCat |
| Voice output | ElevenLabs (Premium) / AVSpeechSynthesizer (Free) |
| Speech to text | Apple Speech Framework (on-device) |
| Calendar | EventKit (native iOS) |
| Health data | HealthKit + Apple Watch |
| Wearables (Phase 3) | Whoop API, Garmin Connect API |

---

## Kai — The AI Coach

Kai is the heart of Forzee. Every product decision centers around
making Kai smarter and the coaching experience better.

**Voice + Text:** Seamless, unified conversation. Same brain, same
history, switches naturally between voice and text. User can speak
at the gym and type on the couch — Kai never loses the thread.

**Kai's two contexts:**

**Inside the gym:**
- Real-time guidance through sessions
- Set and rep tracking
- Form cues (especially for novice users)
- In-session adaptations based on user feedback
- Voice-first interaction (hands are busy)

**Outside the gym:**
- Daily morning briefing (always free)
- Weekly debrief every Sunday
- Recovery and deload guidance
- Schedule-aware workout planning
- Proactive check-ins (never nagging)
- Insight generation over time

**Kai's personality:**
- Calm, confident, warm
- Adapts tone to user fitness level:
  - Novice: encouraging, educational, simple language
  - Intermediate: motivating, progressive, engaging
  - Advanced: direct, technical, respects their knowledge
- Never patronizing, never over-enthusiastic
- Speaks in short sentences during workouts
- Fuller, warmer conversation outside the gym

**Kai is NOT trained as a custom model.**
Kai's entire personality, philosophy, and expertise lives in a
carefully architected system prompt. Claude Sonnet + Haiku are
the underlying models.

---

## Model Routing

| Task | Model | Reason |
|---|---|---|
| Coach chat, workout generation, recovery advice, periodization, insights | Claude Sonnet | Needs full reasoning |
| Logging, confirmations, simple Q&A, notifications, daily briefing | Claude Haiku | Fast, cheap, sufficient |

**Never use Opus** — not needed for this use case.

---

## Context Pipeline

Every Sonnet call receives a compressed context snapshot:

```json
{
  "user": {
    "level": "intermediate",
    "goals": ["build_muscle", "lose_weight"],
    "equipment": ["full_gym"],
    "limitations": "left knee discomfort"
  },
  "recent_context": {
    "sleep_avg_7d": 6.8,
    "hrv_trend": "declining",
    "workouts_this_week": 2,
    "last_session": "Push — 3 days ago",
    "calendar_today": "busy_afternoon"
  },
  "conversation_summary": "Rolling summary of last 5 messages
    + compressed history. Never send full chat log."
}
```

**Token efficiency rules:**
- System prompt: cached, never resent raw
- Chat history: last 5 messages + rolling summary only
- Target: under 2,000 input tokens per Sonnet call

---

## Project Structure

```
Forzee/
├── App/
│   ├── ForzeeApp.swift
│   └── AppState.swift
├── Features/
│   ├── Onboarding/
│   ├── Coach/
│   ├── Workout/
│   ├── Progress/
│   └── Settings/
├── Integrations/
│   ├── HealthKit/
│   ├── Calendar/
│   └── Wearables/
├── Core/
│   ├── AI/
│   │   ├── KaiEngine.swift
│   │   ├── TaskClassifier.swift
│   │   ├── ContextBuilder.swift
│   │   └── UsageGate.swift
│   ├── Models/
│   ├── Network/
│   └── Storage/
└── Resources/
```

---

## Build Phases

### Phase 1 — The Coach
- Onboarding (goals, fitness level, equipment, schedule, permissions)
- Kai chat interface (text)
- Kai voice interface (seamless with text)
- Smart daily suggestions
- Daily morning briefing (free for all users)
- Voice-guided workouts
- Natural language workout editing
- Adaptive workout generator (novice → advanced)
- Exercise database with form cues
- Pre and post workout check-ins
- Progress tracking
- Progress photos
- Momentum score (replaces streaks — decays slowly, never breaks)
- Awards system (rewards smart behavior, not just output)
- Weekly coach debrief (every Sunday)
- Insight engine (patterns over time)
- Travel mode (auto-detects travel, switches programming)
- Just show up workout (minimum effective dose, one tap)
- Injury and limitation intelligence

### Phase 2 — Context Awareness
- Apple HealthKit integration
- Apple Watch app (WatchOS)
- Sleep data integration
- HRV and recovery signals
- Calendar integration (EventKit)
- Weather integration (WeatherKit)
- Stress signals (HealthKit)
- Nutrition and meal tracking
- Forzee readiness score (proprietary, combines all signals)
- Deload detection
- Premium paywall (RevenueCat)

### Phase 3 — Full Ecosystem
- Whoop API integration
- Garmin Connect API integration
- Deep analytics and insights
- Android (TBD)

---

## Database

Supabase schema SQL file will be provided separately.

**Tables:**
- `profiles` — user identity, fitness level, goals, equipment
- `exercises` — master exercise database with form cues
- `workout_plans` — AI-generated or template plans
- `workouts` — individual sessions with context snapshot
- `sessions` — actual performance log, RPE, mood, ratings
- `context_signals` — health and life signals (Phase 2)
- `coach_messages` — full Kai conversation history
- `progress_photos` — private, Supabase Storage backed
- `personal_records` — PR tracking per exercise
- `usage_tracking` — API call tracking, free tier enforcement

---

## Monetization

**Model:** Freemium + Premium Subscription (via RevenueCat)

| Feature | Free | Premium |
|---|---|---|
| Daily briefing | ✅ Always free | ✅ |
| Coach chat | 3 messages/day | Unlimited |
| AI workout generation | 1/week | Daily adaptive |
| Context-aware coaching | ❌ | ✅ Full signals |
| Voice (Kai) | AVSpeechSynthesizer | ElevenLabs |
| Nutrition tracking | ❌ | ✅ |
| Wearable integrations | ❌ | ✅ |
| Advanced insights | ❌ | ✅ |

**Pricing:** ~$12-15/month or ~$80/year

---

## Key Product Principles

1. **Kai is the product** — every feature either makes Kai smarter
   or the coaching experience better. If it doesn't, we don't build it

2. **No streaks** — replaced by Momentum, a score that decays slowly
   rather than breaks. Life happens, the coach understands

3. **Awards reward smart behavior** — rest days, comebacks, listening
   to your body — not just output and consistency

4. **Kai never nags** — it understands context before reaching out.
   Silence is respected

5. **Privacy first** — health data processed on-device where possible.
   Never sold. Users always in control of their data

6. **Free users build the habit** — daily briefing always free.
   Premium users get the full relationship

7. **Every user is welcome** — novice to advanced. Kai adapts,
   never intimidates, never patronizes

---

## Awards System

Awards should feel meaningful, not generic:

| Award | Trigger |
|---|---|
| Comeback | Returned after 2+ week gap and trained |
| Iron Will | Trained when readiness score was low |
| Consistent | 80% of planned workouts over 30 days |
| PR Streak | New personal record 3 sessions in a row |
| Early Bird / Night Owl | Discovered and committed to best training time |
| Listened to Your Body | Took a rest day when Kai recommended it |

---

## House Rules

- Never write to production unless explicitly told to
- Always document major changes
- Always run scripts through the Makefile
- Ask before assuming on anything ambiguous
- Flag concerns and push back when something doesn't make sense
- You are building this with me, not for me

---

## How To Start

1. Wait for .pen diagram files for each screen
2. Wait for Supabase schema SQL file
3. Ask any clarifying questions before writing code
4. Do not begin implementation until designs are provided
