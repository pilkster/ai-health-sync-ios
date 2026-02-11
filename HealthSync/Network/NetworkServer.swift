//
//  NetworkServer.swift
//  HealthSync
//
//  TLS network server using Network.framework for secure local network
//  health data API. Handles client connections, authentication, and
//  health data requests.
//

import Foundation
import Network
import Observation

/// Server configuration
struct ServerConfig: Sendable {
    let port: UInt16
    let requireAuth: Bool
    
    static let `default` = ServerConfig(port: 8443, requireAuth: true)
}

/// Server state
enum ServerState: Sendable, Equatable {
    case stopped
    case starting
    case running(port: UInt16)
    case error(String)
    
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running(let port): return "Running on port \(port)"
        case .error(let message): return "Error: \(message)"
        }
    }
}

/// HTTP request parsed from raw data
struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
    let queryParameters: [String: String]
    
    /// Parse HTTP request from raw data
    static func parse(from data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let lines = string.components(separatedBy: "\r\n")
        guard lines.count > 0 else { return nil }
        
        // Parse request line
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }
        
        let method = requestLine[0]
        let fullPath = requestLine[1]
        
        // Parse path and query parameters
        let pathComponents = fullPath.components(separatedBy: "?")
        let path = pathComponents[0]
        var queryParameters: [String: String] = [:]
        
        if pathComponents.count > 1 {
            let queryString = pathComponents[1]
            for param in queryString.components(separatedBy: "&") {
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    let key = parts[0].removingPercentEncoding ?? parts[0]
                    let value = parts[1].removingPercentEncoding ?? parts[1]
                    queryParameters[key] = value
                }
            }
        }
        
        // Parse headers
        var headers: [String: String] = [:]
        var bodyStartIndex = 1
        
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty {
                bodyStartIndex = i + 1
                break
            }
            
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }
        
        // Parse body
        var body: Data?
        if bodyStartIndex < lines.count {
            let bodyString = lines[bodyStartIndex...].joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }
        
        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body,
            queryParameters: queryParameters
        )
    }
}

/// TLS network server for health data API
@Observable
@MainActor
final class NetworkServer: @unchecked Sendable {
    // MARK: - Properties
    
    /// Current server state
    private(set) var state: ServerState = .stopped
    
    /// Connected clients count
    private(set) var connectedClients: Int = 0
    
    /// Local network addresses
    private(set) var localAddresses: [String] = []
    
    /// Dependencies
    private let securityService: SecurityService
    private let healthService: HealthKitService
    private let auditService: AuditService
    
    /// Network listener
    private var listener: NWListener?
    
    /// Active connections
    private var connections: [NWConnection] = []
    
    /// Configuration
    private let config: ServerConfig
    
    /// Dispatch queue for network operations
    private let queue = DispatchQueue(label: "org.mvneves.healthsync.server", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init(
        securityService: SecurityService,
        healthService: HealthKitService,
        auditService: AuditService,
        config: ServerConfig = .default
    ) {
        self.securityService = securityService
        self.healthService = healthService
        self.auditService = auditService
        self.config = config
    }
    
    // MARK: - Server Control
    
    /// Start the TLS server
    func start() async {
        guard !state.isRunning else { return }
        
        await MainActor.run {
            state = .starting
        }
        
        do {
            // Create TLS parameters
            let tlsOptions = NWProtocolTLS.Options()
            
            // Configure TLS with our certificate if available
            if let identity = securityService.serverIdentity {
                sec_protocol_options_set_local_identity(
                    tlsOptions.securityProtocolOptions,
                    sec_identity_create(identity)!
                )
            }
            
            // Set minimum TLS version
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions,
                .TLSv12
            )
            
            // Create TCP + TLS parameters
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 30
            
            let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true
            
            // Create listener
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: config.port))
            self.listener = listener
            
