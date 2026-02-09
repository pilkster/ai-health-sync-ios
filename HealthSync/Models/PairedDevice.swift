//
//  PairedDevice.swift
//  HealthSync
//
//  SwiftData model for paired devices.
//  Tracks devices that have successfully authenticated.
//

import Foundation
import SwiftData

/// A device that has been paired with this Health Sync server
@Model
final class PairedDevice {
    /// Unique identifier
    var id: UUID
    
    /// Device name (from pairing request)
    var name: String
    
    /// Device type (e.g., "macOS CLI", "Custom Client")
    var deviceType: String
    
    /// When the device was paired
    var pairedAt: Date
    
    /// Last time the device connected
    var lastSeen: Date
    
    /// Number of requests made by this device
    var requestCount: Int
    
    /// Whether the device is currently active/allowed
    var isActive: Bool
    
    /// Initialize a new paired device
    /// - Parameters:
    ///   - name: Device name
    ///   - deviceType: Type of device
    init(name: String, deviceType: String) {
        self.id = UUID()
        self.name = name
        self.deviceType = deviceType
        self.pairedAt = Date()
        self.lastSeen = Date()
        self.requestCount = 0
        self.isActive = true
    }
    
    /// Update last seen timestamp
    func updateLastSeen() {
        lastSeen = Date()
        requestCount += 1
    }
    
    /// Formatted paired date
    var formattedPairedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: pairedAt)
    }
    
    /// Formatted last seen date
    var formattedLastSeen: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
}
