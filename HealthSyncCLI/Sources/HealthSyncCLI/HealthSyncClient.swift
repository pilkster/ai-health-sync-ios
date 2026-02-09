//
//  HealthSyncClient.swift
//  HealthSyncCLI
//
//  HTTP client for communicating with the iOS Health Sync server.
//  Handles TLS with certificate pinning.
//

import Foundation
import Crypto

/// Client for communicating with Health Sync servers
final class HealthSyncClient: NSObject, Sendable {
    /// URL session with custom TLS handling
    private let session: URLSession
    
    /// Expected certificate fingerprint for pinning
    private var expectedFingerprint: String?
    
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        // We'll handle TLS validation in the delegate
        session = URLSession(configuration: config)
        
        super.init()
    }
    
    /// Create a session with certificate pinning
    private func createPinnedSession(fingerprint: String) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        return URLSession(
            configuration: config,
            delegate: CertificatePinningDelegate(expectedFingerprint: fingerprint),
            delegateQueue: nil
        )
    }
    
    // MARK: - API Methods
    
    /// Pair with a server using pairing data
    /// - Parameter pairingData: Pairing data from QR code
    /// - Returns: Pairing result with access token
    func pair(with pairingData: PairingData) async throws -> PairingResult {
        let url = URL(string: "https://\(pairingData.host):\(pairingData.port)/pair")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(pairingData.token)", forHTTPHeaderField: "Authorization")
        
        // Use pinned session
        let pinnedSession = createPinnedSession(fingerprint: pairingData.fingerprint)
        
        let (data, response) = try await pinnedSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ClientError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(PairingResult.self, from: data)
    }
    
    /// Check server status
    func status(
        host: String,
        port: Int,
        fingerprint: String,
        token: String
    ) async throws -> ServerStatus {
        let url = URL(string: "https://\(host):\(port)/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let pinnedSession = createPinnedSession(fingerprint: fingerprint)
        let (data, response) = try await pinnedSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ClientError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(ServerStatus.self, from: data)
    }
    
    /// List available health data types
    func types(
        host: String,
        port: Int,
        fingerprint: String,
        token: String
    ) async throws -> [HealthType] {
        let url = URL(string: "https://\(host):\(port)/types")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let pinnedSession = createPinnedSession(fingerprint: fingerprint)
        let (data, response) = try await pinnedSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ClientError.httpError(httpResponse.statusCode)
        }
        
        struct TypesResponse: Codable {
            let types: [HealthType]
        }
        
        let result = try JSONDecoder().decode(TypesResponse.self, from: data)
        return result.types
    }
    
    /// Fetch health data
    func fetch(
        host: String,
        port: Int,
        fingerprint: String,
        token: String,
        params: [String: String]
    ) async throws -> FetchResult {
        var components = URLComponents(string: "https://\(host):\(port)/health")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let pinnedSession = createPinnedSession(fingerprint: fingerprint)
        let (data, response) = try await pinnedSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ClientError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FetchResult.self, from: data)
    }
}

/// Client errors
enum ClientError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case certificateMismatch
    case connectionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .certificateMismatch:
            return "Certificate fingerprint does not match"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}

/// URLSession delegate for certificate pinning
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {
    private let expectedFingerprint: String
    
    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Get the server certificate
        guard let certificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCert = certificate.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Calculate fingerprint
        guard let certData = SecCertificateCopyData(serverCert) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let hash = SHA256.hash(data: certData)
        let fingerprint = hash.compactMap { String(format: "%02x", $0) }.joined(separator: ":")
        
        // Compare fingerprints
        if fingerprint.lowercased() == expectedFingerprint.lowercased() {
            // Certificate matches - accept
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Certificate mismatch - reject
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
