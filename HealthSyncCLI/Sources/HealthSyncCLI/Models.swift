//
//  Models.swift
//  HealthSyncCLI
//
//  Data models for the CLI tool.
//

import Foundation

/// Pairing data from QR code
struct PairingData: Codable, Sendable {
    let host: String
    let port: Int
    let fingerprint: String
    let token: String
    let expiresAt: Date
}

/// Pairing result from server
struct PairingResult: Codable, Sendable {
    let accessToken: String
    let fingerprint: String
}

/// Server status response
struct ServerStatus: Codable, Sendable {
    let status: String
    let version: String
    let healthKitAvailable: Bool
}

/// Health data type info
struct HealthType: Codable, Sendable {
    let id: String
    let name: String
}

/// Health data record
struct HealthRecord: Codable, Sendable {
    let type: String
    let startDate: Date
    let endDate: Date
    let value: Double?
    let unit: String?
    let metadata: [String: String]?
    
    // For workouts
    let workoutType: String?
    let duration: Double?
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    
    // For sleep
    let sleepStage: String?
}

/// Fetch result from server
struct FetchResult: Codable, Sendable {
    let type: String
    let startDate: String
    let endDate: String
    let count: Int
    let records: [HealthRecord]
}

/// CLI configuration
struct Config: Codable, Sendable {
    var host: String
    var port: Int
    var fingerprint: String
    
    static let empty = Config(host: "", port: 8443, fingerprint: "")
}

/// Discovered server info
struct DiscoveredServer: Sendable {
    let name: String
    let host: String
    let port: Int
}
