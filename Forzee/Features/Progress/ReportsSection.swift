// ============================================================
// ReportsSection.swift
// Forzee — Features/Progress
//
// Month/Year rollups of the user's fitness journey — total
// sessions, total volume, most-trained muscle group, most-repeated
// workout and how many times it's been done, and Momentum. Pure
// aggregation (InsightsEngine.periodReport), no AI call — free,
// same reasoning as the Log tab and plate calculator: the number
// is free, Kai narrating what it means is the premium layer
// (Kai's Weekly Read, already gated, covers that).
//
// Also renders an actual calendar (WorkoutCalendarView below) — always
// a single month's grid, marking each day a session happened with an
// icon for that session's workout type. Tapping a marked day opens
// SessionDetailView for that exact day's logged exercises.
//
// Both the stats and the calendar are navigable to a past month/year
// (PeriodNavigator below), not locked to "now" — that only works
// because ProgressTabView fetches this section's full session
// history rather than just the current year to date; see
// loadReportSessions there.
// ============================================================

import SwiftUI

enum ReportPeriod: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }
    var label: String { self == .month ? "Month" : "Year" }
}

struct ReportsSection: View {
    let sessions: [SessionHistoryEntry]
    @Binding var period: ReportPeriod

    /// The single month currently being viewed. The calendar below always
    /// shows exactly this one month — Year mode changes what the ReportCard
    /// aggregates (that month's whole year) but never expands the calendar
    /// into a month list. Chevrons always step by month, in both modes,
    /// so "left/right" has one consistent meaning throughout this section.
    @State private var anchor: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            HStack {
                Text("Report")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Picker("", selection: $period) {
                    ForEach(ReportPeriod.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            PeriodNavigator(anchor: $anchor)

            ReportCard(report: currentReport, period: period)

            WorkoutCalendarView(sessions: sessions, monthDate: anchor)
        }
    }

    private var currentReport: InsightsEngine.PeriodReport {
        switch period {
        case .month:
            return InsightsEngine.periodReport(
                sessions: sessions,
                since: InsightsEngine.startOfMonth(anchor),
                until: min(InsightsEngine.endOfMonth(anchor), .now)
            )
        case .year:
            return InsightsEngine.periodReport(
                sessions: sessions,
                since: InsightsEngine.startOfYear(anchor),
                until: min(InsightsEngine.endOfYear(anchor), .now)
            )
        }
    }
}

// MARK: - PeriodNavigator

/// Chevron navigation to move the viewed month back and forward — without
/// this, "Report" could only ever show the current month, with no way to
/// browse to any other one. Always steps by month regardless of the
/// Month/Year segmented control — that control only changes what the
/// ReportCard aggregates, never how these chevrons behave.
private struct PeriodNavigator: View {
    @Binding var anchor: Date

    private var calendar: Calendar { .current }

    var body: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            Spacer()
            Text(label)
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)
            Spacer()
            Button(action: goForward) {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
        }
        .foregroundStyle(Color.fzTextSecondary)
        .buttonStyle(.plain)
    }

    private var label: String {
        anchor.formatted(.dateTime.month(.wide).year())
    }

    /// Never lets the user navigate into a month that hasn't happened yet.
    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: anchor) else { return false }
        return InsightsEngine.startOfMonth(next) <= .now
    }

    private func goBack() {
        withAnimation {
            if let prev = calendar.date(byAdding: .month, value: -1, to: anchor) { anchor = prev }
        }
    }

    private func goForward() {
        guard canGoForward else { return }
        withAnimation {
            if let next = calendar.date(byAdding: .month, value: 1, to: anchor) { anchor = next }
        }
    }
}

// MARK: - ReportCard

