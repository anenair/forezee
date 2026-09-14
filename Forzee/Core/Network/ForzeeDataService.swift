// ============================================================
// ForzeeDataService.swift
// Forzee — Core/Network
//
// Singleton wrapper around the Supabase Swift SDK.
// All database reads and writes go through this service.
//
// Renamed from SupabaseClient → ForzeeDataService to avoid
// naming collision with the Supabase Swift SDK's own
// `SupabaseClient` type.
//
// Tables covered here:
//   - profiles       (auth + user fitness context)
//   - coach_messages (Kai conversation history)
//   - usage_tracking (free tier enforcement + cost monitoring)
//
// Workout, session, and other tables will be added as those
// features are built in Phase 1.
//
// Rules:
//   - Never call this directly from SwiftUI views
//   - All methods are async throws
//   - Uses Supabase RLS — the user can only read/write their own data
// ============================================================

import Foundation
import Supabase

final class ForzeeDataService {

    // MARK: - Shared Instance

    static let shared = ForzeeDataService()

    // MARK: - Supabase Client

    private let client: Supabase.SupabaseClient

    // MARK: - Init

    private init() {
        let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""

        guard let supabaseURL = URL(string: url), !key.isEmpty,
              !url.hasPrefix("https://your-project") else {
            // Return a placeholder client — will fail gracefully on any real calls
            // until the developer fills in Secrets.xcconfig
            #if DEBUG
            print("⚠️  ForzeeDataService: URL or key not configured. Fill in Secrets.xcconfig.")
            #endif
            self.client = Supabase.SupabaseClient(
                supabaseURL: URL(string: "https://placeholder.supabase.co")!,
                supabaseKey: "placeholder"
            )
            return
        }

        self.client = Supabase.SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: - Auth

    /// Attempt to restore an existing user session.
    /// Calls the completion handler with the user ID if a valid session exists.
    func restoreSession(completion: @escaping (String?) async -> Void) async {
        do {
            let session = try await client.auth.session
            // With emitLocalSessionAsInitialSession opted in, the SDK now hands back
            // whatever session is on disk even if it's expired — this used to be
            // filtered out for us, so the check moves here.
            guard !session.isExpired else {
                await completion(nil)
                return
            }
            await completion(session.user.id.uuidString)
        } catch {
            await completion(nil)
        }
    }

    /// Sign in with email and password.
    func signIn(email: String, password: String) async throws -> String {
        let session = try await client.auth.signIn(email: email, password: password)
        return session.user.id.uuidString
    }

    /// Sign up with email and password.
    /// Supabase trigger automatically creates the profile row on signup.
    func signUp(email: String, password: String, fullName: String?) async throws -> String {
        let session = try await client.auth.signUp(
            email: email,
            password: password,
            data: fullName.map { ["full_name": AnyJSON.string($0)] } ?? [:]
        )
        return session.user.id.uuidString
    }

    /// Sign out and clear the local session.
    func signOut() async {
        try? await client.auth.signOut()
    }

    // MARK: - Profiles

    /// Fetch the user's profile from the `profiles` table.
    func fetchProfile(userId: String) async throws -> UserProfile {
        let response = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()

        // Postgres timestamps come back as ISO8601 strings — the default
        // JSONDecoder expects a numeric epoch and fails on those, which
        // silently drops the whole profile (every caller here uses try?)
        // and falls back to onboarding-default values (novice, bodyweight,
        // 45 min) regardless of what the user actually set.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserProfile.self, from: response.data)
    }

    /// Update profile fields. Pass only the fields you want to change.
    ///
    /// Takes `[String: Any]` for caller convenience (plain dictionary
    /// literals), but the Supabase Swift SDK's `.update()` requires a
    /// concrete `Encodable` type — `Any` itself doesn't conform. Converted
    /// internally to `[String: AnyJSON]` (Supabase's own type-erased JSON
    /// value, which is Encodable) via a JSON round-trip.
    func updateProfile(_ updates: [String: Any], userId: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: updates)
        let payload = try JSONDecoder().decode([String: AnyJSON].self, from: data)

        try await client
            .from("profiles")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Coach Messages

    /// Fetch recent coach messages for a user (last N messages).
    func fetchRecentMessages(userId: String, limit: Int = 50) async throws -> [StoredMessage] {
        let response = try await client
            .from("coach_messages")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messages = try decoder.decode([StoredMessage].self, from: response.data)
        return messages.reversed()  // Return chronological order
    }

    /// Save a coach message to the `coach_messages` table.
    func saveMessage(_ message: KaiMessage, userId: String) async throws {
        let record: [String: AnyJSON] = [
            "user_id": .string(userId),
            "role": .string(message.role.rawValue),
            "content": .string(message.content)
        ]
        try await client
            .from("coach_messages")
            .insert(record)
            .execute()
    }

    // MARK: - Context Signals (Phase 2)

    /// Persist a life signal (sleep, HRV, steps, stress, calendar, weather) for trend history.
    /// Best-effort — callers should treat failures as non-fatal.
    func insertContextSignal(_ signal: ContextSignal) async throws {
        let data = try JSONEncoder().encode(signal)
        let payload = try JSONDecoder().decode([String: AnyJSON].self, from: data)

        try await client
            .from("context_signals")
            .insert(payload)
            .execute()
    }

    /// Fetch recent history for a single signal type, most recent first.
    func fetchContextSignals(
        userId: String,
        signalType: ContextSignal.SignalType,
        limit: Int = 30
    ) async throws -> [ContextSignal] {
        let response = try await client
            .from("context_signals")
            .select()
            .eq("user_id", value: userId)
            .eq("signal_type", value: signalType.rawValue)
            .order("recorded_at", ascending: false)
            .limit(limit)
            .execute()

        return try JSONDecoder().decode([ContextSignal].self, from: response.data)
    }

    // MARK: - Nutrition (Phase 2)

    /// Save a manually logged meal. Local-first via SyncManager — always
    /// succeeds even with no connection; uploads opportunistically.
    func saveNutritionEntry(_ entry: NutritionEntry) async throws {
        await SyncManager.shared.enqueue(table: "nutrition_logs", record: entry)
    }

    /// Fetch and aggregate today's logged nutrition for the context snapshot and Progress tab.
    func fetchNutritionToday(userId: String) async throws -> NutritionSummary {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let formatter = ISO8601DateFormatter()

        let response = try await client
            .from("nutrition_logs")
            .select()
            .eq("user_id", value: userId)
            .gte("logged_at", value: formatter.string(from: startOfDay))
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([NutritionEntry].self, from: response.data)

        return NutritionSummary(
            totalCalories: entries.reduce(0) { $0 + $1.calories },
            totalProteinG: entries.reduce(0) { $0 + $1.proteinG },
            entryCount: entries.count
        )
    }

    // MARK: - Device Tokens (push notifications)

    /// Registers or refreshes this device's APNs token for the signed-in user.
    /// RLS restricts this to the caller's own rows — see forzee_schema.sql.
    func saveDeviceToken(_ token: String, environment: String, userId: String) async throws {
        let record = DeviceTokenRecord(userId: userId, token: token, environment: environment)
        let data = try JSONEncoder().encode(record)
        let payload = try JSONDecoder().decode([String: AnyJSON].self, from: data)

        try await client
            .from("device_tokens")
            .upsert(payload, onConflict: "user_id,token")
            .execute()
    }

    private struct DeviceTokenRecord: Encodable {
        let userId: String
        let token: String
        let environment: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case environment
        }
    }

