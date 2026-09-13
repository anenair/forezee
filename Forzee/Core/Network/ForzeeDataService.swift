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

        self.client = Supabase.SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
    }

    // MARK: - Auth

    /// Attempt to restore an existing user session.
    /// Calls the completion handler with the user ID if a valid session exists.
    func restoreSession(completion: @escaping (String?) async -> Void) async {
        do {
            let session = try await client.auth.session
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

        return try JSONDecoder().decode(UserProfile.self, from: response.data)
    }

    /// Update profile fields. Pass only the fields you want to change.
    func updateProfile(_ updates: [String: Any], userId: String) async throws {
        try await client
            .from("profiles")
            .update(updates)
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

        let messages = try JSONDecoder().decode([StoredMessage].self, from: response.data)
        return messages.reversed()  // Return chronological order
    }

    /// Save a coach message to the `coach_messages` table.
    func saveMessage(_ message: KaiMessage, userId: String) async throws {
        let record: [String: Any] = [
            "user_id": userId,
            "role": message.role.rawValue,
            "content": message.content
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
        let encoder = JSONEncoder()
        let data = try encoder.encode(signal)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await client
            .from("context_signals")
            .insert(dict)
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
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await client
            .from("device_tokens")
            .upsert(dict, onConflict: "user_id,token")
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
                            reps: nil
                        )
                    }
                }
                return voiceLogged.map { set in
                    LoggedSetRecord(
                        exerciseId: exercise.exerciseId,
                        exerciseName: exercise.name,
                        setNumber: set.setNumber,
                        weightKg: set.weightValue.map { set.weightUnit == .lbs ? $0 * 0.453592 : $0 },
                        reps: set.reps
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

    /// Direct, immediate network insert — used only by SyncManager when
    /// actually uploading a queued write. Never call this straight from a
    /// view or view model; that would defeat the offline-first guarantee.
    func rawInsert(table: String, values: [String: Any]) async throws {
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
    }

    // MARK: - Usage Tracking

    /// Insert a usage record for cost monitoring and free-tier enforcement.
    func insertUsageRecord(_ record: UsageRecord) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(record)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await client
            .from("usage_tracking")
            .insert(dict)
            .execute()
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
