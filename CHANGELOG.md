# Forzee — Changelog

All notable changes to Forzee are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

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