    // MARK: - Workouts (Phase 1 — logging)

    /// Persists a Kai-generated workout as completed: which exercises were
    /// checked off, the actual per-set weight/reps logged (voice or manual —
    /// see LoggedSet), and the user's post-session feedback. The final save
    /// that closes out a workout. Local-first via SyncManager — this is
    /// exactly the "finished a workout with no gym WiFi" case, so it must
    /// never depend on being online. Two queued writes: `workouts` (the plan
    /// + context snapshot at generation time) and `sessions` (the completion
    /// record — one atomic local save, not a later update, since there's no
    /// reliable server-assigned id to update onto until this has synced).
    func saveCompletedWorkout(
        _ workout: GeneratedWorkout,
        completedExerciseIds: Set<UUID>,
        loggedSets: [LoggedSet],
        feedback: SessionFeedback,
        userId: String
    ) async throws {
        let workoutRecord = WorkoutInsertRecord(
            id: workout.id.uuidString,
            userId: userId,
            name: workout.name,
            workoutType: workout.workoutType,
            estimatedDurationMins: workout.estimatedDurationMins,
            contextSnapshot: workout.contextSnapshot,
            status: "completed",
            exercises: workout.exercises
        )
        await SyncManager.shared.enqueue(table: "workouts", record: workoutRecord)

        let setRecords: [LoggedSetRecord] = workout.exercises
            .filter { completedExerciseIds.contains($0.id) }
            .flatMap { exercise -> [LoggedSetRecord] in
                let voiceLogged = loggedSets
                    .filter { $0.exerciseId == exercise.id }
                    .sorted { $0.setNumber < $1.setNumber }

                guard !voiceLogged.isEmpty else {
                    // Tap-completed with no per-set detail — one approximate
                    // entry per prescribed set rather than losing the exercise
                    // entirely. weightKg here is the AI's suggestion, not a
                    // measured value.
                    return (1...max(exercise.sets, 1)).map { setNumber in
                        LoggedSetRecord(
                            exerciseId: exercise.exerciseId,
                            exerciseName: exercise.name,
                            setNumber: setNumber,
                            weightKg: exercise.weightKg,
                            reps: nil,
                            restSecs: exercise.restSecs
                        )
                    }
                }
                return voiceLogged.map { set in
                    LoggedSetRecord(
                        exerciseId: exercise.exerciseId,
                        exerciseName: exercise.name,
                        setNumber: set.setNumber,
                        weightKg: set.weightValue.map { set.weightUnit == .lbs ? $0 * 0.453592 : $0 },
                        reps: set.reps,
                        restSecs: set.restSecs ?? exercise.restSecs
                    )
                }
            }

        let sessionRecord = SessionInsertRecord(
            id: UUID().uuidString,
            userId: userId,
            workoutId: workout.id.uuidString,
            durationMins: workout.estimatedDurationMins,
            setsLog: setRecords,
            perceivedEffort: feedback.perceivedEffort,
            moodPost: feedback.mood?.rawValue,
            notes: feedback.notes?.isEmpty == false ? feedback.notes : nil,
            rating: feedback.rating
        )
        await SyncManager.shared.enqueue(table: "sessions", record: sessionRecord)
    }

