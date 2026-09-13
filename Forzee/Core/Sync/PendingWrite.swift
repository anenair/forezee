// ============================================================
// PendingWrite.swift
// Forzee — Core/Sync
//
// A queued write waiting to reach Supabase. Lives entirely on
// disk (SwiftData) so it survives with zero connectivity —
// exactly the "no WiFi at the gym" case. Sync is a background
// convenience on top of this; the local write is what's durable.
// ============================================================

import Foundation
import SwiftData

@Model
final class PendingWrite {
    var id: UUID
    var table: String
    var payloadJSON: Data
    var createdAt: Date
    var retryCount: Int

    init(table: String, payloadJSON: Data) {
        self.id = UUID()
        self.table = table
        self.payloadJSON = payloadJSON
        self.createdAt = .now
        self.retryCount = 0
    }
}
