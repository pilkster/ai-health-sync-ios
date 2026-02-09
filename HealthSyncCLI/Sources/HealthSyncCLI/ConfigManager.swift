//
//  ConfigManager.swift
//  HealthSyncCLI
//
//  Manages CLI configuration file storage.
//  Configuration is stored at ~/.healthsync/config.json
//  Note: Tokens are NOT stored here - they go in Keychain.
//

import Foundation

/// Manages CLI configuration storage
enum ConfigManager {
    /// Path to the config directory
    static var configDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.healthsync"
    }
    
    /// Path to the config file
    static var configPath: String {
        "\(configDirectory)/config.json"
    }
    
    /// Load configuration from disk
    /// - Returns: Configuration if it exists, nil otherwise
    static func load() throws -> Config? {
        let path = configPath
        
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        return try decoder.decode(Config.self, from: data)
    }
    
    /// Save configuration to disk
    /// - Parameter config: Configuration to save
    static func save(_ config: Config) throws {
        // Create directory if needed
        let dir = configDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700] // Owner only
            )
        }
        
        // Encode and write
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        
        // Write with restricted permissions
        let url = URL(fileURLWithPath: configPath)
        try data.write(to: url)
        
        // Set file permissions to owner read/write only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configPath
        )
    }
    
    /// Delete configuration file
    static func delete() throws {
        let path = configPath
        
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
    
    /// Check if configuration exists
    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }
}