    /// Fetch recent completed sessions (most recent first), joined with the
    /// originating workout's name/type via a PostgREST embed — one round
    /// trip instead of N+1 lookups. Powers the Progress tab's history feed
    /// and per-exercise history (Workout tab "History" button), both of
    /// which just filter/aggregate this same result set client-side rather
    /// than needing their own bespoke queries.
    func fetchSessionHistory(userId: String, limit: Int = 30) async throws -> [SessionHistoryEntry] {
        let response = try await client
            .from("sessions")
            .select("*, workouts(name, workout_type, exercises)")
            .eq("user_id", value: userId)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SessionHistoryEntry].self, from: response.data)
    }

    /// Direct, immediate network insert — used only by SyncManager when
    /// actually uploading a queued write. Never call this straight from a
    /// view or view model; that would defeat the offline-first guarantee.
    /// Takes the already-encoded JSON payload directly (SyncManager stores
    /// it as Data) and decodes straight into `[String: AnyJSON]` — the
    /// Supabase SDK's Encodable requirement, same reasoning as updateProfile.
    func rawInsert(table: String, payload: Data) async throws {
        let values = try JSONDecoder().decode([String: AnyJSON].self, from: payload)
        try await client.from(table).insert(values).execute()
    }

    private struct WorkoutInsertRecord: Encodable {
        let id: String
        let userId: String
        let name: String
        let workoutType: String
        let estimatedDurationMins: Int
        let contextSnapshot: UserContextSnapshot?
        let status: String
        let exercises: [WorkoutExercise]
    }

    private struct SessionInsertRecord: Encodable {
        let id: String
        let userId: String
        let workoutId: String
        let durationMins: Int
        let setsLog: [LoggedSetRecord]
        let perceivedEffort: Int?
        let moodPost: String?
        let notes: String?
        let rating: Int?
    }

    /// Matches the `sets_log` jsonb structure documented in forzee_schema.sql:
    /// `[{ exercise_id, set_number, reps_completed, weight_kg, rpe }]`.
    private struct LoggedSetRecord: Encodable {
        let exerciseId: String?
        let exerciseName: String
        let setNumber: Int
        let weightKg: Double?
        let reps: Int?
        let restSecs: Int?
    }

    // MARK: - Usage Tracking

    /// Insert a usage record for cost monitoring and free-tier enforcement.
    func insertUsageRecord(_ record: UsageRecord) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(record)
        let payload = try JSONDecoder().decode([String: AnyJSON].self, from: data)

        try await client
            .from("usage_tracking")
            .insert(payload)
            .execute()
    }
}

