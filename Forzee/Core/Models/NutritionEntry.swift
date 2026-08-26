// ============================================================
// NutritionEntry.swift
// Forzee — Core/Models
//
// Maps to the `nutrition_logs` table in Supabase.
// Phase 2: manual macro logging. Kai reads today's totals as
// part of the context snapshot — no photo/barcode scanning yet.
// ============================================================

import Foundation

struct NutritionEntry: Identifiable, Codable, Equatable {

    let id: String
    let userId: String
    var mealType: MealType
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var notes: String?
    let loggedAt: Date

    enum MealType: String, Codable, CaseIterable, Identifiable {
        case breakfast
        case lunch
        case dinner
        case snack

        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case mealType  = "meal_type"
        case calories
        case proteinG  = "protein_g"
        case carbsG    = "carbs_g"
        case fatG      = "fat_g"
        case notes
        case loggedAt  = "logged_at"
    }
}

extension NutritionEntry {
    static func new(
        userId: String,
        mealType: MealType,
        calories: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        notes: String? = nil
    ) -> NutritionEntry {
        NutritionEntry(
            id: UUID().uuidString,
            userId: userId,
            mealType: mealType,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            notes: notes,
            loggedAt: .now
        )
    }
}

// MARK: - NutritionSummary

/// A day's aggregated macros — used by ContextBuilder and the Progress tab.
struct NutritionSummary {
    let totalCalories: Int
    let totalProteinG: Int
    let entryCount: Int

    static let empty = NutritionSummary(totalCalories: 0, totalProteinG: 0, entryCount: 0)
}
