//
//  HealthSync.swift
//  HealthSyncCLI
//
//  Main entry point for the healthsync CLI tool.
//  Provides commands for discovering, pairing with, and fetching data from
//  iOS Health Sync servers on the local network.
//

import ArgumentParser
import Foundation

/// Main command for the healthsync CLI
@main
struct HealthSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "healthsync",
        abstract: "Sync health data from your iPhone to your Mac.",
        version: "1.0.0",
        subcommands: [
            Discover.self,
            Scan.self,
            Status.self,
            Types.self,
            Fetch.self,
            Config.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Discover Command

/// Discover Health Sync servers on the local network using Bonjour
struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover Health Sync servers on your local network."
    )
    
    @Option(name: .shortAndLong, help: "Timeout in seconds for discovery.")
    var timeout: Int = 5
    
    func run() async throws {
        print("🔍 Searching for Health Sync servers...")
        
        let discovery = BonjourDiscovery()
        let servers = await discovery.discover(timeout: TimeInterval(timeout))
        
        if servers.isEmpty {
            print("\n⚠️  No servers found on the network.")
            print("   Make sure the Health Sync app is running on your iPhone")
            print("   and the server is started.")
        } else {
            print("\n✅ Found \(servers.count) server(s):\n")
            for server in servers {
                print("   📱 \(server.name)")
                print("      Host: \(server.host)")
                print("      Port: \(server.port)")
                print("")
            }
        }
    }
}

// MARK: - Scan Command

/// Scan a QR code to pair with a Health Sync server
struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan a QR code to pair with a Health Sync server."
    )
    
    @Option(name: .shortAndLong, help: "Manually provide pairing JSON instead of scanning.")
    var json: String?
    
    func run() async throws {
        let pairingData: PairingData
        
        if let jsonString = json {
            // Parse provided JSON
            guard let data = jsonString.data(using: .utf8) else {
                throw CLIError.invalidInput("Invalid JSON string")
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pairingData = try decoder.decode(PairingData.self, from: data)
        } else {
            // Use QR code scanner
            print("📷 Opening camera to scan QR code...")
            print("   Point your camera at the QR code shown on your iPhone.")
            print("")
            
            let scanner = QRScanner()
            guard let scannedData = try await scanner.scan() else {
                throw CLIError.scanFailed("Failed to scan QR code")
            }
            pairingData = scannedData
        }
        
        // Validate the pairing data
        guard SecurityService.isPrivateNetwork(pairingData.host) else {
            throw CLIError.securityError("Host '\(pairingData.host)' is not on a private network")
        }
        
        // Check if token is expired
        if pairingData.expiresAt < Date() {
            throw CLIError.tokenExpired("Pairing token has expired. Generate a new QR code.")
        }
        
        print("🔗 Connecting to \(pairingData.host):\(pairingData.port)...")
        
        // Exchange pairing token for permanent access
        let client = HealthSyncClient()
        let result = try await client.pair(with: pairingData)
        
        // Save configuration
        var config = try ConfigManager.load() ?? Config.empty
        config.host = pairingData.host
        config.port = pairingData.port
        config.fingerprint = result.fingerprint
        try ConfigManager.save(config)
        
        // Save token to Keychain
        try KeychainService.saveToken(result.accessToken)
        
        print("\n✅ Successfully paired with Health Sync server!")
        print("   Host: \(pairingData.host)")
        print("   Port: \(pairingData.port)")
        print("   Fingerprint: \(result.fingerprint.prefix(20))...")
        print("")
        print("   Run 'healthsync status' to verify the connection.")
    }
}

// MARK: - Status Command