// MARK: - SessionHistoryEntry

/// A completed session as read back from Supabase, with its originating
/// workout's name/type embedded. Mirrors `LoggedSetRecord`'s shape above —
/// `sets_log` was written with `convertToSnakeCase`, so it decodes the same
/// way in reverse.
struct SessionHistoryEntry: Codable, Identifiable {
    let id: String
    let workoutId: String?
    let startedAt: Date
    let completedAt: Date?
    let durationMins: Int?
    let setsLog: [SessionSetEntry]
    let rating: Int?
    let workout: SessionWorkoutInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMins = "duration_mins"
        case setsLog = "sets_log"
        case rating
        case workout = "workouts"
    }

    /// Distinct exercises touched in this session.
    var exerciseCount: Int {
        Set(setsLog.compactMap(\.exerciseName)).count
    }

    /// Σ weight × reps across every logged set — nil weight/reps (a
    /// tap-completed exercise with no per-set detail) contributes 0, not a
    /// crash, so an approximate session still shows a real if partial total.
    var totalVolumeKg: Double {
        setsLog.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }
}

struct SessionSetEntry: Codable {
    let exerciseId: String?
    let exerciseName: String?
    let setNumber: Int?
    let weightKg: Double?
    let reps: Int?
    let restSecs: Int?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case setNumber = "set_number"
        case weightKg = "weight_kg"
        case reps
        case restSecs = "rest_secs"
    }
}

struct SessionWorkoutInfo: Codable {
    let name: String
    let workoutType: String
    /// The prescribed exercises, muscle-group tags included — what
    /// InsightsEngine cross-references against a session's own sets_log
    /// (which only carries exercise_name, not muscle group) to attribute
    /// logged sets to a muscle group.
    let exercises: [WorkoutExercise]?

    enum CodingKeys: String, CodingKey {
        case name
        case workoutType = "workout_type"
        case exercises
    }
}

// MARK: - StoredMessage

/// A coach message as stored in Supabase (includes DB metadata).
struct StoredMessage: Codable {
    let id: String
    let userId: String
    let role: String
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case role
        case content
        case createdAt = "created_at"
    }

    /// Convert to a KaiMessage for use in the AI engine.
    func toKaiMessage() -> KaiMessage {
        KaiMessage(
            id: UUID(uuidString: id) ?? UUID(),
            role: KaiRole(rawValue: role) ?? .user,
            content: content,
            createdAt: createdAt
        )
    }
}
