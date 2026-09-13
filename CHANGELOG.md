# Forzee — Changelog

All notable changes to Forzee are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added — Surface AI connectivity, not just data sync (2026-09-13)

Kai is AI-centric — every chat reply, workout generation, and voice
command needs a live network call. Left unindicated, a dead connection
just makes the app look unresponsive rather than explaining itself.
Distinct from the Settings sync-status row from earlier (that one's
about whether *saved data* has reached the server — always succeeds
locally regardless of connection); this is "the thing you're about to
do needs Kai, and Kai needs a connection right now."

- **`Core/DesignSystem/ConnectivityNotice.swift`** — small reusable banner, reused everywhere below rather than one-off copy.
- **Coach tab**: banner above the input bar when offline; send button now disabled when offline (previously it would just fail with a raw network-error string after tapping); the daily briefing card explains a failed load instead of showing blank space when there's no connection.
- **Workout tab**: banner in place of "Generate Today's Workout" when offline; voice mode won't start offline (clear message instead of letting it fail); if the connection drops mid-workout while voice mode is already on, the status line and any failed command say so specifically — and make explicit that logged sets are still saved regardless, since that part really is offline-safe.
- Deliberately did not touch the gym companion comment (low-stakes, silent-fail is fine) or the post-workout report's existing fallback text (already explains itself) — scoped to the places where connectivity loss would otherwise look like the app just broke.

### Changed — Voice-logged sets now use real LLM understanding, not pattern matching (2026-09-13)

The first pass at this used local regex/keyword matching for latency
and offline reasons. Overridden on request: mid-workout voice commands
now go through Claude (Haiku), not hand-rolled parsing.

