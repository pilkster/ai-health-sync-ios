//
//  HealthKitService.swift
//  HealthSync
//
//  Service for interacting with HealthKit data store.
//  Handles authorization, data queries, and type mapping.
//

import Foundation
import HealthKit
import Observation

/// Supported health data types for sync operations
enum HealthDataType: String, CaseIterable, Codable, Sendable {
    case steps = "steps"
    case workouts = "workouts"
    case weight = "weight"
    case dietaryEnergy = "dietary_energy"
    case protein = "protein"
    case carbohydrates = "carbohydrates"
    case fat = "fat"
    case fiber = "fiber"
    case sugar = "sugar"
    case water = "water"
    case caffeine = "caffeine"
    case activeEnergy = "active_energy"
    case restingEnergy = "resting_energy"
    case heartRate = "heart_rate"
    case sleepAnalysis = "sleep_analysis"
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .workouts: return "Workouts"
        case .weight: return "Body Weight"
        case .dietaryEnergy: return "Dietary Energy"
        case .protein: return "Protein"
        case .carbohydrates: return "Carbohydrates"
        case .fat: return "Total Fat"
        case .fiber: return "Fiber"
        case .sugar: return "Sugar"
        case .water: return "Water"
        case .caffeine: return "Caffeine"
        case .activeEnergy: return "Active Energy"
        case .restingEnergy: return "Resting Energy"
        case .heartRate: return "Heart Rate"
        case .sleepAnalysis: return "Sleep Analysis"
        }
    }
    
    /// Corresponding HealthKit type identifier
    var healthKitType: HKSampleType? {
        switch self {
        case .steps:
            return HKQuantityType(.stepCount)
        case .workouts:
            return HKWorkoutType.workoutType()
        case .weight:
            return HKQuantityType(.bodyMass)
        case .dietaryEnergy:
            return HKQuantityType(.dietaryEnergyConsumed)
        case .protein:
            return HKQuantityType(.dietaryProtein)
        case .carbohydrates:
            return HKQuantityType(.dietaryCarbohydrates)
        case .fat:
            return HKQuantityType(.dietaryFatTotal)
        case .fiber:
            return HKQuantityType(.dietaryFiber)
        case .sugar:
            return HKQuantityType(.dietarySugar)
        case .water:
            return HKQuantityType(.dietaryWater)
        case .caffeine:
            return HKQuantityType(.dietaryCaffeine)
        case .activeEnergy:
            return HKQuantityType(.activeEnergyBurned)
        case .restingEnergy:
            return HKQuantityType(.basalEnergyBurned)
        case .heartRate:
            return HKQuantityType(.heartRate)
        case .sleepAnalysis:
            return HKCategoryType(.sleepAnalysis)
        }
    }
    
    /// Unit for quantity types
    var unit: HKUnit? {
        switch self {
        case .steps: return .count()
        case .workouts: return nil
        case .weight: return .gramUnit(with: .kilo)
        case .dietaryEnergy: return .kilocalorie()
        case .protein, .carbohydrates, .fat, .fiber, .sugar:
            return .gram()
        case .water: return .literUnit(with: .milli)
        case .caffeine: return .gramUnit(with: .milli)
        case .activeEnergy, .restingEnergy: return .kilocalorie()
        case .heartRate: return HKUnit.count().unitDivided(by: .minute())
        case .sleepAnalysis: return nil
        }
    }
}

/// Generic health data record for JSON serialization
struct HealthRecord: Codable, Sendable {
    let type: String
    let startDate: Date
    let endDate: Date
    let value: Double?
    let unit: String?
    let metadata: [String: String]?
    
    /// For workouts
    let workoutType: String?
    let duration: Double?
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    
    /// For sleep
    let sleepStage: String?
}

/// Service for accessing HealthKit data with proper authorization handling
@Observable
@MainActor
final class HealthKitService: @unchecked Sendable {
    /// HealthKit store instance
    private let healthStore = HKHealthStore()
    
    /// Whether HealthKit is available on this device
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Current authorization status
    private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    /// All read types we request access to
    private var readTypes: Set<HKSampleType> {
        Set(HealthDataType.allCases.compactMap { $0.healthKitType })
    }
    
    /// Request authorization for all health data types
    /// - Returns: Whether authorization was granted
    func requestAuthorization() async throws -> Bool {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }
        
        try await healthStore.requestAuthorization(
            toShare: [],  // We only read, never write
            read: readTypes
        )
        
