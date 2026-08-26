// ============================================================
// PurchaseManager.swift
// Forzee — Core/Billing
//
// Phase 2: wraps RevenueCat for the premium paywall. Syncs the
// resolved entitlement into AppState.subscriptionTier and mirrors
// it to the Supabase `profiles.subscription_tier` column so
// UsageGate and Kai's context snapshot both see it without a
// second network call.
//
// Entitlement identifier expected in RevenueCat: "premium"
// ============================================================

import Foundation
import RevenueCat

@MainActor
final class PurchaseManager: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = PurchaseManager()

    // MARK: - Constants

    static let premiumEntitlementId = "premium"

    // MARK: - Published State

    @Published var offerings: Offerings?
    @Published var isLoadingOfferings = false
    @Published var isPurchasing = false
    @Published var purchaseError: String?

    // MARK: - Init

    private override init() {
        super.init()
        Purchases.shared.delegate = self
    }

    // MARK: - Offerings

    func loadOfferings() async {
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    /// Purchases a package and, on success, syncs the resolved tier for `userId`.
    @discardableResult
    func purchase(package: Package, userId: String?) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        purchaseError = nil

        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            await syncTier(from: result.customerInfo, userId: userId)
            return true
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// Restores a previous purchase (e.g. after reinstall or device switch).
    @discardableResult
    func restorePurchases(userId: String?) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        purchaseError = nil

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await syncTier(from: customerInfo, userId: userId)
            return customerInfo.entitlements[Self.premiumEntitlementId]?.isActive == true
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// Refreshes the current entitlement state without a purchase flow —
    /// call on app foreground / Settings appear to catch renewals and expirations.
    func refreshCustomerInfo(userId: String?) async {
        guard let customerInfo = try? await Purchases.shared.customerInfo() else { return }
        await syncTier(from: customerInfo, userId: userId)
    }

    // MARK: - Private

    private func syncTier(from customerInfo: CustomerInfo, userId: String?) async {
        let isPremium = customerInfo.entitlements[Self.premiumEntitlementId]?.isActive == true
        let tier: SubscriptionTier = isPremium ? .premium : .free

        AppState.shared?.subscriptionTier = tier

        guard let userId else { return }
        try? await ForzeeDataService.shared.updateProfile(
            ["subscription_tier": tier.rawValue],
            userId: userId
        )
    }
}

// MARK: - PurchasesDelegate

extension PurchaseManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await self.syncTier(from: customerInfo, userId: AppState.shared?.userId)
        }
    }
}
