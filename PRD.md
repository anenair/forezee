# Product Requirements Document
## Forzee — AI Fitness Coach
**Version:** 1.0  
**Author:** Solo Founder  
**Last Updated:** April 2026  
**Status:** Approved for Development

---

## 1. Vision

A context-aware AI coaching app for self-motivated individuals getting back in shape. The AI coach understands your *life* — not just your workouts — adapting to your energy, schedule, sleep, and recovery without nagging you when life gets in the way.

**Core belief:** The best coach isn't the loudest one. It's the one that knows when to push and when to back off.

---

## 2. Target User

**Primary:** Self-motivated individuals looking to get or get back in shape

**Full spectrum (all welcome):**
- **Novice** — never worked out or just starting; needs education, form guidance, encouragement, simple language
- **Returning** — was fit before, rebuilding; needs realistic resets, no ego, confidence rebuilding
- **Intermediate** — consistent gym-goer; needs progressive overload, variety, kept engaged
- **Advanced / Hardcore** — athletes, powerlifters, experienced trainers; needs periodization, PR tracking, zero hand-holding, respected as knowledgeable

**Coaching adapts to the user's level** — detected at onboarding, continuously refined over time. A novice should never feel intimidated. An advanced user should never feel patronized.

---

## 3. Platform

| Phase | Platform |
|---|---|
| Phase 1 & 2 | iOS (iPhone + Apple Watch) |
| Phase 3+ | Android |

---

## 4. Monetization

**Model:** Freemium + Premium Subscription

| Tier | Price | Features |
|---|---|---|
| Free | $0 | Basic AI coaching, limited workout types, basic tracking, progress photos |
| Premium | ~$12-15/mo or ~$80/yr | Full context-aware AI, all integrations, voice coaching, nutrition tracking, deep analytics |

**Managed via:** RevenueCat

**Premium value story:** The more you use it, the better your coach gets at knowing you. Integrations (sleep, HRV, calendar, wearables) are the premium differentiator — they're what make the AI genuinely context-aware.

---

## 5. Core Differentiator

An AI coach powered by Claude API that reasons over a full life-signal pipeline:

| Signal | What the AI learns |
|---|---|
| Sleep data | Avoid hard sessions after poor sleep |
| HRV / recovery | Adjust intensity based on recovery score |
| Calendar | Know when a busy week is coming |
| HealthKit activity | Account for passive movement already done |
| Workout history | Understand long-term patterns and progress |

**Example:** *"You slept 5 hours, your HRV is low, and you have back-to-back meetings — here's a 15-minute mobility flow instead."* — without the user saying a word.

---

## 6. Feature Set by Phase

### Phase 1 — The Coach
**Goal:** Does the AI coach feel genuinely different?

- [ ] Onboarding flow (goals, schedule, equipment, fitness level)
- [ ] AI coach — chat interface
- [ ] AI coach — smart daily suggestions (no chat required)
- [ ] Voice-guided workouts
- [ ] Adaptive workout generator (bodyweight → advanced powerlifting / periodization)
- [ ] Coaching tone adapts to user level (encouraging for novice, technical for advanced)
- [ ] Form guidance & education layer (critical for novice safety)
- [ ] Exercise database / workout library
- [ ] Basic progress tracking
- [ ] Progress photos

### Phase 2 — Context Awareness
**Goal:** Does the app feel like it knows your life?

- [x] Apple HealthKit integration (steps, active calories, workouts) — read-only signals wired into ContextBuilder
- [ ] Apple Watch support (WatchOS app) — needs its own Xcode target; deferred
- [x] Sleep data integration (duration, quality, consistency) — 7-day average from HealthKit
- [x] HRV / recovery signal integration — trend classification (declining/stable/improving)
- [x] Calendar integration (EventKit) — busy days, travel, schedule shifts
- [x] Weather integration (CoreLocation + WeatherKit) — indoor/outdoor workout routing
- [x] Stress / mindfulness signals (HealthKit) — mindful minutes as proxy
- [x] Nutrition / meal tracking — manual macro logging + today's summary
- [x] AI proactive daily briefing — surfaces recommendations before user opens app
- [x] AI adapts workouts based on all signals passively (zero manual input) — full signal bundle now in every context snapshot
- [x] Premium paywall (RevenueCat) — offerings, purchase, restore, entitlement sync

Unbuilt/unverified: WatchOS app (Phase 3 hardware integrations — Whoop, Garmin — remain untouched).
None of this has been build-verified (no Xcode/Swift toolchain in this environment) — run `make generate && make build` on macOS.

### Phase 3 — Full Ecosystem
**Goal:** Revenue, retention, and platform expansion

- [ ] Whoop API integration
- [ ] Garmin Connect API integration
- [ ] Deep progress analytics & insights
- [ ] Android (React Native or Flutter port TBD)

---

## 7. Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| iOS App | SwiftUI | Native, best-in-class HealthKit & Watch support |
| Apple Watch | WatchOS + SwiftUI | Seamless HRV and activity access |
| AI Coach | Claude API (Sonnet) | Conversational + context-aware reasoning |
| Backend | Supabase | Auth, Postgres DB, realtime, storage |
| Subscriptions | RevenueCat | Best-in-class, saves weeks of work |
| Calendar | EventKit (native iOS) | Built into iOS, no extra dependency |
| Wearables (Phase 3) | Whoop API, Garmin Connect API | Third-party integrations |

---

## 8. Project Structure

```
Forzee/
├── App/
│   ├── ForzeeApp.swift
│   └── AppState.swift
├── Features/
│   ├── Onboarding/
│   ├── Coach/               ← Phase 1 core
│   ├── Workout/             ← Phase 1 core
│   ├── Progress/
│   └── Settings/
├── Integrations/
│   ├── HealthKit/           ← Phase 2
│   ├── Calendar/            ← Phase 2
│   └── Wearables/           ← Phase 3
├── Core/
│   ├── AI/                  ← Claude API client
│   ├── Models/
│   ├── Network/
│   └── Storage/
└── Resources/
```

---

## 9. AI Cost Architecture

**Model routing strategy:** Hybrid Haiku + Sonnet

| Task Type | Model |
|---|---|
| Logging, confirmations, simple Q&A, notifications | Claude Haiku |
| Coaching chat, workout generation, recovery advice, periodization | Claude Sonnet |

**Token efficiency rules (every Sonnet call):**
- System prompt: cached, never resent raw
- User profile: compressed JSON snapshot only
- Chat history: last 5 messages + rolling summary (never full log)
- Context signals: single structured snapshot object
- Target: under 2,000 input tokens per call

**Usage limits by tier:**
- Free: 3 coach chat messages/day, 1 AI workout generation/week, 1 daily briefing
- Premium: unlimited chat, daily adaptive workouts, full context-aware coaching

**Future (Phase 4+):**
- Forzee-trained human coaches (fully vetted, trained on Forzee methodology)
- No third-party coach marketplace — quality is non-negotiable
- Corporate / B2B wellness offering
- Contextual affiliate recommendations (equipment, gear)

---

## 10. Open Items

- [x] App name — **Forzee** ✅ ("Forza" + "Foresee" — See the strength ahead)
- [ ] App icon & brand direction — TBD
- [ ] Android timeline — deferred to post Phase 2

---

## 10. Success Metrics

| Metric | Goal |
|---|---|
| 6-month retention | Primary KPI — beats streak-based apps |
| Free → Premium conversion | >8% |
| Daily active usage | >4 days/week average |
| AI coach satisfaction | Qualitative feedback in reviews |
