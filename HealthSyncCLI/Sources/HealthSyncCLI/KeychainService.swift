//
//  KeychainService.swift
//  HealthSyncCLI
//
//  Keychain operations for secure token storage.
//  Tokens are never stored in config files.
//

import Foundation
import Security

/// Service for Keychain operations
enum KeychainService {
    /// Keychain service identifier
    private static let service = "org.mvneves.healthsync.cli"
    
    /// Keychain account for the access token
    private static let tokenAccount = "access-token"
    
    /// Keychain account for certificate fingerprints (TOFU)
    private static let fingerprintAccount = "cert-fingerprint"
    
    // MARK: - Token Operations
    
    /// Save access token to Keychain
    /// - Parameter token: The access token to save
    /// - Throws: If the Keychain operation fails
    static func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete existing token first
        deleteToken()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Load access token from Keychain
    /// - Returns: The access token if found, nil otherwise
    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    /// Delete access token from Keychain
    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Fingerprint Operations (TOFU)
    
    /// Save trusted fingerprint to Keychain
    /// - Parameters:
    ///   - fingerprint: Certificate fingerprint
    ///   - host: Server hostname
    static func saveTrustedFingerprint(_ fingerprint: String, for host: String) throws {
        guard let data = fingerprint.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        let account = "\(fingerprintAccount)-\(host)"
        
        // Delete existing first
        deleteTrustedFingerprint(for: host)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Load trusted fingerprint from Keychain
    /// - Parameter host: Server hostname
    /// - Returns: The fingerprint if found
    static func loadTrustedFingerprint(for host: String) -> String? {
        let account = "\(fingerprintAccount)-\(host)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let fingerprint = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return fingerprint
    }
    
    /// Delete trusted fingerprint
    static func deleteTrustedFingerprint(for host: String) {
        let account = "\(fingerprintAccount)-\(host)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain errors
enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        }
    }
}
