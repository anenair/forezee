// ============================================================
// HealthKitManager.swift
// Forzee — Integrations/HealthKit
//
// Phase 2: the first leg of the life-signal pipeline. Reads
// steps, active energy, sleep, HRV, and mindful minutes so
// ContextBuilder can hand Kai a real picture of the user's day.
//
// Read-only — Forzee never writes back to Health except future
// workout logging (Phase 2/3, not implemented here).
// ============================================================

import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = HealthKitManager()

    // MARK: - Published State

    @Published var isAuthorized: Bool = false

    // MARK: - Private

    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let calories = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(calories) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
        return types
    }()

    private init() {}

    // MARK: - Authorization

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Requests read access for all Phase 2 signal types in one prompt.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else {
            isAuthorized = false
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            #if DEBUG
            print("HealthKitManager: authorization failed — \(error.localizedDescription)")
            #endif
            isAuthorized = false
        }
        return isAuthorized
    }

    // MARK: - Activity

    func fetchStepsToday() async -> Int? {
        guard isAuthorized, let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        let total = await sumQuantity(type: type, unit: .count(), predicate: predicate)
        return total.map { Int($0) }
    }

    func fetchActiveCaloriesToday() async -> Int? {
        guard isAuthorized, let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        let total = await sumQuantity(type: type, unit: .kilocalorie(), predicate: predicate)
        return total.map { Int($0) }
    }

    // MARK: - Sleep

    /// Average hours asleep per night over the trailing 7 days.
    func fetchSleepAvg7d() async -> Double? {
        guard isAuthorized, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        let asleepValues: Set<Int> = {
            if #available(iOS 16.0, *) {
                return [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
            }
            return [HKCategoryValueSleepAnalysis.asleep.rawValue]
        }()

        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let nights = max(1, Set(asleepSamples.map { Calendar.current.startOfDay(for: $0.startDate) }).count)
        return (totalSeconds / 3600.0) / Double(nights)
    }

    // MARK: - HRV / Recovery

    /// Compares the trailing 7-day average HRV (SDNN) to the prior 7 days
    /// to classify recovery trend for Kai's context snapshot.
    func fetchHRVTrend() async -> String? {
        guard isAuthorized, let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        async let recentAvg = averageHRV(daysAgoStart: 7, daysAgoEnd: 0, type: type)
        async let priorAvg = averageHRV(daysAgoStart: 14, daysAgoEnd: 7, type: type)

        guard let recent = await recentAvg, let prior = await priorAvg, prior > 0 else { return nil }

        let percentChange = (recent - prior) / prior
        if percentChange <= -0.08 { return "declining" }
        if percentChange >= 0.08 { return "improving" }
        return "stable"
    }

    private func averageHRV(daysAgoStart: Int, daysAgoEnd: Int, type: HKQuantityType) async -> Double? {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -daysAgoStart, to: .now),
              let end = cal.date(byAdding: .day, value: -daysAgoEnd, to: .now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await averageQuantity(type: type, unit: .secondUnit(with: .milli), predicate: predicate)
    }

    // MARK: - Stress / Mindfulness

    /// Minutes of logged mindfulness today — used as a lightweight stress proxy
    /// until a dedicated stress signal is available from wearables (Phase 3).
    func fetchMindfulMinutesToday() async -> Int? {
        guard isAuthorized, let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }
        let totalMinutes = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
        return Int(totalMinutes)
    }

    // MARK: - Query Helpers

    private func sumQuantity(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageQuantity(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
