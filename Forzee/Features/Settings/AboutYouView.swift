// ============================================================
// AboutYouView.swift
// Forzee — Features/Settings
//
// A personal profile screen, separate from both onboarding and
// "My Plan" (which is about training preferences, not who the
// user is). Nothing here is asked at signup — it exists purely
// because this screen does, and every field is optional: Kai
// treats a blank field as "not provided," never guesses one.
//
// Feeds two places: the compact fields (age, sex, height, weight,
// years training) reach Kai's per-call context snapshot (see
// ContextBuilder) for coaching personalization; the two free-text
// fields deliberately don't, to keep that snapshot small — they're
// read only where a call site explicitly pulls them in.
//
// Height/weight/waist/hip are entered in whichever unit system
// "My Plan" already has the user set (lbs/kg) — this screen reads
// that preference but doesn't duplicate a way to change it.
// ============================================================

import SwiftUI

struct AboutYouView: View {

    @EnvironmentObject private var appState: AppState

    // Biometrics
    @State private var shareBirthDate = false
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var biologicalSex: BiologicalSex = .unspecified
    @State private var heightFeetText = ""
    @State private var heightInchesText = ""
    @State private var heightCmText = ""
    @State private var currentWeightText = ""

    // Target weight — set by dialing in a target BMI rather than typing a
    // weight directly, since height is already on this screen and BMI is
    // the more meaningful dial for "what am I aiming for." The weight
    // shown/stored is always derived: targetBMI × height², never typed.
    @State private var hasTargetWeight = false
    @State private var targetBMI: Double = 22.0

    // Body composition
    @State private var bodyFatText = ""
    @State private var waistText = ""
    @State private var hipText = ""

    // Training background
    @State private var yearsTraining: YearsTrainingBucket?
    @State private var trainingBackgroundNotes = ""
    @State private var motivationNotes = ""

    @State private var isSaving = false
    @State private var didSave = false

