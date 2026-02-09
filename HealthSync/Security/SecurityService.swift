//
//  SecurityService.swift
//  HealthSync
//
//  Security service handling certificate generation, token management,
//  and Keychain operations for the TLS server.
//

import Foundation
import Security
import CryptoKit
import Observation

/// Token information for client pairing
struct PairingToken: Codable, Sendable {
    let token: String
    let expiresAt: Date
    let createdAt: Date
    
    /// Check if the token has expired
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    /// Generate a new pairing token (expires in 5 minutes)
    static func generate() -> PairingToken {
        let tokenData = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let token = Data(tokenData).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return PairingToken(
            token: token,
            expiresAt: Date().addingTimeInterval(5 * 60), // 5 minutes
            createdAt: Date()
        )
    }
}

/// QR code pairing data structure
struct PairingData: Codable, Sendable {
    let host: String
    let port: Int
    let fingerprint: String
    let token: String
    let expiresAt: Date
    
    /// Generate QR code string (JSON encoded)
    func toQRString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Security service for managing certificates, tokens, and Keychain operations
@Observable
@MainActor
final class SecurityService: @unchecked Sendable {
    // MARK: - Constants
    
    private static let keychainService = "org.mvneves.healthsync.ios"
    private static let tokenKeychainAccount = "pairing-token"
    private static let certKeychainAccount = "server-certificate"
    private static let keyKeychainAccount = "server-private-key"
    private static let permanentTokenAccount = "permanent-token"
    
    // MARK: - Properties
    
    /// The server's certificate fingerprint (SHA-256)
    private(set) var certificateFingerprint: String = ""
    
    /// Current active pairing token (temporary, for QR codes)
    private(set) var currentPairingToken: PairingToken?
    
    /// Whether security has been initialized
    private(set) var isInitialized = false
    
    /// The server's TLS identity
    private(set) var serverIdentity: SecIdentity?
    
    /// The server's certificate
    private(set) var serverCertificate: SecCertificate?
    
    /// The permanent access token (stored in Keychain)
    private(set) var permanentToken: String?
    
    // MARK: - Initialization
    
    /// Initialize security service, generating certificates if needed
    func initializeIfNeeded() async {
        guard !isInitialized else { return }
        
        // Try to load existing certificate from Keychain
        if let identity = loadIdentityFromKeychain() {
            serverIdentity = identity
            if let cert = extractCertificate(from: identity) {
                serverCertificate = cert
                certificateFingerprint = calculateFingerprint(of: cert)
            }
        } else {
            // Generate new self-signed certificate
            await generateSelfSignedCertificate()
        }
        
        // Load or generate permanent token
        if let token = loadPermanentToken() {
            permanentToken = token
        } else {
            let newToken = generateSecureToken()
            savePermanentToken(newToken)
            permanentToken = newToken
        }
        
        isInitialized = true
    }
    
    /// Generate a new temporary pairing token for QR codes
    func generatePairingToken() -> PairingToken {
        let token = PairingToken.generate()
        currentPairingToken = token
        return token
    }
    
    /// Validate a pairing token
    /// - Parameter token: The token string to validate
    /// - Returns: Whether the token is valid and not expired
    func validatePairingToken(_ token: String) -> Bool {
        guard let currentToken = currentPairingToken else { return false }
        
        // Check if token matches and hasn't expired
        if currentToken.token == token && !currentToken.isExpired {
            // Invalidate after successful use (one-time token)
            currentPairingToken = nil
            return true
        }
        
        return false
    }
    
    /// Validate the permanent access token
    /// - Parameter token: The token to validate
    /// - Returns: Whether the token is valid
    func validateAccessToken(_ token: String) -> Bool {
        return permanentToken == token
    }
    
    /// Generate pairing data for QR code
    /// - Parameters:
    ///   - host: The server hostname/IP
    ///   - port: The server port
    /// - Returns: Pairing data structure
    func generatePairingData(host: String, port: Int) -> PairingData {
        let token = generatePairingToken()
        
        return PairingData(
            host: host,
            port: port,
            fingerprint: certificateFingerprint,
            token: token.token,
            expiresAt: token.expiresAt
        )
    }
    
