// ============================================================
// InsightsSection.swift
// Forzee — Features/Progress
//
// Roadmap Phase 3 "Insights" — the actual paid-tier pitch, not a
// nice-to-have. Free users see a locked teaser; Premium users get
// Weekly Set Targets, Recovery, and Kai's weekly read — all built
// on InsightsEngine's pure aggregation over the same session
// history the Log feed already fetches, so nothing here is a
// separate source of truth.
// ============================================================

import SwiftUI

struct InsightsSection: View {
    let sessions: [SessionHistoryEntry]
    let isPremium: Bool
    let weeklyInsight: String?
    let isLoadingInsight: Bool
    let onRefreshInsight: () -> Void
    let onUpgrade: () -> Void

    @Binding var askQuestion: String
    let askAnswer: String?
    let isAsking: Bool
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            HStack {
                Text("Insights")
                    .font(.fzBody(13, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("PREMIUM")
                    .font(.fzMono(10, weight: .semibold))
                    .foregroundStyle(Color.fzPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.fzPrimaryDim)
                    .clipShape(Capsule())
            }

            if isPremium {
                VStack(spacing: ForzeeSpacing.itemGap) {
                    KaiWeeklyReadCard(insight: weeklyInsight, isLoading: isLoadingInsight, onRefresh: onRefreshInsight)
                    AskKaiCard(question: $askQuestion, answer: askAnswer, isAsking: isAsking, onAsk: onAsk)
                    WeeklySetTargetsCard(sessions: sessions)
                    RecoveryCard(sessions: sessions)
                }
            } else {
                InsightsLockedCard(onUpgrade: onUpgrade)
            }
        }
    }
}

// MARK: - KaiWeeklyReadCard

/// The named premium differentiator — see roadmap Phase 3. Loads lazily
/// (never on every tab visit) since it's a real Sonnet call, not a free
/// local computation like the two cards below it.
private struct KaiWeeklyReadCard: View {
    let insight: String?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            HStack {
                Text("Kai's Weekly Read")
                    .font(.fzBody(14, weight: .semibold))
                    .foregroundStyle(Color.fzText)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView().tint(Color.fzPrimary)
            } else if let insight {
                Text(insight)
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
            } else {
                Text("Tap refresh for Kai's read on your week.")
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzPrimaryDim)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
    }
}

// MARK: - AskKaiCard

/// On-demand version of Kai's weekly read (explain_insight skill) — "why
/// did my momentum drop?" answered against the same InsightsEngine numbers,
/// instead of only ever getting a scheduled summary.
private struct AskKaiCard: View {
    @Binding var question: String
    let answer: String?
    let isAsking: Bool
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Ask Kai About This")
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)

            HStack(spacing: 8) {
                TextField("e.g. \"why is my momentum down?\"", text: $question)
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzText)
                    .padding(10)
                    .background(Color.fzSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))

                Button(action: onAsk) {
                    if isAsking {
                        ProgressView().tint(Color.fzPrimary)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(question.trimmingCharacters(in: .whitespaces).isEmpty ? Color.fzBorder : Color.fzPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAsking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let answer {
                Text(answer)
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
                    .padding(.top, 4)
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

// MARK: - WeeklySetTargetsCard

private struct TargetRow: Identifiable {
    let group: MuscleGroup
    let done: Int
    let target: Int
    var id: MuscleGroup { group }
}

private struct WeeklySetTargetsCard: View {
    let sessions: [SessionHistoryEntry]

    /// Most-neglected first, capped to 6 rows — the point is "what needs
    /// attention," not a full 10-row dump of every group every time.
    /// Broken into explicit statements (rather than one chained
    /// filter/map/sorted expression) — the compiler timed out type-checking
    /// the all-in-one version.
    private var rows: [TargetRow] {
        let volume = InsightsEngine.weeklySetVolume(sessions: sessions)

        var allRows: [TargetRow] = []
        for group in MuscleGroup.allCases where group != .fullBody {
            let done = volume[group] ?? 0
            let target = group.weeklySetTarget
            allRows.append(TargetRow(group: group, done: done, target: target))
        }

        allRows.sort { Self.fraction(of: $0) < Self.fraction(of: $1) }
        return Array(allRows.prefix(6))
    }

    private static func fraction(of row: TargetRow) -> Double {
        guard row.target > 0 else { return 0 }
        return Double(row.done) / Double(row.target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Weekly Set Targets")
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)
            Text("Last 7 days, most-neglected first")
                .font(.fzBody(11))
                .foregroundStyle(Color.fzTextSecondary)

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    TargetBarRow(row: row)
                }
            }
            .padding(.top, 4)
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

private struct TargetBarRow: View {
    let row: TargetRow

    private var fraction: Double {
        row.target > 0 ? min(1, Double(row.done) / Double(row.target)) : 0
    }

    private var barColor: Color {
        fraction >= 1 ? Color.fzGreen : (fraction >= 0.5 ? Color.fzPrimary : Color.fzCoral)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.group.displayName)
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzText)
                Spacer()
                Text("\(row.done)/\(row.target)")
                    .font(.fzMono(12))
                    .foregroundStyle(Color.fzTextSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.fzSurfaceElevated)
                    Capsule().fill(barColor).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - RecoveryCard

private struct RecoveryRow: Identifiable {
    let group: MuscleGroup
    let daysAgo: Int?
    var id: MuscleGroup { group }
}

private struct RecoveryCard: View {
    let sessions: [SessionHistoryEntry]

    /// Stalest first — "no recent session data" sorts as stalest of all,
    /// not most-fresh, since an absent key means no data in the lookback
    /// window, not "just trained." Broken into explicit statements, same
    /// reasoning as WeeklySetTargetsCard.rows above.
    private var rows: [RecoveryRow] {
        let recovery = InsightsEngine.daysSinceLastTrained(sessions: sessions)

        var allRows: [RecoveryRow] = []
        for group in MuscleGroup.allCases where group != .fullBody {
            allRows.append(RecoveryRow(group: group, daysAgo: recovery[group]))
        }

        allRows.sort { ($0.daysAgo ?? Int.max) > ($1.daysAgo ?? Int.max) }
        return Array(allRows.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("Recovery")
                .font(.fzBody(14, weight: .semibold))
                .foregroundStyle(Color.fzText)
            Text("Days since last trained — stalest first")
                .font(.fzBody(11))
                .foregroundStyle(Color.fzTextSecondary)

            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.group.displayName)
                            .font(.fzBody(13))
                            .foregroundStyle(Color.fzText)
                        Spacer()
                        Text(row.daysAgo.map { "\($0)d ago" } ?? "no data")
                            .font(.fzMono(12))
                            .foregroundStyle(freshnessColor(row.daysAgo))
                    }
                }
            }
            .padding(.top, 4)
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

    private func freshnessColor(_ daysAgo: Int?) -> Color {
        guard let daysAgo else { return Color.fzTextSecondary }
        return daysAgo >= 5 ? Color.fzGreen : Color.fzTextSecondary
    }
}

// MARK: - InsightsLockedCard

private struct InsightsLockedCard: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fzPrimary)
                    .padding(.top, 2)
                Text("See your weekly volume, recovery, and Kai's own read on your training.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
            }
            ForzeeTextButton(title: "Try Forzee Premium", action: onUpgrade)
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