            // Handle state updates
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    self?.handleListenerState(newState)
                }
            }
            
            // Handle new connections
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            
            // Start listening
            listener.start(queue: queue)
            
            // Update local addresses
            await updateLocalAddresses()
            
        } catch {
            await MainActor.run {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    /// Stop the server
    func stop() async {
        listener?.cancel()
        listener = nil
        
        // Close all connections
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        await MainActor.run {
            state = .stopped
            connectedClients = 0
        }
    }
    
    // MARK: - Connection Handling
    
    /// Handle listener state changes
    private func handleListenerState(_ newState: NWListener.State) {
        Task { @MainActor in
            switch newState {
            case .ready:
                self.state = .running(port: self.config.port)
            case .failed(let error):
                self.state = .error(error.localizedDescription)
            case .cancelled:
                self.state = .stopped
            default:
                break
            }
        }
    }
    
    /// Handle new incoming connection
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        Task { @MainActor in
            connectedClients = connections.count
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveData(on: connection)
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: queue)
    }
    
    /// Remove a connection
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        
        Task { @MainActor in
            connectedClients = connections.count
        }
    }
    
    /// Receive data from a connection
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let data = data, !data.isEmpty {
                    self.handleRequest(data: data, connection: connection)
                }
                
                if isComplete || error != nil {
                    self.removeConnection(connection)
                } else {
                    self.receiveData(on: connection)
                }
            }
        }
    }
    
    /// Handle an incoming HTTP request
    private func handleRequest(data: Data, connection: NWConnection) {
        guard let request = HTTPRequest.parse(from: data) else {
            sendResponse(
                connection: connection,
                statusCode: 400,
                body: ["error": "Invalid request"]
            )
            return
        }
        
        // Get client address for logging
        let clientAddress = connection.endpoint.debugDescription
        
        Task { @MainActor in
            // Authenticate request
            let authResult = await authenticate(request: request)
            
            if !authResult.authenticated {
                await auditService.log(
                    action: .authenticationFailed,
                    clientAddress: clientAddress,
                    details: "Failed authentication attempt"
                )
                
                sendResponse(
                    connection: connection,
                    statusCode: 401,
                    body: ["error": "Unauthorized"]
                )
                return
            }
            
            // Route request
            await routeRequest(
                request: request,
                connection: connection,
                clientAddress: clientAddress
            )
        }
    }
    
    /// Authenticate a request
    private func authenticate(request: HTTPRequest) async -> (authenticated: Bool, token: String?) {
        // Check for Authorization header
        guard let authHeader = request.headers["authorization"] else {
            return (false, nil)
        }
        
        // Support "Bearer <token>" format
        let parts = authHeader.components(separatedBy: " ")
        guard parts.count == 2, parts[0].lowercased() == "bearer" else {
            return (false, nil)
        }
        
        let token = parts[1]
        
        // First check if it's a pairing token
        if securityService.validatePairingToken(token) {
            return (true, token)
        }
        
        // Then check if it's the permanent access token
        if securityService.validateAccessToken(token) {
            return (true, token)
        }
        
        return (false, nil)
    }
    
    /// Route request to appropriate handler
    private func routeRequest(
        request: HTTPRequest,
        connection: NWConnection,
        clientAddress: String
    ) async {
        switch (request.method, request.path) {
        case ("GET", "/status"):
            await handleStatus(request: request, connection: connection, clientAddress: clientAddress)
            
        case ("GET", "/types"):
            await handleTypes(request: request, connection: connection, clientAddress: clientAddress)
            
        case ("GET", "/health"):
            await handleHealthFetch(request: request, connection: connection, clientAddress: clientAddress)
            
        case ("POST", "/pair"):
            await handlePair(request: request, connection: connection, clientAddress: clientAddress)
            
        default:
            sendResponse(
                connection: connection,
                statusCode: 404,
                body: ["error": "Not found"]
            )
        }
    }
    
    // MARK: - Request Handlers
    
    /// Handle status check
    private func handleStatus(request: HTTPRequest, connection: NWConnection, clientAddress: String) async {
        await auditService.log(
            action: .statusCheck,
            clientAddress: clientAddress,
            details: "Status check"
        )
        
        sendResponse(
            connection: connection,
            statusCode: 200,
            body: [
                "status": "ok",
                "version": "1.0.0",
                "healthKitAvailable": healthService.isAvailable
            ]
        )
    }
    
    /// Handle listing available types
    private func handleTypes(request: HTTPRequest, connection: NWConnection, clientAddress: String) async {
        await auditService.log(
            action: .typesListed,
            clientAddress: clientAddress,
            details: "Listed available types"
        )
        
        let types = HealthDataType.allCases.map { type in
            [
                "id": type.rawValue,
                "name": type.displayName
            ]
        }
        
        sendResponse(
            connection: connection,
            statusCode: 200,
            body: ["types": types]
        )
    }
    
    /// Handle health data fetch
    private func handleHealthFetch(request: HTTPRequest, connection: NWConnection, clientAddress: String) async {
        // Parse query parameters
        let typeString = request.queryParameters["type"] ?? "steps"
        let daysString = request.queryParameters["days"] ?? "7"
        let startString = request.queryParameters["start"]
        let endString = request.queryParameters["end"]
        
        guard let type = HealthDataType(rawValue: typeString) else {
            sendResponse(
                connection: connection,
                statusCode: 400,
                body: ["error": "Invalid type: \(typeString)"]
            )
            return
        }
        
        // Calculate date range
        let endDate = parseDate(endString) ?? Date()
        let startDate: Date
        
        if let start = parseDate(startString) {
            startDate = start
        } else if let days = Int(daysString) {
            startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        } else {
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        }
        
        await auditService.log(
            action: .dataFetched,
            clientAddress: clientAddress,
            dataType: type.rawValue,
            details: "Fetched \(type.displayName) from \(startDate) to \(endDate)"
        )
        
        do {
            let records = try await healthService.fetchData(
                type: type,
                startDate: startDate,
                endDate: endDate
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let recordsData = try encoder.encode(records)
            let recordsJSON = try JSONSerialization.jsonObject(with: recordsData)
            
            sendResponse(
                connection: connection,
                statusCode: 200,
                body: [
                    "type": type.rawValue,
                    "startDate": ISO8601DateFormatter().string(from: startDate),
                    "endDate": ISO8601DateFormatter().string(from: endDate),
                    "count": records.count,
                    "records": recordsJSON
                ]
            )
        } catch {
            sendResponse(
                connection: connection,
                statusCode: 500,
                body: ["error": error.localizedDescription]
            )
        }
    }
    
    /// Handle pairing request (exchange token for permanent access)
    private func handlePair(request: HTTPRequest, connection: NWConnection, clientAddress: String) async {
        await auditService.log(
            action: .devicePaired,
            clientAddress: clientAddress,
            details: "Device paired successfully"
        )
        
        // Return the permanent access token
        sendResponse(
            connection: connection,
            statusCode: 200,
            body: [
                "accessToken": securityService.permanentToken ?? "",
                "fingerprint": securityService.certificateFingerprint
            ]
        )
    }
    
    // MARK: - Response Helpers
    
    /// Send an HTTP response
    private func sendResponse(
        connection: NWConnection,
        statusCode: Int,
        body: [String: Any]
    ) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            let statusText = httpStatusText(for: statusCode)
            
            var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            response += "Content-Type: application/json\r\n"
            response += "Content-Length: \(jsonData.count)\r\n"
            response += "Connection: close\r\n"
            response += "\r\n"
            
            var responseData = response.data(using: .utf8)!
            responseData.append(jsonData)
            
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }
    
    /// Get HTTP status text
    private func httpStatusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
    
    /// Parse ISO8601 date string
    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
    
    // MARK: - Network Info
    
    /// Update local network addresses
    private func updateLocalAddresses() async {
        var addresses: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var current = firstAddr
        while true {
            let interface = current.pointee
            let family = interface.ifa_addr.pointee.sa_family
            
            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                
                // Only include WiFi and Ethernet interfaces
                if name.hasPrefix("en") || name.hasPrefix("bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    let result = getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    
                    if result == 0 {
                        let address = String(cString: hostname)
                        if SecurityService.isPrivateNetwork(address) {
                            addresses.append(address)
                        }
                    }
                }
            }
            
            guard let next = current.pointee.ifa_next else { break }
            current = next
        }
        
        await MainActor.run {
            localAddresses = addresses
        }
    }
}

// Required for getifaddrs
import Darwin
