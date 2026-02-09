//
//  HealthSyncApp.swift
//  HealthSync
//
//  Main application entry point for the Health Sync iOS app.
//  Configures SwiftData, HealthKit permissions, and the server lifecycle.
//

import SwiftUI
import SwiftData

/// The main application entry point for Health Sync.
/// Manages the app lifecycle, data persistence, and shared services.
@main
struct HealthSyncApp: App {
    /// Shared service container for dependency injection
    @State private var services = ServiceContainer()
    
    /// SwiftData model container for audit logs
    let modelContainer: ModelContainer
    
    init() {
        // Configure SwiftData with audit log schema
        do {
            let schema = Schema([
                AuditLogEntry.self,
                PairedDevice.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services)
                .modelContainer(modelContainer)
                .task {
                    // Initialize services on app launch
                    await services.initialize(modelContainer: modelContainer)
                }
        }
    }
}
