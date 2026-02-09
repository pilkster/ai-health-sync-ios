//
//  HealthSyncCLITests.swift
//  HealthSyncCLI
//
//  Unit tests for critical CLI functionality.
//

import Testing
import Foundation
@testable import HealthSyncCLI

@Suite("Security Service Tests")
struct SecurityServiceTests {
    
    @Test("Private network detection - localhost")
    func testLocalhostIsPrivate() {
        #expect(SecurityService.isPrivateNetwork("localhost"))
        #expect(SecurityService.isPrivateNetwork("127.0.0.1"))
        #expect(SecurityService.isPrivateNetwork("::1"))
    }
    
    @Test("Private network detection - .local domains")
    func testLocalDomainIsPrivate() {
        #expect(SecurityService.isPrivateNetwork("myphone.local"))
        #expect(SecurityService.isPrivateNetwork("iphone.local"))
    }
    
    @Test("Private network detection - Class A private")
    func testClassAPrivate() {
        #expect(SecurityService.isPrivateNetwork("10.0.0.1"))
        #expect(SecurityService.isPrivateNetwork("10.255.255.255"))
        #expect(SecurityService.isPrivateNetwork("10.1.2.3"))
    }
    
    @Test("Private network detection - Class B private")
    func testClassBPrivate() {
        #expect(SecurityService.isPrivateNetwork("172.16.0.1"))
        #expect(SecurityService.isPrivateNetwork("172.31.255.255"))
        #expect(SecurityService.isPrivateNetwork("172.20.1.1"))
        
        // Not private - outside 172.16-31 range
        #expect(!SecurityService.isPrivateNetwork("172.15.0.1"))
        #expect(!SecurityService.isPrivateNetwork("172.32.0.1"))
    }
    
    @Test("Private network detection - Class C private")
    func testClassCPrivate() {
        #expect(SecurityService.isPrivateNetwork("192.168.0.1"))
        #expect(SecurityService.isPrivateNetwork("192.168.255.255"))
        #expect(SecurityService.isPrivateNetwork("192.168.1.100"))
    }
    
    @Test("Private network detection - Link-local")
    func testLinkLocal() {
        #expect(SecurityService.isPrivateNetwork("169.254.0.1"))
        #expect(SecurityService.isPrivateNetwork("169.254.255.255"))
    }
    
    @Test("Public addresses are not private")
    func testPublicAddresses() {
        #expect(!SecurityService.isPrivateNetwork("8.8.8.8"))
        #expect(!SecurityService.isPrivateNetwork("1.1.1.1"))
        #expect(!SecurityService.isPrivateNetwork("142.250.80.46"))
        #expect(!SecurityService.isPrivateNetwork("example.com"))
    }
    
    @Test("Certificate fingerprint calculation")
    func testFingerprintCalculation() {
        let testData = "test certificate data".data(using: .utf8)!
        let fingerprint = SecurityService.calculateFingerprint(testData)
        
        // Should be SHA-256 format (64 hex chars with colons)
        #expect(fingerprint.contains(":"))
        
        let parts = fingerprint.split(separator: ":")
        #expect(parts.count == 32) // 32 bytes = 32 hex pairs
        
        // Each part should be 2 hex characters
        for part in parts {
            #expect(part.count == 2)
        }
    }
}

@Suite("Config Manager Tests")
struct ConfigManagerTests {
    
    @Test("Config path is in home directory")
    func testConfigPath() {
        let path = ConfigManager.configPath
        #expect(path.contains(".healthsync"))
        #expect(path.hasSuffix("config.json"))
    }
    
    @Test("Empty config has default values")
    func testEmptyConfig() {
        let config = Config.empty
        #expect(config.host == "")
        #expect(config.port == 8443)
        #expect(config.fingerprint == "")
    }
}

@Suite("Model Tests")
struct ModelTests {
    
    @Test("PairingData decoding")
    func testPairingDataDecoding() throws {
        let json = """
        {
            "host": "192.168.1.100",
            "port": 8443,
            "fingerprint": "aa:bb:cc:dd",
            "token": "test-token",
            "expiresAt": "2024-01-01T12:00:00Z"
        }
        """
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = json.data(using: .utf8)!
        let pairing = try decoder.decode(PairingData.self, from: data)
        
        #expect(pairing.host == "192.168.1.100")
        #expect(pairing.port == 8443)
        #expect(pairing.fingerprint == "aa:bb:cc:dd")
        #expect(pairing.token == "test-token")
    }
    
    @Test("HealthRecord decoding")
    func testHealthRecordDecoding() throws {
        let json = """
        {
            "type": "steps",
            "startDate": "2024-01-01T00:00:00Z",
            "endDate": "2024-01-01T23:59:59Z",
            "value": 10000,
            "unit": "count",
            "metadata": null,
            "workoutType": null,
            "duration": null,
            "totalEnergyBurned": null,
            "totalDistance": null,
            "sleepStage": null
        }
        """
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = json.data(using: .utf8)!
        let record = try decoder.decode(HealthRecord.self, from: data)
        
        #expect(record.type == "steps")
        #expect(record.value == 10000)
        #expect(record.unit == "count")
    }
    
    @Test("Workout record decoding")
    func testWorkoutRecordDecoding() throws {
        let json = """
        {
            "type": "workouts",
            "startDate": "2024-01-01T08:00:00Z",
            "endDate": "2024-01-01T09:00:00Z",
            "value": null,
            "unit": null,
            "metadata": null,
            "workoutType": "Running",
            "duration": 3600,
            "totalEnergyBurned": 450,
            "totalDistance": 5000,
            "sleepStage": null
        }
        """
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = json.data(using: .utf8)!
        let record = try decoder.decode(HealthRecord.self, from: data)
        
        #expect(record.type == "workouts")
        #expect(record.workoutType == "Running")
        #expect(record.duration == 3600)
        #expect(record.totalEnergyBurned == 450)
        #expect(record.totalDistance == 5000)
    }
}
