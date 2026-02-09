//
//  AuditService.swift
//  HealthSync
//
//  Audit logging service for tracking all data access events.
//  Stores logs in SwiftData for persistence and review.
//

import Foundation
import SwiftData
import Observation

/// Types of audit actions that can be logged
enum AuditAction: String, Codable, Sendable {
    case serverStarted = "server_started"
    case serverStopped = "server_stopped"
    case authenticationFailed = "auth_failed"
    case authenticationSuccess = "auth_success"
    case devicePaired = "device_paired"
    case deviceUnpaired = "device_unpaired"
    case dataFetched = "data_fetched"
    case statusCheck = "status_check"
    case typesListed = "types_listed"
    
    /// Human-readable description
    var displayName: String {
        switch self {
        case .serverStarted: return "Server Started"
        case .serverStopped: return "Server Stopped"
        case .authenticationFailed: return "Authentication Failed"
        case .authenticationSuccess: return "Authentication Success"
        case .devicePaired: return "Device Paired"
        case .deviceUnpaired: return "Device Unpaired"
        case .dataFetched: return "Data Fetched"
        case .statusCheck: return "Status Check"
        case .typesListed: return "Types Listed"
        }
    }
    
    /// Icon for display
    var icon: String {
        switch self {
        case .serverStarted: return "play.circle.fill"
        case .serverStopped: return "stop.circle.fill"
        case .authenticationFailed: return "xmark.shield.fill"
        case .authenticationSuccess: return "checkmark.shield.fill"
        case .devicePaired: return "link.circle.fill"
        case .deviceUnpaired: return "link.badge.plus"
        case .dataFetched: return "arrow.down.doc.fill"
        case .statusCheck: return "heart.text.square.fill"
        case .typesListed: return "list.bullet.rectangle.fill"
        }
    }
    
    /// Whether this is a security-related action
    var isSecurityRelated: Bool {
        switch self {
        case .authenticationFailed, .authenticationSuccess, .devicePaired, .deviceUnpaired:
            return true
        default:
            return false
        }
    }
}

/// Service for recording and querying audit logs
@Observable
@MainActor
final class AuditService: @unchecked Sendable {
    /// SwiftData model container
    private let modelContainer: ModelContainer
    
    /// Recent logs cache for quick access
    private(set) var recentLogs: [AuditLogEntry] = []
    
    /// Maximum number of logs to keep in cache
    private let cacheLimit = 50
    
    /// Initialize with model container
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        Task {
            await loadRecentLogs()
        }
    }
    
    /// Log an audit event
    /// - Parameters:
    ///   - action: The type of action being logged
    ///   - clientAddress: The client's network address (if applicable)
    ///   - dataType: The type of health data accessed (if applicable)
    ///   - details: Additional details about the action
    @MainActor
    func log(
        action: AuditAction,
        clientAddress: String? = nil,
        dataType: String? = nil,
        details: String? = nil
    ) async {
        let entry = AuditLogEntry(
            action: action.rawValue,
            clientAddress: clientAddress,
            dataType: dataType,
            details: details,
            timestamp: Date()
        )
        
        // Insert into SwiftData
        let context = modelContainer.mainContext
        context.insert(entry)
        
        do {
            try context.save()
        } catch {
            print("Failed to save audit log: \(error)")
        }
        
        // Update cache
        recentLogs.insert(entry, at: 0)
        if recentLogs.count > cacheLimit {
            recentLogs = Array(recentLogs.prefix(cacheLimit))
        }
    }
    
    /// Load recent logs from storage
    private func loadRecentLogs() async {
        let context = modelContainer.mainContext
        
        let descriptor = FetchDescriptor<AuditLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let logs = try context.fetch(descriptor)
            await MainActor.run {
                self.recentLogs = Array(logs.prefix(cacheLimit))
            }
        } catch {
            print("Failed to load audit logs: \(error)")
        }
    }
    
    /// Get all logs within a date range
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of audit log entries
    func getLogs(from startDate: Date, to endDate: Date) async -> [AuditLogEntry] {
        let context = modelContainer.mainContext
        
        let predicate = #Predicate<AuditLogEntry> { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
        
        var descriptor = FetchDescriptor<AuditLogEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1000
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch logs: \(error)")
            return []
        }
    }
    
    /// Get logs for a specific action type
    /// - Parameter action: The action type to filter by
    /// - Returns: Array of matching audit log entries
    func getLogs(forAction action: AuditAction) async -> [AuditLogEntry] {
        let context = modelContainer.mainContext
        let actionString = action.rawValue
        
        let predicate = #Predicate<AuditLogEntry> { entry in
            entry.action == actionString
        }
        
        var descriptor = FetchDescriptor<AuditLogEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch logs: \(error)")
            return []
        }
    }
    
    /// Clear old logs (older than specified days)
    /// - Parameter days: Number of days to keep
    func clearOldLogs(olderThan days: Int) async {
        let context = modelContainer.mainContext
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let predicate = #Predicate<AuditLogEntry> { entry in
            entry.timestamp < cutoffDate
        }
        
        let descriptor = FetchDescriptor<AuditLogEntry>(predicate: predicate)
        
        do {
            let oldLogs = try context.fetch(descriptor)
            for log in oldLogs {
                context.delete(log)
            }
            try context.save()
        } catch {
            print("Failed to clear old logs: \(error)")
        }
    }
    
    /// Get security-related logs
    func getSecurityLogs() async -> [AuditLogEntry] {
        let context = modelContainer.mainContext
        let securityActions = [
            AuditAction.authenticationFailed.rawValue,
            AuditAction.authenticationSuccess.rawValue,
            AuditAction.devicePaired.rawValue,
            AuditAction.deviceUnpaired.rawValue
        ]
        
        // Using a simpler approach since complex predicates with contains can be tricky
        var descriptor = FetchDescriptor<AuditLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        
        do {
            let allLogs = try context.fetch(descriptor)
            return allLogs.filter { securityActions.contains($0.action) }
        } catch {
            print("Failed to fetch security logs: \(error)")
            return []
        }
    }
}