    // MARK: - Certificate Generation
    
    /// Generate a self-signed TLS certificate and store in Keychain
    private func generateSelfSignedCertificate() async {
        // Generate key pair
        let keyParameters: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyParameters as CFDictionary, &error) else {
            print("Failed to generate private key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            print("Failed to extract public key")
            return
        }
        
        // Create self-signed certificate using the legacy approach
        // Note: In production, consider using a proper certificate generation library
        let certificate = createSelfSignedCertificate(
            privateKey: privateKey,
            publicKey: publicKey
        )
        
        if let cert = certificate {
            serverCertificate = cert
            certificateFingerprint = calculateFingerprint(of: cert)
            
            // Create identity and store in Keychain
            if let identity = createAndStoreIdentity(certificate: cert, privateKey: privateKey) {
                serverIdentity = identity
            }
        }
    }
    
    /// Create a self-signed certificate
    private func createSelfSignedCertificate(
        privateKey: SecKey,
        publicKey: SecKey
    ) -> SecCertificate? {
        // For iOS, we need to use a different approach since we can't easily
        // create certificates programmatically. We'll use a PKCS#12 approach
        // or rely on Network.framework's automatic certificate handling.
        
        // For now, we'll generate a placeholder that will be replaced
        // by proper certificate generation in the network layer
        
        // Note: In a production app, you would either:
        // 1. Bundle a tool to generate certificates
        // 2. Use a server-side component to generate certificates
        // 3. Use Apple's CryptoTokenKit for certificate operations
        
        // For this implementation, we'll rely on Network.framework's
        // ability to handle TLS with programmatic trust evaluation
        
        return nil
    }
    
    /// Create identity from certificate and key, store in Keychain
    private func createAndStoreIdentity(
        certificate: SecCertificate,
        privateKey: SecKey
    ) -> SecIdentity? {
        // Store the private key
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "org.mvneves.healthsync.serverkey",
            kSecValueRef as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemDelete(keyQuery as CFDictionary)
        let keyStatus = SecItemAdd(keyQuery as CFDictionary, nil)
        
        if keyStatus != errSecSuccess && keyStatus != errSecDuplicateItem {
            print("Failed to store private key: \(keyStatus)")
            return nil
        }
        
        // Store the certificate
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemDelete(certQuery as CFDictionary)
        let certStatus = SecItemAdd(certQuery as CFDictionary, nil)
        
        if certStatus != errSecSuccess && certStatus != errSecDuplicateItem {
            print("Failed to store certificate: \(certStatus)")
            return nil
        }
        
        // Retrieve the identity
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true
        ]
        
        var identityRef: CFTypeRef?
        let status = SecItemCopyMatching(identityQuery as CFDictionary, &identityRef)
        
        if status == errSecSuccess, let identity = identityRef {
            return (identity as! SecIdentity)
        }
        
        return nil
    }
    
    /// Load existing identity from Keychain
    private func loadIdentityFromKeychain() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let identity = result {
            return (identity as! SecIdentity)
        }
        
        return nil
    }
    
    /// Extract certificate from identity
    private func extractCertificate(from identity: SecIdentity) -> SecCertificate? {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        return status == errSecSuccess ? certificate : nil
    }
    
    /// Calculate SHA-256 fingerprint of a certificate
    private func calculateFingerprint(of certificate: SecCertificate) -> String {
        guard let data = SecCertificateCopyData(certificate) as Data? else {
            return ""
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined(separator: ":")
    }
    
    // MARK: - Token Management
    
    /// Generate a secure random token
    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Save permanent token to Keychain
    private func savePermanentToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.permanentTokenAccount,
            kSecValueData as String: token.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Load permanent token from Keychain
    private func loadPermanentToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.permanentTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    // MARK: - Network Validation
    
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
}