private struct ReportCard: View {
    let report: InsightsEngine.PeriodReport
    let period: ReportPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if report.totalSessions == 0 {
                Text("No workouts logged this \(period.label.lowercased()) yet.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else {
                HStack(spacing: ForzeeSpacing.sectionGap) {
                    ReportStat(value: "\(report.totalSessions)", label: "sessions")
                    ReportStat(value: "\(Int(report.totalVolumeKg))", label: "kg volume")
                    ReportStat(value: "\(report.momentumScore)", label: "momentum")
                }

                if let group = report.mostTrainedMuscleGroup {
                    ReportLine(text: "Most trained: \(group.displayName)")
                }
                if let name = report.mostRepeatedWorkoutName, report.mostRepeatedWorkoutCount > 1 {
                    ReportLine(text: "Most repeated: \(name) — \(report.mostRepeatedWorkoutCount)×")
                }
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

private struct ReportStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.fzHeading(20, weight: .bold))
                .foregroundStyle(Color.fzText)
            Text(label)
                .font(.fzBody(11))
                .foregroundStyle(Color.fzTextSecondary)
        }
    }
}

private struct ReportLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.fzBody(13))
            .foregroundStyle(Color.fzText)
    }
}

// MARK: - WorkoutCalendarView

/// Always exactly one calendar grid — the month PeriodNavigator has
/// anchored to. Year mode never expands this into a month list; it only
/// changes what ReportCard aggregates above.
private struct WorkoutCalendarView: View {
    let sessions: [SessionHistoryEntry]
    let monthDate: Date

    private var calendar: Calendar { .current }

    /// The latest session on each calendar day — a day with more than one
    /// logged session (rare) shows whichever happened last, since a single
    /// day cell can only carry one icon.
    private var sessionsByDay: [Date: SessionHistoryEntry] {
        var map: [Date: SessionHistoryEntry] = [:]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            map[calendar.startOfDay(for: session.startedAt)] = session
        }
        return map
    }

    var body: some View {
        MonthCalendarCard(monthDate: monthDate, sessionsByDay: sessionsByDay)
    }
}

// MARK: - MonthCalendarCard

private struct MonthCalendarCard: View {
    let monthDate: Date
    let sessionsByDay: [Date: SessionHistoryEntry]

    private var calendar: Calendar { .current }

    private var monthInterval: DateInterval? { calendar.dateInterval(of: .month, for: monthDate) }

    private var days: [Date] {
        guard let interval = monthInterval else { return [] }
        var result: [Date] = []
        var current = interval.start
        while current < interval.end {
            result.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    /// Blank leading cells so day 1 lands under its real weekday column.
    /// `.weekday` is 1-indexed from Sunday, matching `veryShortWeekdaySymbols`.
    private var leadingBlanks: Int {
        guard let interval = monthInterval else { return 0 }
        return calendar.component(.weekday, from: interval.start) - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthDate.formatted(.dateTime.month(.wide).year()))
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.fzBody(10, weight: .semibold))
                        .foregroundStyle(Color.fzTextSecondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { blank in
                    Color.clear.frame(height: 40).id(blank)
                }
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, session: sessionsByDay[calendar.startOfDay(for: day)])
                }
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

// MARK: - DayCell

/// A day marked with a session is a NavigationLink straight to that day's
/// exact logged exercises (SessionDetailView) — an unmarked day is inert.
private struct DayCell: View {
    let day: Date
    let session: SessionHistoryEntry?

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var dayNumber: Int { calendar.component(.day, from: day) }

    var body: some View {
        Group {
            if let session {
                NavigationLink(destination: SessionDetailView(session: session)) {
                    cellContent
                }
                .buttonStyle(.plain)
            } else {
                cellContent
            }
        }
    }

    private var cellContent: some View {
        VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.fzMono(11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.fzPrimary : Color.fzText)

            if let session {
                Image(systemName: workoutIcon(session.workout?.workoutType))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: "0A0A0F"))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.fzPrimary))
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.fzPrimary.opacity(0.1) : Color.clear)
        )
    }

    /// workoutType is Kai's own strength|cardio|mobility|hiit|recovery tag
    /// (see WorkoutGenerationPrompt) — mapped to a representative SF Symbol
    /// rather than trying to depict a specific exercise, since a session
    /// usually spans several exercises with no single one that stands in
    /// for the whole day.
    private func workoutIcon(_ workoutType: String?) -> String {
        switch workoutType {
        case "strength": return "dumbbell.fill"
        case "cardio":   return "figure.run"
        case "mobility": return "figure.flexibility"
        case "hiit":     return "bolt.fill"
        case "recovery": return "leaf.fill"
        default:         return "checkmark"
        }
    }
}