    private var isImperial: Bool { (appState.userProfile?.weightUnit ?? "lbs") == "lbs" }
    private var weightUnitLabel: String { isImperial ? "lb" : "kg" }
    private var lengthUnitLabel: String { isImperial ? "in" : "cm" }

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: ForzeeSpacing.sectionGap) {
                    calculatedCard
                    biometricsCard
                    bodyCompositionCard
                    trainingBackgroundCard
                }
                .padding(ForzeeSpacing.screenPadding)
                .padding(.bottom, 72)
            }
        }
        .navigationTitle("About You")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if didSave {
                    Text("Saved")
                        .font(.fzBody(12, weight: .semibold))
                        .foregroundStyle(Color.fzGreen)
                }
                ForzeeButton(title: "Save Changes", action: { Task { await save() } }, isLoading: isSaving)
            }
            .padding(ForzeeSpacing.screenPadding)
            .background(Color.fzBg)
        }
        .onAppear(perform: loadFromProfile)
    }

    // MARK: - Calculated (read-only)

    private var calculatedCard: some View {
        let preview = previewProfile()
        let hasAnything = preview.age != nil || preview.bmi != nil || preview.estimatedBMR != nil

        return Group {
            if hasAnything {
                InfoCard(title: "Calculated") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let age = preview.age {
                            CalculatedRow(label: "Age", value: "\(age)")
                        }
                        if let bmi = preview.bmi, let category = preview.bmiCategory {
                            CalculatedRow(label: "BMI", value: "\(String(format: "%.1f", bmi)) · \(category)")
                        }
                        if let bmr = preview.estimatedBMR {
                            CalculatedRow(label: "Estimated BMR", value: "\(Int(bmr)) cal/day")
                        }
                        Text("Estimates from what you've entered below — not measurements.")
                            .font(.fzBody(11))
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }
            }
        }
    }

    /// Builds a throwaway UserProfile from the current on-screen (unsaved)
    /// values so Calculated can preview live — reuses
    /// PersonalProfileCalculations instead of re-deriving age/BMI/BMR here.
    private func previewProfile() -> UserProfile {
        var profile = appState.userProfile ?? .new(userId: appState.userId ?? "")
        profile.dateOfBirth = shareBirthDate ? dateOfBirth : nil
        profile.biologicalSex = biologicalSex.rawValue
        profile.heightCm = resolvedHeightCm()
        profile.currentWeightKg = resolvedWeightKg(currentWeightText)
        return profile
    }

    // MARK: - Biometrics

    private var biometricsCard: some View {
        InfoCard(title: "Biometrics") {
            VStack(spacing: 12) {
                Toggle(isOn: $shareBirthDate) {
                    Text("Share your birth date")
                        .font(.fzBody(14))
                        .foregroundStyle(Color.fzText)
                }
                .tint(Color.fzPrimary)

                if shareBirthDate {
                    DatePicker(
                        "",
                        selection: $dateOfBirth,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color.fzPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().background(Color.fzBorder)

                Text("Biological sex")
                    .font(.fzBody(12, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                VStack(spacing: 8) {
                    ForEach(BiologicalSex.allCases) { option in
                        SelectableRow(title: option.title, subtitle: option.subtitle, isSelected: biologicalSex == option) {
                            biologicalSex = option
                        }
                    }
                }

                Divider().background(Color.fzBorder)

                if isImperial {
                    HStack(spacing: 8) {
                        numberField(label: "Height (ft)", text: $heightFeetText)
                        numberField(label: "Height (in)", text: $heightInchesText)
                    }
                } else {
                    numberField(label: "Height (cm)", text: $heightCmText)
                }

                numberField(label: "Current weight (\(weightUnitLabel))", text: $currentWeightText)
                targetWeightSlider
            }
        }
    }

    private var targetWeightSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $hasTargetWeight) {
                Text("Set a target weight")
                    .font(.fzBody(14))
                    .foregroundStyle(Color.fzText)
            }
            .tint(Color.fzPrimary)

            if hasTargetWeight {
                if let heightCm = resolvedHeightCm(), heightCm > 0 {
                    let heightM = heightCm / 100
                    let weightKg = targetBMI * heightM * heightM

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Target weight — optional")
                                .font(.fzBody(12))
                                .foregroundStyle(Color.fzTextSecondary)
                            Spacer()
                            Text("\(formattedWeight(fromKg: weightKg)) \(weightUnitLabel)")
                                .font(.fzMono(14, weight: .semibold))
                                .foregroundStyle(Color.fzText)
                        }
                        Slider(value: $targetBMI, in: 15...40, step: 0.1)
                            .tint(Color.fzPrimary)
                        HStack {
                            Text("BMI \(String(format: "%.1f", targetBMI))")
                                .font(.fzMono(12, weight: .medium))
                                .foregroundStyle(Color.fzPrimary)
                            Spacer()
                            Text(UserProfile.bmiCategory(for: targetBMI))
                                .font(.fzBody(12))
                                .foregroundStyle(Color.fzTextSecondary)
                        }
                    }
                } else {
                    Text("Enter your height above to set a target weight by BMI.")
                        .font(.fzBody(12))
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionCard: some View {
        InfoCard(title: "Body Composition") {
            VStack(spacing: 12) {
                numberField(label: "Body fat % — optional", text: $bodyFatText)
                numberField(label: "Waist (\(lengthUnitLabel)) — optional", text: $waistText)
                numberField(label: "Hip (\(lengthUnitLabel)) — optional", text: $hipText)
            }
        }
    }

    // MARK: - Training Background

    private var trainingBackgroundCard: some View {
        InfoCard(title: "Training Background") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Years training")
                    .font(.fzBody(12, weight: .semibold))
                    .foregroundStyle(Color.fzTextSecondary)
                    .textCase(.uppercase)
                VStack(spacing: 8) {
                    ForEach(YearsTrainingBucket.allCases) { bucket in
                        SelectableRow(title: bucket.title, subtitle: nil, isSelected: yearsTraining == bucket) {
                            yearsTraining = bucket
                        }
                    }
                }

                Divider().background(Color.fzBorder)

                textArea(label: "Your training background — optional", text: $trainingBackgroundNotes,
                         placeholder: "Programs you've done, what's worked or hasn't...")
                textArea(label: "What's driving you right now — optional", text: $motivationNotes,
                         placeholder: "Why this, why now...")
            }
        }
    }

    // MARK: - Shared field builders

    private func numberField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fzBody(12))
                .foregroundStyle(Color.fzTextSecondary)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .font(.fzMono(14))
                .foregroundStyle(Color.fzText)
                .padding(10)
                .background(Color.fzSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
    }

    private func textArea(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fzBody(12))
                .foregroundStyle(Color.fzTextSecondary)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzText)
                .padding(10)
                .background(Color.fzSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                .lineLimit(2...5)
        }
    }

    // MARK: - Unit conversion

    private func resolvedHeightCm() -> Double? {
        if isImperial {
            guard let feet = Double(heightFeetText) else { return nil }
            let inches = Double(heightInchesText) ?? 0
            return (feet * 12 + inches) * 2.54
        }
        return Double(heightCmText)
    }

    private func resolvedWeightKg(_ text: String) -> Double? {
        guard let value = Double(text) else { return nil }
        return isImperial ? value * 0.453592 : value
    }

    private func resolvedLengthCm(_ text: String) -> Double? {
        guard let value = Double(text) else { return nil }
        return isImperial ? value * 2.54 : value
    }

    /// The actual target-weight value to store — derived from the BMI
    /// slider and height, never typed directly. nil whenever the toggle is
    /// off or height isn't known yet, which on save clears any
    /// previously-stored target rather than leaving a stale one behind.
    private func resolvedTargetWeightKg() -> Double? {
        guard hasTargetWeight, let heightCm = resolvedHeightCm(), heightCm > 0 else { return nil }
        let heightM = heightCm / 100
        return targetBMI * heightM * heightM
    }

    /// Boxes a value for the `[String: Any]` updates dict, using NSNull
    /// (not Swift's nil) to explicitly clear a field — JSONSerialization
    /// serializes NSNull as JSON `null`, which Postgres reads as "set this
    /// column to NULL." A bare Swift `nil` inside an `Any` dictionary can't
    /// express that at all.
    private func anyOrNull<T>(_ value: T?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private func formattedHeight(fromCm cm: Double) {
        if isImperial {
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
            heightFeetText = String(feet)
            heightInchesText = String(inches)
        } else {
            heightCmText = formattedNumber(cm)
        }
    }

    private func formattedWeight(fromKg kg: Double) -> String {
        formattedNumber(isImperial ? kg / 0.453592 : kg)
    }

    private func formattedLength(fromCm cm: Double) -> String {
        formattedNumber(isImperial ? cm / 2.54 : cm)
    }

    private func formattedNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Load / Save

    private func loadFromProfile() {
        guard let profile = appState.userProfile else { return }

        if let dob = profile.dateOfBirth {
            shareBirthDate = true
            dateOfBirth = dob
        }
        biologicalSex = BiologicalSex(rawValue: profile.biologicalSex ?? "") ?? .unspecified

        if let heightCm = profile.heightCm {
            formattedHeight(fromCm: heightCm)
        }
        if let weight = profile.currentWeightKg {
            currentWeightText = formattedWeight(fromKg: weight)
        }
        if let target = profile.targetWeightKg, let heightCm = profile.heightCm, heightCm > 0 {
            hasTargetWeight = true
            let heightM = heightCm / 100
            targetBMI = target / (heightM * heightM)
        }
        if let bodyFat = profile.bodyFatPercent {
            bodyFatText = formattedNumber(bodyFat)
        }
        if let waist = profile.waistCm {
            waistText = formattedLength(fromCm: waist)
        }
        if let hip = profile.hipCm {
            hipText = formattedLength(fromCm: hip)
        }
        yearsTraining = YearsTrainingBucket(rawValue: profile.yearsTrainingBucket ?? "")
        trainingBackgroundNotes = profile.trainingBackgroundNotes ?? ""
        motivationNotes = profile.motivationNotes ?? ""
    }

    private func save() async {
        guard let userId = appState.userId else { return }
        isSaving = true
        didSave = false
        defer { isSaving = false }

        var updates: [String: Any] = [
            "biological_sex": biologicalSex.rawValue,
        ]
        updates["date_of_birth"] = anyOrNull(shareBirthDate ? ISO8601DateFormatter().string(from: dateOfBirth) : nil)
        updates["height_cm"] = anyOrNull(resolvedHeightCm())
        updates["current_weight_kg"] = anyOrNull(resolvedWeightKg(currentWeightText))
        updates["target_weight_kg"] = anyOrNull(resolvedTargetWeightKg())
        updates["body_fat_percent"] = anyOrNull(Double(bodyFatText))
        updates["waist_cm"] = anyOrNull(resolvedLengthCm(waistText))
        updates["hip_cm"] = anyOrNull(resolvedLengthCm(hipText))
        updates["years_training_bucket"] = anyOrNull(yearsTraining?.rawValue)
        updates["training_background_notes"] = anyOrNull(trainingBackgroundNotes.isEmpty ? nil : trainingBackgroundNotes)
        updates["motivation_notes"] = anyOrNull(motivationNotes.isEmpty ? nil : motivationNotes)

        guard (try? await ForzeeDataService.shared.updateProfile(updates, userId: userId)) != nil else { return }

        if var profile = appState.userProfile {
            profile.biologicalSex = biologicalSex.rawValue
            profile.dateOfBirth = shareBirthDate ? dateOfBirth : nil
            profile.heightCm = resolvedHeightCm()
            profile.currentWeightKg = resolvedWeightKg(currentWeightText)
            profile.targetWeightKg = resolvedTargetWeightKg()
            profile.bodyFatPercent = Double(bodyFatText)
            profile.waistCm = resolvedLengthCm(waistText)
            profile.hipCm = resolvedLengthCm(hipText)
            profile.yearsTrainingBucket = yearsTraining?.rawValue
            profile.trainingBackgroundNotes = trainingBackgroundNotes.isEmpty ? nil : trainingBackgroundNotes
            profile.motivationNotes = motivationNotes.isEmpty ? nil : motivationNotes
            appState.userProfile = profile
        }

        withAnimation { didSave = true }
    }
}

