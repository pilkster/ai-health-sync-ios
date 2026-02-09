//
//  ServiceContainer.swift
//  HealthSync
//
//  Dependency injection container that manages all app services.
//  Provides centralized access to HealthKit, networking, and security services.
//

import Foundation
import SwiftData
import Observation

/// Central service container for dependency injection throughout the app.
/// Manages initialization and lifecycle of all core services.
@Observable
@MainActor
final class ServiceContainer: Sendable {
    /// HealthKit data access service
    private(set) var healthService: HealthKitService?
    
    /// TLS server for network connections
    private(set) var networkServer: NetworkServer?
    
    /// Security service for certificates and tokens
    private(set) var securityService: SecurityService?
    
    /// Audit logging service
    private(set) var auditService: AuditService?
    
    /// Whether services have been initialized
    private(set) var isInitialized = false
    
    /// Initialize all services with the model container
    /// - Parameter modelContainer: SwiftData container for persistence
    func initialize(modelContainer: ModelContainer) async {
        guard !isInitialized else { return }
        
        // Initialize security service first (generates certs if needed)
        let security = SecurityService()
        await security.initializeIfNeeded()
        self.securityService = security
        
        // Initialize audit service with SwiftData
        let audit = AuditService(modelContainer: modelContainer)
        self.auditService = audit
        
        // Initialize HealthKit service
        let health = HealthKitService()
        self.healthService = health
        
        // Initialize network server with dependencies
        let server = NetworkServer(
            securityService: security,
            healthService: health,
            auditService: audit
        )
        self.networkServer = server
        
        isInitialized = true
    }
}
