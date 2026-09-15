// ============================================================
// CoachBlockRenderer.swift
// Forzee — Features/Coach
//
// Renders a CoachResponse's blocks — the "chat renderer becomes a
// block renderer" half of the protocol (see Core/AI/CoachProtocol/
// CoachResponse.swift for the data side). Each block type gets its
// own small, native SwiftUI renderer; an unknown block type (any
// future kind this build doesn't know about yet) renders nothing
// rather than crashing — see CoachBlock.unknown.
// ============================================================

import SwiftUI

// MARK: - CoachBlockRenderer

struct CoachBlockRenderer: View {
    let blocks: [CoachBlock]
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let b):
                    TextBlockView(content: b.content, textColor: textColor)
                case .workout(let b):
                    WorkoutBlockView(workout: b.workout)
                case .coachingNote(let b):
                    CoachingNoteBlockView(block: b)
                case .progress(let b):
                    ProgressBlockView(block: b)
                case .confirmation(let b):
                    ConfirmationBlockView(block: b)
                case .unknown:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - TextBlockView

/// Plain conversational text — the one block type that still parses a
/// lightweight "- " list convention out of its own content, for a rare
/// non-workout list Kai wants to set apart (a workout's own exercises
/// belong in a `workout` block instead — see KaiSystemPrompt's Rules).
/// Structured fitness data never lives here.
private struct TextBlockView: View {
    let content: String
    let textColor: Color

    private enum Line {
        case prose(String)
        case listItem(String)
    }

    private var lines: [Line] {
        var result: [Line] = []
        var proseLines: [String] = []
        func flush() {
            guard !proseLines.isEmpty else { return }
            result.append(.prose(proseLines.joined(separator: "\n")))
            proseLines = []
        }
        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") {
                flush()
                result.append(.listItem(String(line.dropFirst(2))))
            } else if line.isEmpty {
                flush()
            } else {
                proseLines.append(line)
            }
        }
        flush()
        return result.isEmpty ? [.prose(content)] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .prose(let text):
                    Text(text)
                        .font(.fzBody(15))
                        .foregroundStyle(textColor)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                case .listItem(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(textColor.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 7)
                        Text(text)
                            .font(.fzBody(14))
                            .foregroundStyle(textColor)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }
}

// MARK: - WorkoutBlockView

/// A structured workout, rendered by native components — never text
/// formatted to look like one. Read-only here: no per-set logging, that's
/// WorkoutTabView's job once the user taps Build Workout (see
/// CoachActionRow / CoachActionExecutor).
private struct WorkoutBlockView: View {
    let workout: CoachWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.title.isEmpty ? "Workout" : workout.title)
                    .font(.fzBody(15, weight: .semibold))
                    .foregroundStyle(Color.fzText)
                if let mins = workout.estimatedDurationMinutes {
                    Spacer()
                    Text("~\(mins) min")
                        .font(.fzMono(12))
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                    CoachExerciseRow(exercise: exercise)
                }
            }
        }
        .padding(12)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }
}

private struct CoachExerciseRow: View {
    let exercise: CoachExercise

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color.fzPrimary).frame(width: 5, height: 5).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // fixedSize forces each Text to claim the vertical (and,
                    // for the prescription, horizontal) space its own
                    // content actually needs — without it, this HStack's
                    // Spacer can propose an ambiguous width that silently
                    // truncates text to one line instead of wrapping.
                    Text(exercise.name)
                        .font(.fzBody(14, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(prescriptionText)
                        .font(.fzMono(12, weight: .medium))
                        .foregroundStyle(Color.fzPrimary)
                        .fixedSize()
                }
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.fzBody(12))
                        .italic()
                        .foregroundStyle(Color.fzTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var prescriptionText: String {
        "\(exercise.prescription.legacySets) × \(exercise.prescription.legacyRepsText)"
    }
}

// MARK: - CoachingNoteBlockView

private struct CoachingNoteBlockView: View {
    let block: CoachingNoteBlock

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tintColor)
            Text(block.content)
                .font(.fzBody(13, weight: .medium))
                .foregroundStyle(Color.fzText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tintColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    /// Severity → styling is decided entirely here — the LLM picks one of
    /// three fixed severities (see CoachingNoteSeverity), never the icon
    /// or color itself.
    private var iconName: String {
        switch block.severity {
        case .info:    return "info.circle.fill"
        case .tip:     return "lightbulb.fill"
        case .caution: return "exclamationmark.triangle.fill"
        }
    }

    private var tintColor: Color {
        switch block.severity {
        case .info:    return Color.fzPrimary
        case .tip:     return Color.fzGreen
        case .caution: return Color.fzCoral
        }
    }
}

// MARK: - ProgressBlockView

/// Architecture-ready, not yet produced by Kai — no call site emits a
/// progress block in v1. The UI owns this visualization entirely; the
/// LLM would only ever supply the plain numbers/strings below.
private struct ProgressBlockView: View {
    let block: ProgressBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.fzBody(12, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(formatted(block.current))\(block.unit)")
                    .font(.fzHeading(18, weight: .bold))
                    .foregroundStyle(Color.fzText)
                if let previous = block.previous {
                    Text("from \(formatted(previous))\(block.unit)")
                        .font(.fzBody(12))
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - ConfirmationBlockView

/// Architecture-ready, not yet interactive — no call site emits a
/// confirmation block or wires up Yes/No handling in v1. Renders as a
/// read-only card so a future confirmation block never crashes the chat
/// even before its action-handling exists.
private struct ConfirmationBlockView: View {
    let block: ConfirmationBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzText)
            Text(block.message)
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzPrimaryDim)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }
}

// MARK: - CoachActionRow

/// One structured action, rendered under the message that proposed it —
/// e.g. "Build Workout". CoachResponseValidator.isPermitted already
/// decided this action is real and executable before it was ever handed
/// here; tapping it runs CoachActionExecutor, never anything the LLM
/// claims on its own say-so.
struct CoachActionRow: View {
    let action: CoachAction
    let isExecuting: Bool
    let confirmation: String?
    let onTap: () -> Void
    let onOpenWorkoutTab: () -> Void

    var body: some View {
        if let confirmation {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fzGreen)
                    Text(confirmation)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                ForzeeTextButton(title: "Open Workout Tab", action: onOpenWorkoutTab)
            }
        } else {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    if isExecuting {
                        ProgressView().tint(Color.fzPrimary).scaleEffect(0.8)
                    } else {
                        Image(systemName: actionIcon)
                    }
                    Text(action.label)
                        .font(.fzBody(14, weight: .medium))
                }
                .foregroundStyle(Color.fzPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.fzPrimaryDim)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.pill))
            }
            .disabled(isExecuting)
        }
    }

    private var actionIcon: String {
        switch action.type {
        case .buildWorkout:    return "dumbbell.fill"
        case .replaceExercise: return "arrow.triangle.2.circlepath"
        case .logSet:          return "checkmark.circle.fill"
        case .startWorkout:    return "play.fill"
        case .modifyWorkout:   return "minus.circle"
        case .skipExercise:    return "arrow.uturn.forward"
        case .startTimer:      return "timer"
        case .finishWorkout:   return "flag.checkered"
        case .showExercise:    return "clock.arrow.circlepath"
        case .viewProgress:    return "chart.bar.fill"
        default:                return "bolt.fill"
        }
    }
}
