// ============================================================
// ProgressTabView.swift
// Forzee — Features/Progress
//
// Phase 2: manual nutrition logging. Named ProgressTabView
// (not ProgressView) to avoid shadowing SwiftUI.ProgressView
// throughout the module.
//
// Full progress tracking (photos, PRs, charts) stays out of
// scope here — this ships the nutrition half of Phase 2's
// "Nutrition / meal tracking" checklist item.
// ============================================================

import SwiftUI

struct ProgressTabView: View {

    @EnvironmentObject private var appState: AppState

    @State private var summary: NutritionSummary = .empty
    @State private var isLoading = false
    @State private var showLogSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: ForzeeSpacing.sectionGap) {
                        nutritionCard
                        ForzeeButton(title: "Log a Meal") { showLogSheet = true }
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
            .navigationTitle("Progress")
            .task { await loadSummary() }
            .sheet(isPresented: $showLogSheet) {
                LogMealSheet(userId: appState.userId) {
                    Task { await loadSummary() }
                }
            }
        }
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("Today's Nutrition")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            if isLoading {
                ProgressView().tint(Color.fzPrimary)
            } else if summary.entryCount == 0 {
                Text("Nothing logged yet today.")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzTextSecondary)
            } else {
                HStack(spacing: ForzeeSpacing.sectionGap) {
                    StatColumn(value: "\(summary.totalCalories)", label: "calories")
                    StatColumn(value: "\(summary.totalProteinG)g", label: "protein")
                    StatColumn(value: "\(summary.entryCount)", label: "meals logged")
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

    private func loadSummary() async {
        guard let userId = appState.userId else { return }
        isLoading = true
        defer { isLoading = false }
        summary = (try? await ForzeeDataService.shared.fetchNutritionToday(userId: userId)) ?? .empty
    }
}

// MARK: - StatColumn

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.fzHeading(20, weight: .bold))
                .foregroundStyle(Color.fzText)
            Text(label)
                .font(.fzBody(12))
                .foregroundStyle(Color.fzTextSecondary)
        }
    }
}

// MARK: - LogMealSheet

private struct LogMealSheet: View {
    let userId: String?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mealType: NutritionEntry.MealType = .breakfast
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                VStack(spacing: ForzeeSpacing.sectionGap) {
                    Picker("Meal", selection: $mealType) {
                        ForEach(NutritionEntry.MealType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: ForzeeSpacing.itemGap) {
                        MacroField(label: "Calories", text: $calories)
                        MacroField(label: "Protein (g)", text: $protein)
                        MacroField(label: "Carbs (g)", text: $carbs)
                        MacroField(label: "Fat (g)", text: $fat)
                    }

                    Spacer()

                    ForzeeButton(title: "Save", action: save, isDisabled: calories.isEmpty, isLoading: isSaving)
                }
                .padding(ForzeeSpacing.screenPadding)
            }
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let userId else { return }
        let entry = NutritionEntry.new(
            userId: userId,
            mealType: mealType,
            calories: Int(calories) ?? 0,
            proteinG: Int(protein) ?? 0,
            carbsG: Int(carbs) ?? 0,
            fatG: Int(fat) ?? 0
        )
        isSaving = true
        Task {
            try? await ForzeeDataService.shared.saveNutritionEntry(entry)
            isSaving = false
            onSaved()
            dismiss()
        }
    }
}

// MARK: - MacroField

private struct MacroField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzTextSecondary)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.fzMono(15))
                .foregroundStyle(Color.fzText)
                .frame(width: 80)
        }
        .padding(12)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
    }
}

#Preview {
    ProgressTabView()
        .environmentObject(AppState())
}
