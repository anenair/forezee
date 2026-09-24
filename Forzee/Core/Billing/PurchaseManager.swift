// ============================================================
// PurchaseManager.swift
// Forzee — Core/Billing
//
// Phase 2: wraps RevenueCat for the premium paywall. Reflects the
// resolved entitlement in AppState.subscriptionTier for the UI, and
// asks the sync-subscription Edge Function to update
// `profiles.subscription_tier`. The app can't write that column
// itself (see protect_subscription_columns in forzee_schema.sql) —
// otherwise anyone could grant themselves premium. The function
// asks RevenueCat directly, keyed on the Supabase user id that
// identify(userId:) logs in with.
//
// Entitlement identifier expected in RevenueCat: "premium"
//
// Guards every method against RevenueCat not being configured yet
// (no real REVENUECAT_API_KEY in Secrets.xcconfig). `Purchases.shared`
// is a force-unwrap internally — touching it before
// `Purchases.configure(...)` has run is a hard crash, not a throwable
// error, so `try?` around it does nothing. AppBootstrap skips
// configure() when the key is still a placeholder, so this class must
// never assume it ran. Degrades to the default free tier instead.
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

    // MARK: - Availability

    private var isAvailable: Bool { Purchases.isConfigured }

    // MARK: - Init

    private override init() {
        super.init()
        guard isAvailable else {
            #if DEBUG
            print("⚠️  PurchaseManager: RevenueCat not configured — purchases unavailable, defaulting to free tier.")
            #endif
            return
        }
        Purchases.shared.delegate = self
    }

    // MARK: - Identity

    /// Ties RevenueCat's customer record to the Supabase user, so
    /// sync-subscription can look purchases up by that id server-side.
    /// Call after every sign-in or session restore. logIn also moves any
    /// purchase made while anonymous onto this user.
    func identify(userId: String) async {
        guard isAvailable else { return }
        _ = try? await Purchases.shared.logIn(userId)
        await refreshCustomerInfo(userId: userId)
    }

    /// Call on sign-out so the next user on this device doesn't inherit
    /// this one's purchases.
    func resetIdentity() async {
        guard isAvailable, !Purchases.shared.isAnonymous else { return }
        _ = try? await Purchases.shared.logOut()
    }

    // MARK: - Offerings

    func loadOfferings() async {
        guard isAvailable else { return }
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
        guard isAvailable else {
            purchaseError = "Purchases aren't set up yet."
            return false
        }
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
        guard isAvailable else {
            purchaseError = "Purchases aren't set up yet."
            return false
        }
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
        guard isAvailable, let customerInfo = try? await Purchases.shared.customerInfo() else { return }
        await syncTier(from: customerInfo, userId: userId)
    }

    // MARK: - Private

    private func syncTier(from customerInfo: CustomerInfo, userId: String?) async {
        let isPremium = customerInfo.entitlements[Self.premiumEntitlementId]?.isActive == true
        let tier: SubscriptionTier = isPremium ? .premium : .free

        AppState.shared?.subscriptionTier = tier

        guard userId != nil else { return }
        await requestServerSync()
    }

    /// Best-effort: the server stays on its last-known tier if this fails,
    /// and the next launch or purchase retries it.
    private func requestServerSync() async {
        guard var request = try? await ForzeeDataService.shared.edgeFunctionRequest("sync-subscription") else { return }
        request.httpBody = Data("{}".utf8)
        _ = try? await URLSession.shared.data(for: request)
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
