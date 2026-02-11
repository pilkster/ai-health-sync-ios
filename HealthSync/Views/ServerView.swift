//
//  ServerView.swift
//  HealthSync
//
//  Server status and control view.
//  Shows server state, connected clients, network info, and cloud sync.
//

import SwiftUI

/// Server status and control view
struct ServerView: View {
    @Environment(ServiceContainer.self) private var services
    @State private var isAuthorizing = false
    @State private var authorizationError: String?
    @State private var showingAuthError = false
    
    var body: some View {
        NavigationStack {
            List {
                // Cloud Sync Section
                Section {
                    cloudSyncStatusRow
                    cloudSyncButton
                } header: {
                    Text("Cloud Sync")
                } footer: {
                    if let cloudSync = services.cloudSyncService,
                       let lastSync = cloudSync.lastSyncTimestamp {
                        Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                
                // Server Status Section
                Section {
                    serverStatusRow
                    
                    if let server = services.networkServer {
                        if server.state.isRunning {
                            connectedClientsRow(server)
                            networkAddressesSection(server)
                        }
                    }
                } header: {
                    Text("Server Status")
                }
                
                // HealthKit Status Section
                Section {
                    healthKitStatusRow
                } header: {
                    Text("HealthKit")
                }
                
                // Server Control Section
                Section {
                    serverControlButton
                } header: {
                    Text("Controls")
                }
                
                // Quick Stats Section
                if let audit = services.auditService {
                    Section {
                        statsSection(audit)
                    } header: {
                        Text("Quick Stats")
                    }
                }
            }
            .navigationTitle("Health Sync")
            .alert("HealthKit Authorization", isPresented: $showingAuthError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authorizationError ?? "Failed to authorize HealthKit access")
            }
        }
    }
    
    // MARK: - Server Status
    
    private var serverStatusRow: some View {
        HStack {
            Image(systemName: serverStatusIcon)
                .foregroundColor(serverStatusColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Server")
                    .font(.headline)
                Text(services.networkServer?.state.displayText ?? "Not initialized")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if case .running = services.networkServer?.state {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var serverStatusIcon: String {
        guard let server = services.networkServer else { return "server.rack" }
        
        switch server.state {
        case .stopped: return "stop.circle"
        case .starting: return "arrow.clockwise.circle"
        case .running: return "play.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private var serverStatusColor: Color {
        guard let server = services.networkServer else { return .gray }
        
        switch server.state {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
    
    // MARK: - Connected Clients
    
    private func connectedClientsRow(_ server: NetworkServer) -> some View {
        HStack {
            Image(systemName: "laptopcomputer")
                .foregroundColor(.blue)
            
            Text("Connected Clients")
            
            Spacer()
            
            Text("\(server.connectedClients)")
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Network Addresses
    
    @ViewBuilder
    private func networkAddressesSection(_ server: NetworkServer) -> some View {
        if !server.localAddresses.isEmpty {
            ForEach(server.localAddresses, id: \.self) { address in
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.blue)
                    
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = "\(address):8443"
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    // MARK: - HealthKit Status
    
    private var healthKitStatusRow: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("HealthKit")
                    .font(.headline)
                
                if let health = services.healthService {
                    Text(health.isAvailable ? "Available" : "Not Available")
                        .font(.caption)
                        .foregroundColor(health.isAvailable ? .green : .red)
                } else {
                    Text("Initializing...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if isAuthorizing {
                ProgressView()
            } else {
                Button("Authorize") {
                    Task {
                        await authorizeHealthKit()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(services.healthService == nil)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Server Control
    
    private var serverControlButton: some View {
        Button {
            Task {
                await toggleServer()
            }
        } label: {
            HStack {
                Image(systemName: services.networkServer?.state.isRunning == true ? "stop.fill" : "play.fill")
                Text(services.networkServer?.state.isRunning == true ? "Stop Server" : "Start Server")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(services.networkServer?.state.isRunning == true ? .red : .green)
        .disabled(!services.isInitialized)
    }
    
    // MARK: - Stats Section
    
    private func statsSection(_ audit: AuditService) -> some View {
        Group {
            HStack {
                Text("Recent Requests")
                Spacer()
                Text("\(audit.recentLogs.count)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Security Events")
                Spacer()
                let securityCount = audit.recentLogs.filter { 
                    $0.auditAction?.isSecurityRelated == true 
                }.count
                Text("\(securityCount)")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Cloud Sync
    
    private var cloudSyncStatusRow: some View {
        HStack {
            Image(systemName: cloudSyncStatusIcon)
                .foregroundColor(cloudSyncStatusColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloud Sync")
                    .font(.headline)
                Text(services.cloudSyncService?.status.displayText ?? "Not configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if case .syncing = services.cloudSyncService?.status {
                ProgressView()
            } else if case .success = services.cloudSyncService?.status {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var cloudSyncStatusIcon: String {
        guard let cloudSync = services.cloudSyncService else { return "cloud" }
        
        switch cloudSync.status {
        case .idle: return "cloud"
        case .syncing: return "arrow.triangle.2.circlepath.circle"
        case .success: return "cloud.fill"
        case .error: return "exclamationmark.icloud.fill"
        }
    }
    
    private var cloudSyncStatusColor: Color {
        guard let cloudSync = services.cloudSyncService else { return .gray }
        
        switch cloudSync.status {
        case .idle: return .gray
        case .syncing: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
    
    private var cloudSyncButton: some View {
        Button {
            Task {
                await services.cloudSyncService?.sync()
            }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                Text("Sync to Cloud")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(services.cloudSyncService == nil || 
                  services.cloudSyncService?.status == .syncing)
    }
    
    // MARK: - Actions
    
    private func authorizeHealthKit() async {
        isAuthorizing = true
        defer { isAuthorizing = false }
        
        guard let health = services.healthService else { return }
        
        do {
            _ = try await health.requestAuthorization()
        } catch {
            authorizationError = error.localizedDescription
            showingAuthError = true
        }
    }
    
    private func toggleServer() async {
        guard let server = services.networkServer else { return }
        
        if server.state.isRunning {
            await server.stop()
            await services.auditService?.log(action: .serverStopped)
        } else {
            await server.start()
            await services.auditService?.log(action: .serverStarted)
        }
    }
}

#Preview {
    ServerView()
        .environment(ServiceContainer())
}
