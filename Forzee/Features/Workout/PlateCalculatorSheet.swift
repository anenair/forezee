// ============================================================
// PlateCalculatorSheet.swift
// Forzee — Features/Workout
//
// Roadmap Phase 1 "Plate calculator" — given a target weight and
// a bar weight, work out which plates go on each side. Pure math,
// no AI call and no network round trip, so it opens instantly from
// the Workout tab toolbar regardless of connectivity.
// ============================================================

import SwiftUI

// MARK: - PlateMath

enum PlateMath {
    static let availablePlatesLbs: [Double] = [45, 35, 25, 10, 5, 2.5]
    static let availablePlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Greedily picks plates for one side of the bar to reach `targetWeight`
    /// as closely as possible without going over — the largest plate that
    /// still fits, repeated, then the next size down. Returns them largest
    /// first (the order they'd actually get loaded onto the bar); empty if
    /// the target is at or below the bar's own weight.
    static func platesPerSide(targetWeight: Double, barWeight: Double, unit: WeightUnit) -> [Double] {
        var remaining = (targetWeight - barWeight) / 2
        guard remaining > 0.001 else { return [] }

        let available = unit == .kg ? availablePlatesKg : availablePlatesLbs
        var result: [Double] = []

        for plate in available {
            while remaining + 0.001 >= plate {
                result.append(plate)
                remaining -= plate
            }
        }
        return result
    }
}

// MARK: - PlateCalculatorSheet

struct PlateCalculatorSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var targetText = ""
    @State private var barText = "45"
    @State private var unit: WeightUnit = .lbs

    private var targetWeight: Double? { Double(targetText) }
    private var barWeight: Double { Double(barText) ?? (unit == .kg ? 20 : 45) }

    private var plates: [Double] {
        guard let targetWeight else { return [] }
        return PlateMath.platesPerSide(targetWeight: targetWeight, barWeight: barWeight, unit: unit)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                VStack(spacing: ForzeeSpacing.sectionGap) {
                    unitPicker
                    inputs
                    resultCard
                    Spacer()
                }
                .padding(ForzeeSpacing.screenPadding)
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: unit) { oldUnit, newUnit in
            // Target weight is a real value the user typed — it has to
            // convert, not just get relabeled (225 staying "225" after
            // toggling lb -> kg would silently become a different weight).
            if let target = Double(targetText) {
                let kg = oldUnit == .kg ? target : target * 0.45359237
                targetText = formattedPlate(newUnit == .kg ? kg : kg / 0.45359237)
            }
            // The bar, by contrast, resets to the new unit's own standard
            // barbell rather than converting — there's no "standard target
            // weight" to fall back on the way there's a standard bar.
            barText = newUnit == .kg ? "20" : "45"
        }
    }

    private var unitPicker: some View {
        Picker("Unit", selection: $unit) {
            Text("lb").tag(WeightUnit.lbs)
            Text("kg").tag(WeightUnit.kg)
        }
        .pickerStyle(.segmented)
    }

    private var inputs: some View {
        VStack(spacing: ForzeeSpacing.itemGap) {
            calcField(label: "Target weight", text: $targetText, placeholder: "225")
            calcField(label: "Bar weight", text: $barText, placeholder: unit == .kg ? "20" : "45")
        }
    }

    private func calcField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzTextSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.fzMono(15))
                .foregroundStyle(Color.fzText)
                .frame(width: 90)
        }
        .padding(12)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("Per Side")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            if targetWeight == nil {
                Text("Enter a target weight.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else if plates.isEmpty {
                Text("Bar only — target is at or below the bar's own weight.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        PlateChip(value: plate, unit: unit)
                    }
                }
                Text(plates.map(formattedPlate).joined(separator: " + "))
                    .font(.fzMono(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
    }

    private func formattedPlate(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }
}

// MARK: - PlateChip

private struct PlateChip: View {
    let value: Double
    let unit: WeightUnit

    var body: some View {
        Text(formatted)
            .font(.fzMono(12, weight: .semibold))
            .foregroundStyle(Color(hex: "0A0A0F"))
            .frame(width: plateSize, height: plateSize)
            .background(Circle().fill(Color.fzPrimary.opacity(opacity)))
    }

    private var formatted: String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// Bigger plates read as visually bigger chips, capped so a 45 doesn't
    /// blow past the row.
    private var plateSize: CGFloat {
        let maxPlate: Double = unit == .kg ? 25 : 45
        let minSize: CGFloat = 28
        let maxSize: CGFloat = 52
        return minSize + (maxSize - minSize) * CGFloat(min(value / maxPlate, 1))
    }

    private var opacity: Double {
        0.55 + 0.45 * min(value / (unit == .kg ? 25 : 45), 1)
    }
}

#Preview {
    PlateCalculatorSheet()
}
