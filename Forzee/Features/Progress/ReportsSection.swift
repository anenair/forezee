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
// ============================================================

import SwiftUI

enum ReportPeriod: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }
    var label: String { self == .month ? "Month" : "Year" }
    var startDate: Date { self == .month ? InsightsEngine.startOfMonth() : InsightsEngine.startOfYear() }
}

struct ReportsSection: View {
    let sessions: [SessionHistoryEntry]
    @Binding var period: ReportPeriod

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

            ReportCard(report: InsightsEngine.periodReport(sessions: sessions, since: period.startDate), period: period)
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
