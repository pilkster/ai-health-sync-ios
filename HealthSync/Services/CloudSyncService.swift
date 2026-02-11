//
//  CloudSyncService.swift
//  HealthSync
//
//  Cloud sync service for posting HealthKit data to remote endpoint.
//  Handles data collection, formatting, and HTTP sync operations.
//

import Foundation
import Observation
import UIKit

/// Sync status states
enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case success(Date)
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "Not synced"
        case .syncing:
            return "Syncing..."
        case .success(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// Data models for sync payload
struct SyncPayload: Codable, Sendable {
    let deviceId: String
    let syncedAt: String
    let data: SyncData
}

struct SyncData: Codable, Sendable {
    let steps: [StepRecord]
    let activeEnergyBurned: [EnergyRecord]
    let heartRate: [HeartRateRecord]
    let restingHeartRate: [HeartRateRecord]
    let heartRateVariability: [HRVRecord]
    let sleep: [SleepRecord]
    let weight: [WeightRecord]
    let workouts: [WorkoutRecord]
}

struct StepRecord: Codable, Sendable {
    let date: String
    let value: Int
}

struct EnergyRecord: Codable, Sendable {
    let date: String
    let value: Double
}

struct HeartRateRecord: Codable, Sendable {
    let timestamp: String
    let value: Int
}

struct HRVRecord: Codable, Sendable {
    let timestamp: String
    let value: Double
}

struct SleepRecord: Codable, Sendable {
    let date: String
    let asleep: Int  // minutes
    let inBed: Int   // minutes
}

struct WeightRecord: Codable, Sendable {
    let date: String
    let value: Double  // kg
}

struct WorkoutRecord: Codable, Sendable {
    let type: String
    let start: String
    let duration: Double  // seconds
    let calories: Double?
}

/// Settings keys for UserDefaults
private enum CloudSyncKeys {
    static let endpointURL = "cloudSync.endpointURL"
    static let autoSyncEnabled = "cloudSync.autoSyncEnabled"
    static let lastSyncTimestamp = "cloudSync.lastSyncTimestamp"
    static let syncDaysRange = "cloudSync.syncDaysRange"
}

/// Service for syncing health data to cloud endpoint
@Observable
@MainActor
final class CloudSyncService: @unchecked Sendable {
    /// Current sync status
    private(set) var status: SyncStatus = .idle
    
    /// Cloud endpoint URL
    var endpointURL: String {
        didSet {
            UserDefaults.standard.set(endpointURL, forKey: CloudSyncKeys.endpointURL)
        }
    }
    
    /// Whether to auto-sync on app launch
    var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: CloudSyncKeys.autoSyncEnabled)
        }
    }
    
    /// Number of days to sync (default: 7)
    var syncDaysRange: Int {
        didSet {
            UserDefaults.standard.set(syncDaysRange, forKey: CloudSyncKeys.syncDaysRange)
        }
    }
    
    /// Last successful sync timestamp
    var lastSyncTimestamp: Date? {
        didSet {
            if let date = lastSyncTimestamp {
                UserDefaults.standard.set(date, forKey: CloudSyncKeys.lastSyncTimestamp)
            } else {
                UserDefaults.standard.removeObject(forKey: CloudSyncKeys.lastSyncTimestamp)
            }
        }
    }
    
    /// Unique device identifier
    private var deviceId: String {
        if let existingId = UserDefaults.standard.string(forKey: "cloudSync.deviceId") {
            return existingId
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "cloudSync.deviceId")
        return newId
    }
    
    /// Reference to HealthKit service
    private var healthService: HealthKitService?
    
    /// URL session for network requests
    private let session: URLSession
    
    /// ISO8601 date formatter
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Date-only formatter
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
    
    init() {
        // Load persisted settings
        self.endpointURL = UserDefaults.standard.string(forKey: CloudSyncKeys.endpointURL) 
            ?? "https://health.aineko.com"
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: CloudSyncKeys.autoSyncEnabled)
        self.syncDaysRange = UserDefaults.standard.integer(forKey: CloudSyncKeys.syncDaysRange)
        if self.syncDaysRange == 0 { self.syncDaysRange = 7 }
        self.lastSyncTimestamp = UserDefaults.standard.object(forKey: CloudSyncKeys.lastSyncTimestamp) as? Date
        
        // Configure URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        // Restore last status if we have a timestamp
        if let lastSync = lastSyncTimestamp {
            self.status = .success(lastSync)
        }
    }
    
    /// Configure the service with HealthKit dependency
    func configure(healthService: HealthKitService) {
        self.healthService = healthService
    }
    
    /// Perform sync to cloud endpoint
    func sync() async {
        guard let healthService = healthService else {
            status = .error("HealthKit not available")
            return
        }
        
        status = .syncing
        
        do {
            // Calculate date range
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -syncDaysRange, to: endDate)!
            
            // Fetch all health data
            let syncData = try await fetchAllHealthData(
                healthService: healthService,
                startDate: startDate,
                endDate: endDate
            )
            
            // Build payload
            let payload = SyncPayload(
                deviceId: deviceId,
                syncedAt: isoFormatter.string(from: Date()),
                data: syncData
            )
            
            // Send to cloud
            try await sendToCloud(payload: payload)
            
            let now = Date()
            lastSyncTimestamp = now
            status = .success(now)
            
        } catch {
            status = .error(error.localizedDescription)
        }
    }
    
    /// Fetch all health data types for sync
    private func fetchAllHealthData(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> SyncData {
        // Fetch daily aggregated steps
        let stepsRecords = try await fetchDailySteps(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch daily active energy
        let energyRecords = try await fetchDailyEnergy(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch heart rate samples
        let heartRateRecords = try await fetchHeartRate(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch resting heart rate
        let restingHRRecords = try await fetchRestingHeartRate(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch HRV
        let hrvRecords = try await fetchHRV(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch sleep
        let sleepRecords = try await fetchSleep(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch weight
        let weightRecords = try await fetchWeight(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        // Fetch workouts
        let workoutRecords = try await fetchWorkouts(
            healthService: healthService,
            startDate: startDate,
            endDate: endDate
        )
        
        return SyncData(
            steps: stepsRecords,
            activeEnergyBurned: energyRecords,
            heartRate: heartRateRecords,
            restingHeartRate: restingHRRecords,
            heartRateVariability: hrvRecords,
            sleep: sleepRecords,
            weight: weightRecords,
            workouts: workoutRecords
        )
    }
    
    // MARK: - Individual Data Fetchers
    
    private func fetchDailySteps(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [StepRecord] {
        let records = try await healthService.fetchStatistics(
            type: .steps,
            startDate: startDate,
            endDate: endDate,
            interval: DateComponents(day: 1)
        )
        
        return records.map { record in
            StepRecord(
                date: dateFormatter.string(from: record.startDate),
                value: Int(record.value ?? 0)
            )
        }
    }
    
    private func fetchDailyEnergy(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [EnergyRecord] {
        let records = try await healthService.fetchStatistics(
            type: .activeEnergy,
            startDate: startDate,
            endDate: endDate,
            interval: DateComponents(day: 1)
        )
        
        return records.map { record in
            EnergyRecord(
                date: dateFormatter.string(from: record.startDate),
                value: record.value ?? 0
            )
        }
    }
    
    private func fetchHeartRate(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [HeartRateRecord] {
        let records = try await healthService.fetchData(
            type: .heartRate,
            startDate: startDate,
            endDate: endDate,
            limit: 500
        )
        
        return records.map { record in
            HeartRateRecord(
                timestamp: isoFormatter.string(from: record.startDate),
                value: Int(record.value ?? 0)
            )
        }
    }
    
    private func fetchRestingHeartRate(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [HeartRateRecord] {
        // Resting heart rate is typically calculated daily
        // Use heartRate with filtering for low activity periods
        // For now, return empty - would need additional HK type
        return []
    }
    
    private func fetchHRV(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [HRVRecord] {
        // HRV requires HKQuantityType(.heartRateVariabilitySDNN)
        // For now, return empty - would need additional HK type support
        return []
    }
    
    private func fetchSleep(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [SleepRecord] {
        let records = try await healthService.fetchData(
            type: .sleepAnalysis,
            startDate: startDate,
            endDate: endDate,
            limit: 200
        )
        
        // Group by date and aggregate sleep stages
        var sleepByDate: [String: (asleep: Int, inBed: Int)] = [:]
        
        for record in records {
            let dateKey = dateFormatter.string(from: record.startDate)
            let duration = Int(record.endDate.timeIntervalSince(record.startDate) / 60)
            
            var existing = sleepByDate[dateKey] ?? (asleep: 0, inBed: 0)
            
            if let stage = record.sleepStage {
                if stage == "In Bed" {
                    existing.inBed += duration
                } else if stage != "Awake" {
                    existing.asleep += duration
                    existing.inBed += duration
                }
            }
            
            sleepByDate[dateKey] = existing
        }
        
        return sleepByDate.map { (date, times) in
            SleepRecord(date: date, asleep: times.asleep, inBed: times.inBed)
        }.sorted { $0.date > $1.date }
    }
    
    private func fetchWeight(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [WeightRecord] {
        let records = try await healthService.fetchData(
            type: .weight,
            startDate: startDate,
            endDate: endDate,
            limit: 50
        )
        
        return records.map { record in
            WeightRecord(
                date: dateFormatter.string(from: record.startDate),
                value: record.value ?? 0
            )
        }
    }
    
    private func fetchWorkouts(
        healthService: HealthKitService,
        startDate: Date,
        endDate: Date
    ) async throws -> [WorkoutRecord] {
        let records = try await healthService.fetchData(
            type: .workouts,
            startDate: startDate,
            endDate: endDate,
            limit: 100
        )
        
        return records.map { record in
            WorkoutRecord(
                type: record.workoutType?.lowercased().replacingOccurrences(of: " ", with: "_") ?? "unknown",
                start: isoFormatter.string(from: record.startDate),
                duration: record.duration ?? 0,
                calories: record.totalEnergyBurned
            )
        }
    }
    
    // MARK: - Network
    
    private func sendToCloud(payload: SyncPayload) async throws {
        guard let url = URL(string: "\(endpointURL)/sync/healthkit") else {
            throw CloudSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HealthSync-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudSyncError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudSyncError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
}

/// Cloud sync errors
enum CloudSyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String)
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid endpoint URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .encodingError:
            return "Failed to encode sync data"
        }
    }
}