- **`Core/AI/ClaudeAPIClient.swift`** gained `completeWithTool` — forces a response through a single named tool (Anthropic's tool-use API), guaranteeing structured JSON back instead of prose. New `ClaudeTool` type (name/description/JSON-schema).
- **`Core/AI/WorkoutVoiceCommandPrompt.swift`** — the `workout_voice_command` tool schema (action: log_set/next_exercise/progress/chat, weight_value, weight_unit, reps, same_as_previous, spoken_reply) plus `WorkoutVoiceState`, a compact snapshot of current exercise/sets-so-far/last-logged-set/remaining-exercises handed to Claude so "same as previous" and "what's next" resolve against real state instead of the model guessing.
- **`KaiEngine.interpretWorkoutVoiceCommand`** — one Haiku tool-use call classifies the intent AND extracts weight/reps together. Haiku, not Sonnet: this fires mid-set, so speed still matters, and intent classification doesn't need Sonnet's depth — action == `chat` (genuinely open-ended questions) still escalates to a full `KaiEngine.chat` (Sonnet) call.
- Deleted `WorkoutVoiceCommandParser.swift` (the regex version) entirely.
- `WorkoutTabView` now calls the LLM for every recognized-shape command and speaks `spoken_reply` directly — Kai's own generated confirmation, not a hand-composed string. The actual data write (resolving "same as previous," the prescribed-weight fallback, appending the `LoggedSet`) still happens in app code, same as any voice-assistant integration acting on a parsed intent — that's state management, not the pattern-matching that was removed.
- **Tradeoff, stated directly since it was raised before and is now the deliberate choice**: this reintroduces a network dependency and per-command latency (~1s Haiku round-trip) that the local version avoided. With no connection, voice logging won't work — same as Coach chat. That's the accepted cost of real language understanding over fixed phrasing.
- Same sharp edge as before: `VoiceManager` is a shared singleton with one active listening session — Coach and Workout voice modes can't really both be on at once. Each stops listening on `onDisappear`, covering normal tab-switching, but there's no deeper arbitration.

### Added — A real final save for finished workouts (2026-09-13)

`sessions` has had `perceived_effort`, `mood_post`, `notes`, and
`rating` columns since the original Phase 1 schema — nothing in the
UI ever collected them, and "Finish Workout" saved silently with no
distinct completion moment.

- **`Core/Models/SessionFeedback.swift`** — effort (1-10 RPE), mood (great/good/okay/tired/rough, matching the schema comment exactly), a 1-5 rating, optional notes.
- **`WorkoutTabView`** — "Finish Workout" now opens a `SessionFeedbackSheet` ("How'd it go?") instead of saving immediately; "Skip" is one tap away for anyone who just wants it logged. "Save Session" there is the actual final save.
- One atomic local write, not a later update — the session id is generated client-side up front specifically because there's no reliable server-assigned id to update back onto until a queued write has actually synced (see the sync fix below). `saveCompletedWorkout` gained a `feedback:` parameter; both queued writes (`workouts`, `sessions`) still go through `SyncManager`, so this final save is exactly as offline-safe as the rest of the flow.
- The save and the AI report are shown as visibly separate states now: "Session saved" appears the instant the local write completes, the report fills in underneath once (if) the network call resolves — so a slow or failed report can never look like the workout didn't save.
- Fixed a real dead-end while in there: after finishing a workout there was no way back to generating a new one without leaving the tab. Added "Start a New Workout".

### Fixed — Offline-first writes: workouts and nutrition logs (2026-09-13)

Real bug, not a nice-to-have: `ForzeeDataService` wrote straight to
Supabase on every save, several calls via `try?` — no signal at the
gym meant the workout you just finished was silently gone. No retry,
no local copy.

- **`Core/Sync/PendingWrite.swift`** — a SwiftData model. Local disk write, always succeeds regardless of connectivity — this is the actual durability.
- **`Core/Sync/SyncManager.swift`** — `enqueue()` saves locally and returns immediately, never blocking on network. Upload happens opportunistically in the background, triggered by (a) connectivity transitioning offline → online (`NWPathMonitor`), (b) app foreground, (c) a 60s safety-net timer while open — never synchronously off an individual save, per "shouldn't be on every save."
- `ForzeeDataService.saveCompletedWorkout` and `saveNutritionEntry` now route through the queue instead of hitting the network directly — call sites in `WorkoutTabView`/`ProgressTabView` didn't need to change.
- A `Settings` row shows sync status (synced / N items waiting / no connection — saved on this device) — not a dashboard, just enough to trust the save actually happened.
- Retries up to 10 times per write, then stops auto-retrying (surfaced via the pending count, never silently dropped). Saves to disk immediately after each successful upload rather than batching — narrows the crash window where a retry could duplicate a row server-side.
- **Scope, stated plainly**: only workouts/sessions and nutrition logs are durable this way. Usage tracking, context signals, and chat messages are still best-effort `try?` — lower stakes if lost, and making everything durable is real additional work not attempted here.

### Added — Server-side push: the send-push Edge Function (2026-09-13)

First real backend component — no UI, deliberately. A secure,
authenticated primitive for sending a push notification, closing the
gap the local-notification system's own changelog entry called out.

- **`supabase/functions/send-push/index.ts`** — Supabase Edge Function (Deno). Holds the APNs private key as a server-side secret — it never ships to the client. Signs its own ES256 provider JWT per Apple's APNs spec (no external JWT library — Deno's Web Crypto API does the ECDSA signing directly) and posts to `api.push.apple.com` (or the sandbox host) over HTTP/2.
- **Authorization, not just authentication**: Supabase's gateway verifies the caller's JWT is valid before the function runs at all (`verify_jwt = true`); the function itself then only permits the **service role** (a cron job or backend process — can push to any user) or **a user pushing to themselves** (their JWT's `sub` matches the target `user_id`). Every other combination is rejected with 403 before any APNs call is made.
- **`device_tokens` table** (`forzee_schema.sql`) — RLS scoped to `auth.uid()`, so a client can register or remove only its own token. The function reads across all users via the service-role key, which bypasses RLS by design — that's the actual trust boundary, not the table.
- **iOS side**: `AppDelegate.swift` (bridged in via `@UIApplicationDelegateAdaptor`, since SwiftUI's `App` protocol has no hook for the APNs device-token callback) captures the token and saves it through `ForzeeDataService.saveDeviceToken`. `NotificationManager.requestAuthorization()` now also calls `registerForRemoteNotifications()` once local notification permission is granted.
- Dead tokens (APNs 400/410 responses) get deleted automatically on next send — no accumulating cruft.
- `aps-environment` entitlement — **same paid Apple Developer Program gate as HealthKit/WeatherKit**, called out directly in the function's README.
- `make deploy-functions` target; full setup (get an APNs Auth Key, `supabase link`, set 5 secrets, deploy) documented in `supabase/functions/send-push/README.md` since there's no CLI in this environment to actually run any of it.
- **Deliberately not built**: anything that decides *who* to push and *why* (e.g. "HRV crashed, suggest a rest day" computed from `context_signals`) — this function only sends when told to. That decision logic is a scheduled job (Supabase Cron/`pg_cron`) that doesn't exist yet; this is the primitive it would call.

### Added — Local notification system (2026-09-13)

- `Core/Notifications/NotificationManager.swift` — local notifications only, no APNs/server. Two kinds:
  - **Workout reminders**: recurring, one per training day picked in onboarding, at roughly the preferred time of day. Scheduled once onboarding completes.
  - **Re-engagement nudge**: rescheduled on every app foreground (`ForzeeApp`'s `scenePhase` — cancel pending, schedule a fresh one N days out); if the user doesn't reopen the app in time, it fires. This is what closes the gap Coach Mode: Accountability called out when it shipped — it can now actually reach the user outside the app. Advisory mode never schedules one; Guided gets a gentle 3-day nudge, Accountability a sharper 1-day one.
- Added as a 5th onboarding permission row (Notifications), and a Settings row to enable it later — though Settings can only default reminders to "morning" since onboarding's preferred time-of-day was never persisted to the profile (a pre-existing gap, not something this pass introduced).
- Tapping any notification opens the Coach tab.
- Cancelled entirely on sign out.
- **Not attempted**: server-driven push (APNs) for content computed server-side (e.g. "your HRV crashed, skip today") — that needs a backend component (device token storage, an APNs key, something to trigger sends) and is real, separate scope.

### Added — Voice chat: "Hi Kai" wake phrase (2026-09-13)

- `Integrations/Voice/VoiceManager.swift` — Speech + AVAudioEngine wake-phrase detection ("Hi Kai" / "Hey Kai") and speech-to-text, on-device recognition when the device supports it.
- `Integrations/Voice/KaiVoiceSynthesizer.swift` — speaks Kai's replies aloud. Free tier uses `AVSpeechSynthesizer` (system voice); Premium + a configured ElevenLabs key gets Kai's custom voice — this split was already staged in `Secrets.xcconfig.example`, just never wired up. Any ElevenLabs failure (network, quota, bad key) falls back to the system voice rather than going silent.
- `CoachView` — mic toggle in the nav bar starts the wake-phrase loop: say "Hi Kai", ask something, get a spoken reply, automatically back to listening. Voice-captured and typed messages share the same conversation thread and pipeline.
- **Known limitation, stated plainly**: this only works while the Coach screen is open and the phone is unlocked. iOS does not give third-party apps a Siri-style always-on background wake word — there's no public API for that. It also isn't gapless: `SFSpeechRecognitionTask` has to restart roughly every minute of audio, and a wake phrase spoken in that restart window could be missed. Real, usable, foreground-only — not Siri-grade.

### Added — Coach Mode: FSD-style autonomy levels for Kai (2026-09-13)

- New onboarding step 5 ("How much should Kai reach out?") — this was already reserved in the design (`OnboardingProgressBar` and every step screen's "Step X of 5" label predate this; step 5 was never built until now).
- Three levels, independent of fitness-level tone: **Advisory** (never initiates), **Guided** (default — proactive suggestions, user decides), **Accountability** (calls out avoidance instead of waiting to be asked).
- `UserProfile.coachMode` / `profiles.coach_mode` column, `CoachMode` enum (`Features/Onboarding/OnboardingViewModel.swift`), `OnboardingCoachModeView.swift`.
- `KaiSystemPrompt.coachModeGuide(for:)` — a second tone axis alongside the existing fitness-level guide, combined per user.
- Editable later in `SettingsView` (the onboarding screen promises "change any time in Settings" — this is that).
- **Known limitation, called out directly in the Accountability prompt**: this only changes what Kai says when the app is opened. It cannot reach the user outside the app — there's no push notification infrastructure yet, so "Accountability" mode today is honest tone, not real proactive nagging. That's separate, larger scope.

### Added — Workout tab + gym companion (2026-09-12)

- `Features/Workout/WorkoutTabView.swift` — replaces the Workout tab placeholder. Generate today's workout via `KaiEngine.generateWorkout`, check off exercises as they're done, finish to log the session and get a Sonnet-written post-workout report. Completion is tracked per exercise, not per set, for this first pass.
- `ForzeeDataService.saveCompletedWorkout` — persists the generated plan to `workouts` and the completion log to `sessions`.
- **Gym companion comments** — a short Haiku-generated remark fires after each exercise is checked off. Deliberately skips the full HealthKit/EventKit/WeatherKit context snapshot so it comes back fast between sets.
- **Model routing, made explicit**: gym companion comments → Haiku (speed + cost), workout reports → Sonnet (quality + format reliability), coaching chat → Sonnet (conversational depth, already the default). Added `gymCompanionComment` and `workoutReport` to `KaiTaskType`/`TaskClassifier`.

### Added — Phase 2: Context Awareness (2026-08-26)

**The life-signal pipeline**
- `Integrations/HealthKit/HealthKitManager.swift` — steps, active calories, 7-day sleep average, HRV trend (7d vs prior 7d), mindful minutes (stress proxy). Read-only, single authorization prompt for all types.
- `Integrations/Calendar/CalendarManager.swift` — EventKit; classifies today as `free` / `busy_morning` / `busy_afternoon` / `busy_all_day` / `travel` from event load and keyword detection.
- `Integrations/Weather/WeatherManager.swift` — CoreLocation + WeatherKit; current conditions plus an `outdoorFriendly` flag (temp/wind/condition thresholds) for indoor/outdoor workout routing.
- `Core/Models/ContextSignal.swift` — maps to `context_signals`; every signal ContextBuilder reads is now also persisted for trend history.
- `ForzeeDataService` — `insertContextSignal`, `fetchContextSignals`, `saveNutritionEntry`, `fetchNutritionToday`.
- `ContextBuilder.swift` — rewritten to assemble all Phase 2 signals in parallel alongside the Phase 1 profile/workout fetch, write-through to `context_signals`, and expand `UserContextSnapshot.RecentContext` with `stepsToday`, `stressMinutesToday`, `weatherCondition`, `outdoorFriendly`, `nutritionToday`. Every source degrades to `nil` on missing authorization — Kai never blocks on an absent signal.
- `OnboardingPermissionsView` — "Grant All" now actually calls `HealthKitManager`/`CalendarManager`/`WeatherManager` instead of the Phase 1 stub that just flipped toggles.

**Nutrition**
- `Core/Models/NutritionEntry.swift` + `nutrition_logs` table (schema + RLS) — manual meal logging (calories/protein/carbs/fat).
- `Features/Progress/ProgressTabView.swift` — today's macro summary + a log-a-meal sheet. Replaces the Progress tab placeholder. (Progress photos, PRs, and charts are still open Phase 1 items.)

**Premium paywall**
- `Core/Billing/PurchaseManager.swift` — RevenueCat wrapper: offerings, purchase, restore, and a `PurchasesDelegate` that syncs the `premium` entitlement into `AppState.subscriptionTier` and `profiles.subscription_tier`.
- `Features/Settings/PaywallView.swift`, `Features/Settings/SettingsView.swift` — replaces the Settings placeholder with subscription status, upgrade sheet, per-integration connect rows, and sign out.
- `AppState.shared` — weak static reference so singleton services can push state without being threaded through the view hierarchy.

**Coach**
- `Features/Coach/CoachView.swift` — replaces the Coach placeholder with the Phase 1 chat interface plus a Phase 2 proactive daily briefing card, powered by the now-context-aware `KaiEngine`.

**Config**
- `project.yml` — `Forzee.entitlements` (HealthKit + WeatherKit), `NSLocationWhenInUseUsageDescription`.
- `forzee_schema.sql` — `nutrition_logs` table, index, and RLS policy.

**Not in this pass** — WatchOS app and Whoop/Garmin integrations (Phase 2/3 PRD items) need their own Xcode target and hardware to validate; deferred rather than shipped unverifiable. This environment has no Xcode/Swift toolchain, so none of the above has been build-verified — run `make generate && make build` on macOS before merging.

### Added — Git workflow Makefile targets (2026-04-25)

- `make commit MSG="..."` — stage all changes and commit with the given message
- `make push` — push the current branch to `origin`
- `make ship MSG="..."` — commit + push in one shot
- Help text updated to list the new targets

Per house rule "always run scripts through the Makefile."

### Added — Project Scaffold (Phase 1 foundation)

**Project configuration**
- `project.yml` — XcodeGen project configuration for iOS 18, Xcode 16
- `Makefile` — All project scripts: `setup`, `generate`, `build`, `test`, `clean`, `open`, `lint`, `format`, `db-migrate-dev`
- `Secrets.xcconfig.example` — Template for API keys (Claude, Supabase, RevenueCat, ElevenLabs)
- `.gitignore` — Standard iOS ignore rules; `Secrets.xcconfig` explicitly excluded

**App layer**
- `ForzeeApp.swift` — App entry point; bootstraps SDKs before first render
- `AppBootstrap.swift` — Configures RevenueCat on launch
- `AppState.swift` — Central `@EnvironmentObject` owning auth, profile, subscription, and tab state
- `RootView.swift` — Auth gate → onboarding gate → main app routing
- `MainTabView.swift` — Root tab bar (Coach, Workout, Progress, Settings) with placeholder screens

**Core/AI — Kai engine**
- `KaiEngine.swift` — Main AI coaching interface; `chat()`, `generateWorkout()`, `generateDailyBriefing()`
- `ClaudeAPIClient.swift` — Low-level HTTP client for Claude Messages API (streaming + non-streaming)
- `KaiSystemPrompt.swift` — Kai's full identity, coaching philosophy, and tone-per-fitness-level system prompt
- `TaskClassifier.swift` — Routes tasks to Haiku vs Sonnet based on complexity
- `ContextBuilder.swift` — Assembles compressed user context snapshot per API call
- `UsageGate.swift` — Free-tier limit enforcement and usage recording
- `WorkoutGenerationPrompt.swift` — Prompt builder for workout generation and daily briefing

**Core/Models**
- `UserProfile.swift` — Maps to Supabase `profiles` table
- `SubscriptionTier.swift` — `free` | `premium` enum
- `GeneratedWorkout.swift` — Kai's generated workout + `WorkoutParser` for decoding Claude's JSON response
- `UsageRecord.swift` — Maps to Supabase `usage_tracking` table

**Core/Network**
- `ForzeeDataService.swift` — Singleton Supabase wrapper; auth, profile, messages, usage tracking (renamed from `SupabaseClient` — see Fixed)

**Feature stubs** (screens added as .pen diagrams are provided)
- `Features/Coach/`
- `Features/Workout/`
- `Features/Progress/`
- `Features/Settings/`

**Integration stubs** (implemented in Phase 2 & 3)
- `Integrations/HealthKit/`
- `Integrations/Calendar/`
- `Integrations/Wearables/`

**Core/DesignSystem**
- `ForzeeTheme.swift` — Full design token system: `fz*` colour extensions, `Color(hex:)` initialiser, `fzDisplay` / `fzHeading` / `fzBody` / `fzMono` font helpers (JetBrains Mono with SF Mono fallback), `ForzeeRadius` and `ForzeeSpacing` constants
- `ForzeeButton.swift` — `ForzeeButton` (primary, full-width, height 48, scale-on-press, haptic, loading + disabled states), `ForzeeTextButton` ghost variant, `PressedButtonStyle`
- `OnboardingProgressBar.swift` — 5-segment progress indicator (active = `fzPrimary`, inactive = `fzBorder`)

**Features/Onboarding — full flow implemented from `forezee.pen`**
- `OnboardingViewModel.swift` — `@MainActor ObservableObject`; enums for `FitnessLevel`, `TrainingGoal`, `Equipment`, `Weekday`, `TimeOfDay`; validation helpers; `complete(userId:)` persists profile to Supabase
- `OnboardingFlow.swift` — `OnboardingStep` enum (8 steps); `OnboardingFlowView` coordinator with step-state `@State`, forward/backward slide+opacity transitions, `advance()` / `goBack()` / `completeOnboarding()`
- `SplashView.swift` — "forzee" wordmark, teal radial glow, tagline, 2.2s auto-advance
- `OnboardingWelcomeView.swift` — Hero headline, "Get Started" CTA, sign-in text link
- `OnboardingFitnessLevelView.swift` — Step 1: `FitnessLevelCard` list, tap-to-advance with 200ms delay
- `OnboardingGoalsView.swift` — Step 2: `GoalPill` multi-select chips, Continue enabled ≥1 selected
- `OnboardingEquipmentView.swift` — Step 3: `EquipmentCell` 3×2 grid (110pt height), Continue enabled ≥1 selected
- `OnboardingScheduleView.swift` — Step 4: `DayCircle` day picker, `TimeSegmentedControl`, session length card; minimum 1 training day enforced
- `OnboardingPermissionsView.swift` — `PermissionRow` with `ForzeeToggleStyle` (custom `fzPrimary`/`fzBorder` toggle, spring-animated knob); "Grant All" / "Set up later"
- `MeetKaiView.swift` — `KaiRingsView` animated visualisation (outer/middle/inner rings + glow); `ProfileSummaryCard` dynamic summary from `OnboardingViewModel`; "Let's go" button with loading state

### Changed
- `RootView.swift` — Replaced `OnboardingPlaceholderView` placeholder with `OnboardingFlowView()`. Removed placeholder struct.

### Fixed
- Renamed `SupabaseClient` wrapper to `ForzeeDataService` to resolve naming collision with the Supabase Swift SDK's own exported `SupabaseClient` type. Updated all call sites across `AppBootstrap`, `AppState`, `ContextBuilder`, and `UsageGate`. Deleted original `SupabaseClient.swift`.

---

## How to start

```bash
# Clone the repo and run:
make setup

# Fill in Secrets.xcconfig with your API keys, then:
make open
```

See `Secrets.xcconfig.example` for all required keys.
