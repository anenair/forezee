// ============================================================
// AppDelegate.swift
// Forzee
//
// SwiftUI's App protocol has no hook for the APNs device-token
// callbacks — they only exist on UIApplicationDelegate. Bridged
// in via @UIApplicationDelegateAdaptor in ForzeeApp.
// ============================================================

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            guard let userId = AppState.shared?.userId else { return }
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            try? await ForzeeDataService.shared.saveDeviceToken(token, environment: environment, userId: userId)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("AppDelegate: remote notification registration failed — \(error.localizedDescription)")
        #endif
    }
}
