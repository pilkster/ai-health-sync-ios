//
//  AuditLogEntry.swift
//  HealthSync
//
//  SwiftData model for audit log entries.
//  Records all data access events for security and compliance.
//

import Foundation
import SwiftData

/// Audit log entry stored in SwiftData
@Model
final class AuditLogEntry {
    /// Unique identifier
    var id: UUID
    
    /// The action that was performed (raw value of AuditAction)
    var action: String
    
    /// Client's network address (IP or hostname)
    var clientAddress: String?
    
    /// Type of health data accessed (if applicable)
    var dataType: String?
    
    /// Additional details about the action
    var details: String?
    
    /// When the action occurred
    var timestamp: Date
    
    /// Initialize a new audit log entry
    /// - Parameters:
    ///   - action: The action that was performed
    ///   - clientAddress: Client's network address
    ///   - dataType: Type of health data accessed
    ///   - details: Additional details
    ///   - timestamp: When the action occurred
    init(
        action: String,
        clientAddress: String? = nil,
        dataType: String? = nil,
        details: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.action = action
        self.clientAddress = clientAddress
        self.dataType = dataType
        self.details = details
        self.timestamp = timestamp
    }
    
    /// Get the audit action enum value
    var auditAction: AuditAction? {
        AuditAction(rawValue: action)
    }
    
    /// Formatted timestamp string
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    /// Relative timestamp string (e.g., "2 minutes ago")
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
