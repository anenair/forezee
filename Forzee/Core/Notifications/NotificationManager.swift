// ============================================================
// NotificationManager.swift
// Forzee — Core/Notifications
//
// Local notifications only — no server, no APNs. Two things:
//
//   1. Workout reminders — recurring, one per training day picked
//      in onboarding, at roughly the preferred time of day.
//   2. Re-engagement nudge — rescheduled every time the app comes
//      to the foreground; if the user doesn't come back within N
//      days it fires. This is what makes Coach Mode: Accountability
//      actually reach the user outside the app, closing the gap
//      called out when that feature shipped. Respects Coach Mode:
//      Advisory never gets a nudge.
//
// A real server-driven push system (APNs, computed server-side —
// e.g. "HRV crashed, skip today") is a separate, larger piece of
// work requiring a backend component. Not attempted here.
// ============================================================

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = NotificationManager()

    // MARK: - Published State

    @Published private(set) var isAuthorized = false

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()

    private enum Identifier {
        static let reengagement = "forzee.reengagement"
        static func workoutReminder(_ day: Weekday) -> String { "forzee.workout.\(day.rawValue)" }
    }

    private override init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Workout Reminders

    /// Schedules a recurring local reminder for each selected training day.
    /// Idempotent — cancels any previously scheduled reminders first.
    func scheduleWorkoutReminders(days: Set<Weekday>, time: TimeOfDay) {
        cancelWorkoutReminders()
        guard isAuthorized, !days.isEmpty else { return }

        for day in days {
            let content = UNMutableNotificationContent()
            content.title = "Forzee"
            content.body = workoutReminderBody(for: time)
            content.sound = .default

            var components = DateComponents()
            components.weekday = day.calendarWeekday
            components.hour = time.notificationHour
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Identifier.workoutReminder(day),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func cancelWorkoutReminders() {
        center.removePendingNotificationRequests(
            withIdentifiers: Weekday.allCases.map(Identifier.workoutReminder)
        )
    }

    private func workoutReminderBody(for time: TimeOfDay) -> String {
        switch time {
        case .morning:   return "Today's session is ready whenever you are this morning."
        case .afternoon: return "Got a session on deck for this afternoon."
        case .evening:   return "Tonight's workout is queued up."
        }
    }

    // MARK: - Re-engagement Nudge

    /// Call whenever the app becomes active. Cancels any pending nudge and
    /// schedules a fresh one N days out — if the user hasn't reopened the
    /// app by then, it fires. Advisory mode never schedules one at all.
    func scheduleReengagementNudge(coachMode: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.reengagement])
        guard isAuthorized, coachMode != "advisory" else { return }

        let (daysOut, body) = reengagementCopy(for: coachMode)
        guard let fireDate = Calendar.current.date(byAdding: .day, value: daysOut, to: .now) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Kai"
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.reengagement, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelReengagementNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.reengagement])
    }

    private func reengagementCopy(for coachMode: String) -> (daysOut: Int, body: String) {
        switch coachMode {
        case "accountability":
            return (1, "It's been a day. Busy, or avoiding it? Either's fine — just tell me.")
        default: // "guided"
            return (3, "No pressure — just checking in. Whenever you're ready.")
        }
    }

    // MARK: - Sign Out

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Show the banner + sound even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Tapping any Forzee notification opens the Coach tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            AppState.shared?.activeTab = .coach
        }
        completionHandler()
    }
}

// MARK: - Weekday / TimeOfDay → Scheduling

private extension Weekday {
    /// `DateComponents.weekday` convention: 1 = Sunday ... 7 = Saturday.
    var calendarWeekday: Int {
        switch self {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        }
    }
}

private extension TimeOfDay {
    var notificationHour: Int {
        switch self {
        case .morning:   return 7
        case .afternoon: return 13
        case .evening:   return 18
        }
    }
}
