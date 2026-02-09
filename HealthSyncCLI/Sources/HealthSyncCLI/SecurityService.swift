//
//  SecurityService.swift
//  HealthSyncCLI
//
//  Security utilities for the CLI tool.
//  Validates network addresses and certificates.
//

import Foundation
import Crypto

/// Security utilities for the CLI
enum SecurityService {
    /// Validate that a host is on a private/local network
    /// - Parameter host: The hostname or IP to validate
    /// - Returns: Whether the host is on a private network
    static func isPrivateNetwork(_ host: String) -> Bool {
        // Check for .local mDNS names
        if host.hasSuffix(".local") {
            return true
        }
        
        // Check for localhost
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        
        // Parse IP address and check for private ranges
        let components = host.split(separator: ".")
        guard components.count == 4,
              let first = Int(components[0]),
              let second = Int(components[1]) else {
            return false
        }
        
        // 10.0.0.0 - 10.255.255.255 (Class A private)
        if first == 10 {
            return true
        }
        
        // 172.16.0.0 - 172.31.255.255 (Class B private)
        if first == 172 && (16...31).contains(second) {
            return true
        }
        
        // 192.168.0.0 - 192.168.255.255 (Class C private)
        if first == 192 && second == 168 {
            return true
        }
        
        // 169.254.0.0 - 169.254.255.255 (Link-local)
        if first == 169 && second == 254 {
            return true
        }
        
        return false
    }
    
    /// Calculate SHA-256 fingerprint of certificate data
    /// - Parameter data: Certificate data
    /// - Returns: Hex-encoded fingerprint with colons
    static func calculateFingerprint(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined(separator: ":")
    }
    
    /// Verify a fingerprint matches expected value (TOFU)
    /// - Parameters:
    ///   - fingerprint: Fingerprint to verify
    ///   - host: Server host for looking up stored fingerprint
    /// - Returns: Whether the fingerprint is trusted
    static func verifyFingerprint(_ fingerprint: String, for host: String) -> Bool {
        // Check if we have a stored fingerprint (TOFU)
        if let storedFingerprint = KeychainService.loadTrustedFingerprint(for: host) {
            return fingerprint.lowercased() == storedFingerprint.lowercased()
        }
        
        // First connection - trust and store (TOFU)
        do {
            try KeychainService.saveTrustedFingerprint(fingerprint, for: host)
            return true
        } catch {
            return false
        }
    }
}
