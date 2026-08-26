// ============================================================
// AppBootstrap.swift
// Forzee
//
// Configures all third-party SDKs at app launch.
// Called once from ForzeeApp.init() before any UI is shown.
// ============================================================

import Foundation
import RevenueCat

enum AppBootstrap {

    /// Configure all external SDKs.
    /// Called once in ForzeeApp.init().
    @MainActor
    static func configure() {
        configureRevenueCat()
        // Touch PurchaseManager.shared now so its PurchasesDelegate is
        // registered before any StoreKit transaction can arrive — waiting
        // for the Settings tab to lazily init it would risk missing one.
        _ = PurchaseManager.shared
        // Supabase client is configured lazily in ForzeeDataService.shared
    }

    // MARK: - Private

    private static func configureRevenueCat() {
        let apiKey = Bundle.main.infoDictionary?["REVENUECAT_API_KEY"] as? String ?? ""
        guard !apiKey.isEmpty, !apiKey.hasPrefix("appl_your") else {
            #if DEBUG
            print("⚠️  RevenueCat: API key not configured. Subscriptions will not work.")
            #endif
            return
        }
        Purchases.configure(withAPIKey: apiKey)
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
    }
}
