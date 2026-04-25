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
