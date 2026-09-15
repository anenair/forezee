// ============================================================
// PersonalProfileCalculations.swift
// Forzee — Core/Models
//
// Derived values from the "About You" profile — age, BMI, BMR.
// None of these are stored; they're computed fresh from the raw
// fields on UserProfile wherever they're needed, so there's never
// a stale calculated value sitting in the database disagreeing
// with its own inputs.
// ============================================================

import Foundation

extension UserProfile {

    /// Whole years, computed from dateOfBirth as of now. nil if no
    /// birth date has been set.
    var age: Int? {
        guard let dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year
    }

    /// Standard weight(kg) / height(m)² — needs both height and current
    /// weight; nil if either is missing.
    var bmi: Double? {
        guard let heightCm, heightCm > 0, let currentWeightKg else { return nil }
        let heightM = heightCm / 100
        return currentWeightKg / (heightM * heightM)
    }

    /// WHO's standard BMI bands — descriptive, not a health judgment Kai
    /// should moralize about.
    var bmiCategory: String? {
        guard let bmi else { return nil }
        return Self.bmiCategory(for: bmi)
    }

    /// Same bands as `bmiCategory`, but for a BMI value that isn't
    /// necessarily this profile's *current* one — e.g. AboutYouView's
    /// target-weight-by-BMI slider, which previews a category for a BMI
    /// the user hasn't actually reached yet.
    static func bmiCategory(for bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Healthy range"
        case 25..<30: return "Overweight"
        default: return "Obesity range"
        }
    }

    /// Mifflin-St Jeor equation — the most widely used BMR estimate,
    /// accurate to within roughly 10% for most people. An estimate, not a
    /// measurement: needs height, weight, age, and a stated biological
    /// sex (nil if sex is "unspecified" or missing — no formula to fall
    /// back on that wouldn't just be a guess).
    var estimatedBMR: Double? {
        guard let heightCm, let currentWeightKg, let age, let biologicalSex,
              biologicalSex == "male" || biologicalSex == "female" else { return nil }
        let base = 10 * currentWeightKg + 6.25 * heightCm - 5 * Double(age)
        return biologicalSex == "male" ? base + 5 : base - 161
    }
}