/// Check the connection status with the configured server
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check connection status with the Health Sync server."
    )
    
    func run() async throws {
        guard let config = try ConfigManager.load() else {
            print("❌ Not configured. Run 'healthsync scan' to pair with a server.")
            return
        }
        
        guard let token = KeychainService.loadToken() else {
            print("❌ No access token found. Run 'healthsync scan' to pair with a server.")
            return
        }
        
        print("📡 Checking connection to \(config.host):\(config.port)...")
        
        let client = HealthSyncClient()
        do {
            let status = try await client.status(
                host: config.host,
                port: config.port,
                fingerprint: config.fingerprint,
                token: token
            )
            
            print("\n✅ Connected!")
            print("   Status: \(status.status)")
            print("   Version: \(status.version)")
            print("   HealthKit: \(status.healthKitAvailable ? "Available" : "Not Available")")
        } catch {
            print("\n❌ Connection failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Types Command

/// List available health data types
struct Types: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available health data types."
    )
    
    @Option(name: .shortAndLong, help: "Output format (table, json).")
    var format: OutputFormat = .table
    
    func run() async throws {
        guard let config = try ConfigManager.load() else {
            throw CLIError.notConfigured
        }
        
        guard let token = KeychainService.loadToken() else {
            throw CLIError.notConfigured
        }
        
        let client = HealthSyncClient()
        let types = try await client.types(
            host: config.host,
            port: config.port,
            fingerprint: config.fingerprint,
            token: token
        )
        
        switch format {
        case .table:
            print("\n📊 Available Health Data Types:\n")
            print("   ID                  Name")
            print("   ──────────────────  ────────────────────")
            for type in types {
                let paddedId = type.id.padding(toLength: 18, withPad: " ", startingAt: 0)
                print("   \(paddedId)  \(type.name)")
            }
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(types)
            print(String(data: data, encoding: .utf8) ?? "")
        case .csv:
            print("id,name")
            for type in types {
                print("\(type.id),\(type.name)")
            }
        }
    }
}

// MARK: - Fetch Command

/// Fetch health data from the server
struct Fetch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch health data from the server."
    )
    
    @Option(name: .shortAndLong, help: "Data type to fetch (e.g., steps, workouts, weight).")
    var type: String = "steps"
    
    @Option(name: .shortAndLong, help: "Number of days to fetch (default: 7).")
    var days: Int = 7
    
    @Option(name: .long, help: "Start date (ISO 8601 format).")
    var start: String?
    
    @Option(name: .long, help: "End date (ISO 8601 format).")
    var end: String?
    
    @Option(name: .shortAndLong, help: "Output format (csv, json).")
    var format: OutputFormat = .csv
    
    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String?
    
    @Flag(name: .long, help: "Include metadata in output.")
    var metadata: Bool = false
    
    func run() async throws {
        guard let config = try ConfigManager.load() else {
            throw CLIError.notConfigured
        }
        
        guard let token = KeychainService.loadToken() else {
            throw CLIError.notConfigured
        }
        
        let client = HealthSyncClient()
        
        // Build date parameters
        var params: [String: String] = ["type": type]
        
        if let startDate = start {
            params["start"] = startDate
        }
        if let endDate = end {
            params["end"] = endDate
        }
        if start == nil && end == nil {
            params["days"] = String(days)
        }
        
        print("📥 Fetching \(type) data...")
        
        let result = try await client.fetch(
            host: config.host,
            port: config.port,
            fingerprint: config.fingerprint,
            token: token,
            params: params
        )
        
        print("   Retrieved \(result.count) records")
        print("   Date range: \(result.startDate) to \(result.endDate)")
        print("")
        
        // Format output
        let outputString: String
        switch format {
        case .csv:
            outputString = formatCSV(records: result.records, includeMetadata: metadata)
        case .json:
            outputString = try formatJSON(records: result.records)
        case .table:
            outputString = formatTable(records: result.records)
        }
        
        // Write output
        if let outputPath = output {
            try outputString.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("✅ Data written to \(outputPath)")
        } else {
            print(outputString)
        }
    }
    
    private func formatCSV(records: [HealthRecord], includeMetadata: Bool) -> String {
        var lines = ["date,value,unit"]
        if records.first?.workoutType != nil {
            lines = ["date,workout_type,duration_minutes,energy_burned,distance"]
        }
        
        for record in records {
            if let workoutType = record.workoutType {
                let duration = record.duration.map { String(format: "%.1f", $0 / 60) } ?? ""
                let energy = record.totalEnergyBurned.map { String(format: "%.0f", $0) } ?? ""
                let distance = record.totalDistance.map { String(format: "%.0f", $0) } ?? ""
                lines.append("\(formatDate(record.startDate)),\(workoutType),\(duration),\(energy),\(distance)")
            } else {
                let value = record.value.map { String(format: "%.2f", $0) } ?? ""
                let unit = record.unit ?? ""
                lines.append("\(formatDate(record.startDate)),\(value),\(unit)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatJSON(records: [HealthRecord]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
    
    private func formatTable(records: [HealthRecord]) -> String {
        var lines: [String] = []
        
        if records.first?.workoutType != nil {
            lines.append("Date                 Type              Duration  Calories")
            lines.append("───────────────────  ────────────────  ────────  ────────")
            
            for record in records {
                let date = formatDate(record.startDate)
                let type = (record.workoutType ?? "").padding(toLength: 16, withPad: " ", startingAt: 0)
                let duration = record.duration.map { String(format: "%5.0fm", $0 / 60) } ?? "     -"
                let energy = record.totalEnergyBurned.map { String(format: "%6.0f", $0) } ?? "     -"
                lines.append("\(date)  \(type)  \(duration)   \(energy)")
            }
        } else {
            lines.append("Date                 Value        Unit")
            lines.append("───────────────────  ───────────  ─────────")
            
            for record in records {
                let date = formatDate(record.startDate)
                let value = record.value.map { String(format: "%11.2f", $0) } ?? "          -"
                let unit = record.unit ?? ""
                lines.append("\(date)  \(value)  \(unit)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }
}

// MARK: - Config Command

/// Manage CLI configuration
struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage CLI configuration.",
        subcommands: [
            ConfigShow.self,
            ConfigReset.self
        ],
        defaultSubcommand: ConfigShow.self
    )
}

struct ConfigShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current configuration."
    )
    
    func run() throws {
        guard let config = try ConfigManager.load() else {
            print("❌ Not configured. Run 'healthsync scan' to pair with a server.")
            return
        }
        
        print("\n📋 Current Configuration:\n")
        print("   Host:        \(config.host)")
        print("   Port:        \(config.port)")
        print("   Fingerprint: \(config.fingerprint)")
        print("")
        print("   Config file: \(ConfigManager.configPath)")
        
        if KeychainService.loadToken() != nil {
            print("   Token:       ✅ Stored in Keychain")
        } else {
            print("   Token:       ❌ Not found")
        }
    }
}

struct ConfigReset: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset configuration and remove stored credentials."
    )
    
    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force: Bool = false
    
    func run() throws {
        if !force {
            print("⚠️  This will remove all configuration and credentials.")
            print("   You will need to re-scan the QR code to reconnect.")
            print("")
            print("   Type 'yes' to confirm: ", terminator: "")
            
            guard let input = readLine(), input.lowercased() == "yes" else {
                print("   Cancelled.")
                return
            }
        }
        
        try ConfigManager.delete()
        KeychainService.deleteToken()
        
        print("✅ Configuration reset.")
    }
}

// MARK: - Supporting Types

/// Output format options
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case csv
    case json
    case table
}

/// CLI errors
enum CLIError: LocalizedError {
    case notConfigured
    case invalidInput(String)
    case scanFailed(String)
    case connectionFailed(String)
    case securityError(String)
    case tokenExpired(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Not configured. Run 'healthsync scan' to pair with a server."
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .scanFailed(let message):
            return "Scan failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .securityError(let message):
            return "Security error: \(message)"
        case .tokenExpired(let message):
            return "Token expired: \(message)"
        }
    }
}
