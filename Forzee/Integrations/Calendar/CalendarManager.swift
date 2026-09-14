// ============================================================
// CalendarManager.swift
// Forzee — Integrations/Calendar
//
// Phase 2: reads EventKit to classify how busy the user's day
// is, so Kai can plan around back-to-back meetings or travel
// without the user having to say anything.
// ============================================================

import Foundation
import EventKit

@MainActor
final class CalendarManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = CalendarManager()

    // MARK: - Published State

    @Published var isAuthorized: Bool = false

    // MARK: - Private

    private let store = EKEventStore()
    private let travelKeywords = ["flight", "travel", "airport", "trip", "layover"]

    private init() {
        isAuthorized = Self.currentAuthorizationGranted()
    }

    // MARK: - Authorization

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            // Deployment target is iOS 18.0, so the granular full/write-only
            // access API (iOS 17+) is always available — no need to branch
            // on the deprecated all-or-nothing requestAccess(to:).
            isAuthorized = try await store.requestFullAccessToEvents()
        } catch {
            #if DEBUG
            print("CalendarManager: authorization failed — \(error.localizedDescription)")
            #endif
            isAuthorized = false
        }
        return isAuthorized
    }

    private static func currentAuthorizationGranted() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - Signals

    /// Classifies today's calendar load for the context snapshot.
    /// Returns "travel" | "busy_all_day" | "busy_morning" | "busy_afternoon" | "free"
    func todayBusyness() async -> String? {
        guard isAuthorized else { return nil }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: .now)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay }

        if events.contains(where: isTravelEvent) { return "travel" }
        if events.isEmpty { return "free" }

        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        let morningBusy = busyMinutes(events: events, from: startOfDay, to: noon) >= 120
        let afternoonBusy = busyMinutes(events: events, from: noon, to: endOfDay) >= 120

        switch (morningBusy, afternoonBusy) {
        case (true, true):   return "busy_all_day"
        case (false, true):  return "busy_afternoon"
        case (true, false):  return "busy_morning"
        case (false, false): return "free"
        }
    }

    // MARK: - Private

    private func busyMinutes(events: [EKEvent], from: Date, to: Date) -> Double {
        events.reduce(0.0) { total, event in
            let overlapStart = max(event.startDate, from)
            let overlapEnd = min(event.endDate, to)
            guard overlapEnd > overlapStart else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart) / 60.0
        }
    }

    private func isTravelEvent(_ event: EKEvent) -> Bool {
        let haystack = [event.title, event.location]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return travelKeywords.contains { haystack.contains($0) }
    }
}