        return true
    }
    
    /// Fetch health data for a specific type within a date range
    /// - Parameters:
    ///   - type: The health data type to fetch
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    ///   - limit: Maximum number of records (default: 1000)
    /// - Returns: Array of health records
    func fetchData(
        type: HealthDataType,
        startDate: Date,
        endDate: Date,
        limit: Int = 1000
    ) async throws -> [HealthRecord] {
        guard let sampleType = type.healthKitType else {
            throw HealthKitError.unsupportedType
        }
        
        // Create date predicate
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        // Sort by date descending
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let samples = samples else {
                    continuation.resume(returning: [])
                    return
                }
                
                let records = self?.convertSamples(samples, type: type) ?? []
                continuation.resume(returning: records)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Fetch aggregated statistics for a quantity type
    /// - Parameters:
    ///   - type: The health data type to aggregate
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    ///   - interval: Aggregation interval (daily, weekly, etc.)
    /// - Returns: Array of aggregated records
    func fetchStatistics(
        type: HealthDataType,
        startDate: Date,
        endDate: Date,
        interval: DateComponents
    ) async throws -> [HealthRecord] {
        guard let quantityType = type.healthKitType as? HKQuantityType,
              let unit = type.unit else {
            throw HealthKitError.unsupportedType
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .discreteAverage],
                anchorDate: startDate,
                intervalComponents: interval
            )
            
            query.initialResultsHandler = { _, collection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let collection = collection else {
                    continuation.resume(returning: [])
                    return
                }
                
                var records: [HealthRecord] = []
                collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let value: Double?
                    if let sum = statistics.sumQuantity() {
                        value = sum.doubleValue(for: unit)
                    } else if let avg = statistics.averageQuantity() {
                        value = avg.doubleValue(for: unit)
                    } else {
                        value = nil
                    }
                    
                    if let value = value {
                        records.append(HealthRecord(
                            type: type.rawValue,
                            startDate: statistics.startDate,
                            endDate: statistics.endDate,
                            value: value,
                            unit: unit.unitString,
                            metadata: nil,
                            workoutType: nil,
                            duration: nil,
                            totalEnergyBurned: nil,
                            totalDistance: nil,
                            sleepStage: nil
                        ))
                    }
                }
                
                continuation.resume(returning: records)
            }
            
            healthStore.execute(query)
        }
    }
    
    /// Convert HealthKit samples to our generic HealthRecord format
    private func convertSamples(_ samples: [HKSample], type: HealthDataType) -> [HealthRecord] {
        samples.compactMap { sample -> HealthRecord? in
            switch sample {
            case let quantitySample as HKQuantitySample:
                guard let unit = type.unit else { return nil }
                let value = quantitySample.quantity.doubleValue(for: unit)
                return HealthRecord(
                    type: type.rawValue,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    value: value,
                    unit: unit.unitString,
                    metadata: convertMetadata(sample.metadata),
                    workoutType: nil,
                    duration: nil,
                    totalEnergyBurned: nil,
                    totalDistance: nil,
                    sleepStage: nil
                )
                
            case let workout as HKWorkout:
                return HealthRecord(
                    type: type.rawValue,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    value: nil,
                    unit: nil,
                    metadata: convertMetadata(workout.metadata),
                    workoutType: workout.workoutActivityType.name,
                    duration: workout.duration,
                    totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
                    sleepStage: nil
                )
                
            case let categorySample as HKCategorySample:
                let sleepStage: String?
                if type == .sleepAnalysis {
                    sleepStage = HKCategoryValueSleepAnalysis(rawValue: categorySample.value)?.name
                } else {
                    sleepStage = nil
                }
                
                return HealthRecord(
                    type: type.rawValue,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    value: Double(categorySample.value),
                    unit: nil,
                    metadata: convertMetadata(sample.metadata),
                    workoutType: nil,
                    duration: nil,
                    totalEnergyBurned: nil,
                    totalDistance: nil,
                    sleepStage: sleepStage
                )
                
            default:
                return nil
            }
        }
    }
    
    /// Convert HealthKit metadata to string dictionary
    private func convertMetadata(_ metadata: [String: Any]?) -> [String: String]? {
        guard let metadata = metadata, !metadata.isEmpty else { return nil }
        
        var result: [String: String] = [:]
        for (key, value) in metadata {
            result[key] = String(describing: value)
        }
        return result
    }
}

/// Errors that can occur during HealthKit operations
enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case unsupportedType
    case queryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "HealthKit authorization was denied"
        case .unsupportedType:
            return "This health data type is not supported"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}

// MARK: - HealthKit Type Extensions

extension HKWorkoutActivityType {
    /// Human-readable name for workout types
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Weight Training"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .highIntensityIntervalTraining: return "HIIT"
        case .pilates: return "Pilates"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        default: return "Workout"
        }
    }
}

extension HKCategoryValueSleepAnalysis {
    /// Human-readable name for sleep stages
    var name: String {
        switch self {
        case .inBed: return "In Bed"
        case .asleepUnspecified: return "Asleep"
        case .awake: return "Awake"
        case .asleepCore: return "Core Sleep"
        case .asleepDeep: return "Deep Sleep"
        case .asleepREM: return "REM Sleep"
        @unknown default: return "Unknown"
        }
    }
}
