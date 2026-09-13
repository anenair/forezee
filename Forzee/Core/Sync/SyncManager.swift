// ============================================================
// SyncManager.swift
// Forzee — Core/Sync
//
// Local-first write queue. `enqueue` always succeeds — it's a
// disk write via SwiftData, no network involved — so a save can
// never be lost to a dead signal at the gym. Actual upload to
// Supabase happens opportunistically in the background:
//   - when connectivity transitions from offline → online (NWPathMonitor)
//   - when the app comes to the foreground
//   - on a periodic safety-net timer while the app is open
// Never triggered synchronously by an individual save — that's
// the "not on every save" part.
//
// Scope: workouts/sessions and nutrition logs go through this
// (see ForzeeDataService). Lower-stakes writes — usage tracking,
// context signals, chat messages — stay best-effort for now;
// making everything durable is real additional scope, not
// attempted here.
// ============================================================

import Foundation
import SwiftData
import Network

@MainActor
final class SyncManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = SyncManager()

    // MARK: - Published State

    @Published private(set) var isOnline = true
    @Published private(set) var pendingCount = 0
    @Published private(set) var isSyncing = false

    // MARK: - Private

    private var modelContext: ModelContext?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.forzee.syncmanager.pathmonitor")

    /// A write that has failed this many times is left in the queue (never
    /// silently dropped) but stops being retried every sync pass — surfaced
    /// via `pendingCount` rather than jamming the queue on one bad row.
    private let maxAutoRetries = 10

    /// Shared encoding policy for every queued record: snake_case keys
    /// (matches Postgres column naming) and ISO8601 dates (matches every
    /// timestamp column). Types with explicit CodingKeys already in
    /// snake_case (e.g. DeviceTokenRecord) pass through unaffected —
    /// convertToSnakeCase is a no-op on a key that's already snake_case.
    private static let recordEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline, self.isOnline {
                    await self.syncPendingWrites()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Setup

    /// Call once, early (RootView.task) — SwiftData needs a live ModelContext.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await refreshPendingCount()
            if isOnline { await syncPendingWrites() }
        }
    }

    // MARK: - Enqueue

    /// Saves locally immediately. Always succeeds regardless of connectivity —
    /// this is the durable part. Kicks off a background sync attempt if
    /// already online, but the caller never waits on it.
    func enqueue<T: Encodable>(table: String, record: T) {
        guard let modelContext else {
            #if DEBUG
            print("SyncManager: enqueue before configure() — dropping write to \(table)")
            #endif
            return
        }
        do {
            let payload = try Self.recordEncoder.encode(record)
            modelContext.insert(PendingWrite(table: table, payloadJSON: payload))
            try modelContext.save()
            pendingCount += 1
        } catch {
            #if DEBUG
            print("SyncManager: local save failed for \(table) — \(error.localizedDescription)")
            #endif
        }

        if isOnline {
            Task { await syncPendingWrites() }
        }
    }

    // MARK: - Sync

    /// Uploads every queued write it can. Call from connectivity-restored,
    /// app-foreground, or a periodic timer — never from an individual save.
    func syncPendingWrites() async {
        guard let modelContext, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let descriptor = FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)])
        guard let writes = try? modelContext.fetch(descriptor), !writes.isEmpty else { return }

        for write in writes where write.retryCount <= maxAutoRetries {
            do {
                let values = try JSONSerialization.jsonObject(with: write.payloadJSON) as? [String: Any] ?? [:]
                try await ForzeeDataService.shared.rawInsert(table: write.table, values: values)
                modelContext.delete(write)
                // Save immediately after each success, not batched at the end of the
                // loop — narrows the crash window between "upload succeeded" and
                // "locally marked done" to a single write instead of the whole pass,
                // which matters here: a retried insert after that gap could duplicate
                // a workout/session server-side rather than just resend safely.
                try? modelContext.save()
            } catch {
                write.retryCount += 1
                #if DEBUG
                print("SyncManager: sync failed for \(write.table) (attempt \(write.retryCount)) — \(error.localizedDescription)")
                #endif
            }
        }

        try? modelContext.save()
        await refreshPendingCount()
    }

    private func refreshPendingCount() async {
        guard let modelContext else { return }
        pendingCount = (try? modelContext.fetchCount(FetchDescriptor<PendingWrite>())) ?? 0
    }
}
