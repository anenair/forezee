// ============================================================
// PaywallView.swift
// Forzee — Features/Settings
//
// Phase 2: the premium paywall. Presented as a sheet from
// Settings (or from a usage-limit prompt in Coach/Workout).
// Lists RevenueCat offerings and drives PurchaseManager.
// ============================================================

import SwiftUI
import RevenueCat

struct PaywallView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackage: Package?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                if purchaseManager.isLoadingOfferings {
                    ProgressView().tint(Color.fzPrimary)
                } else {
                    content
                }
            }
            .navigationTitle("Forzee Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.fzTextSecondary)
                }
            }
        }
        .task {
            await purchaseManager.loadOfferings()
            selectedPackage = purchaseManager.offerings?.current?.availablePackages.first
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForzeeSpacing.sectionGap) {
                header

                if let packages = purchaseManager.offerings?.current?.availablePackages, !packages.isEmpty {
                    VStack(spacing: ForzeeSpacing.itemGap) {
                        ForEach(packages, id: \.identifier) { package in
                            PackageRow(
                                package: package,
                                isSelected: selectedPackage?.identifier == package.identifier
                            ) {
                                selectedPackage = package
                            }
                        }
                    }
                } else {
                    Text("No offerings configured yet. Add packages in the RevenueCat dashboard.")
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }

                if let error = purchaseManager.purchaseError {
                    Text(error)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzPink)
                }

                VStack(spacing: 12) {
                    ForzeeButton(
                        title: "Continue",
                        action: purchaseSelected,
                        isDisabled: selectedPackage == nil,
                        isLoading: purchaseManager.isPurchasing
                    )
                    ForzeeTextButton(title: "Restore Purchases", action: restore)
                }
            }
            .padding(ForzeeSpacing.screenPadding)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.smallGap) {
            Text("The more you use it,\nthe better Kai gets.")
                .font(.fzHeading(26, weight: .bold))
                .foregroundStyle(Color.fzText)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(text: "Unlimited coaching & adaptive workouts")
                FeatureRow(text: "Full context-aware AI — sleep, HRV, calendar, weather")
                FeatureRow(text: "Voice-guided coaching")
                FeatureRow(text: "Nutrition tracking & deep progress analytics")
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func purchaseSelected() {
        guard let package = selectedPackage else { return }
        Task {
            let success = await purchaseManager.purchase(package: package, userId: appState.userId)
            if success {
                dismiss()
            }
        }
    }

    private func restore() {
        Task {
            let success = await purchaseManager.restorePurchases(userId: appState.userId)
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - PackageRow

private struct PackageRow: View {
    let package: Package
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.fzBody(15, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                    Text(package.storeProduct.localizedPriceString)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzBorder)
            }
            .padding(ForzeeSpacing.cardPadding)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: ForzeeRadius.card)
                    .strokeBorder(isSelected ? Color.fzPrimary : Color.fzBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.fzPrimary)
                .padding(.top, 2)
            Text(text)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzTextSecondary)
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(AppState())
}
