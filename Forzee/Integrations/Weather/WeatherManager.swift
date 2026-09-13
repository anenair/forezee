// ============================================================
// WeatherManager.swift
// Forzee — Integrations/Weather
//
// Phase 2: CoreLocation + WeatherKit. Tells Kai whether today
// is a good day to route the user outdoors or keep them inside.
// ============================================================

import Foundation
import CoreLocation
import WeatherKit

@MainActor
final class WeatherManager: NSObject, ObservableObject {

    // MARK: - Shared Instance

    static let shared = WeatherManager()

    // MARK: - Published State

    @Published var isAuthorized: Bool = false

    // MARK: - Result

    struct Signal {
        let condition: String       // e.g. "Clear, 68°F"
        let outdoorFriendly: Bool
    }

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private static let harshConditions: Set<WeatherCondition> = [
        .thunderstorms, .heavyRain, .heavySnow, .blizzard, .hail,
        .tropicalStorm, .hurricane, .strongStorms, .freezingRain, .sleet,
    ]

    private override init() {
        super.init()
        locationManager.delegate = self
        isAuthorized = Self.isAuthorizedStatus(locationManager.authorizationStatus)
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    private static func isAuthorizedStatus(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    // MARK: - Signal

    /// Fetches current conditions and whether they favour an outdoor session.
    /// Degrades to nil if location/weather is unavailable — never blocks Kai.
    func fetchTodaySignal() async -> Signal? {
        guard let location = await currentLocation() else { return nil }
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let tempF = current.temperature.converted(to: .fahrenheit).value
            let windMph = current.wind.speed.converted(to: .milesPerHour).value

            let condition = "\(current.condition.description), \(Int(tempF.rounded()))°F"
            let outdoorFriendly = isOutdoorFriendly(condition: current.condition, tempF: tempF, windMph: windMph)
            return Signal(condition: condition, outdoorFriendly: outdoorFriendly)
        } catch {
            #if DEBUG
            print("WeatherManager: fetch failed — \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Private

    private func isOutdoorFriendly(condition: WeatherCondition, tempF: Double, windMph: Double) -> Bool {
        guard !Self.harshConditions.contains(condition) else { return false }
        guard tempF > 25 && tempF < 100 else { return false }
        guard windMph < 30 else { return false }
        return true
    }

    private func currentLocation() async -> CLLocation? {
        guard Self.isAuthorizedStatus(locationManager.authorizationStatus) else { return nil }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isAuthorized = Self.isAuthorizedStatus(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