// MARK: - BiologicalSex

enum BiologicalSex: String, CaseIterable, Identifiable {
    case male
    case female
    case unspecified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:        return "Male"
        case .female:      return "Female"
        case .unspecified: return "Prefer not to say"
        }
    }

    var subtitle: String? {
        self == .unspecified ? "Skips sex-specific calorie estimates" : nil
    }
}

// MARK: - YearsTrainingBucket

enum YearsTrainingBucket: String, CaseIterable, Identifiable {
    case underOne     = "under_1"
    case oneToThree   = "one_to_three"
    case threeToFive  = "three_to_five"
    case fivePlus     = "five_plus"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .underOne:    return "Under 1 year"
        case .oneToThree:  return "1–3 years"
        case .threeToFive: return "3–5 years"
        case .fivePlus:    return "5+ years"
        }
    }
}

// MARK: - InfoCard

private struct InfoCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text(title)
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)
            content
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

// MARK: - CalculatedRow

private struct CalculatedRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)
            Spacer()
            Text(value)
                .font(.fzMono(14, weight: .semibold))
                .foregroundStyle(Color.fzText)
        }
    }
}

// MARK: - SelectableRow

private struct SelectableRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.fzBody(14, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.fzBody(12))
                            .foregroundStyle(Color.fzTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzBorder)
            }
            .padding(12)
            .background(Color.fzSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AboutYouView()
            .environmentObject(AppState())
    }
}
