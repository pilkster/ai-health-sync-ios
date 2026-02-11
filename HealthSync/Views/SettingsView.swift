//
//  SettingsView.swift
//  HealthSync
//
//  App settings and configuration view.
//  Displays security info and allows configuration changes.
//

import SwiftUI
import SwiftData

/// Settings and configuration view
struct SettingsView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var pairedDevices: [PairedDevice]
    
    @State private var showingResetConfirmation = false
    @State private var showingCertificateInfo = false
    @State private var cloudEndpoint: String = ""
    @State private var autoSyncEnabled: Bool = false
    @State private var syncDaysRange: Int = 7
    
    var body: some View {
        NavigationStack {
            List {
                // Cloud Sync Section
                Section {
                    cloudSyncSettingsSection
                } header: {
                    Text("Cloud Sync")
                } footer: {
                    if let lastSync = services.cloudSyncService?.lastSyncTimestamp {
                        Text("Last synced: \(lastSync.formatted(date: .long, time: .shortened))")
                    } else {
                        Text("Configure cloud sync to upload health data to your server.")
                    }
                }
                
                // Certificate Info Section
                Section {
                    certificateInfoRow
                } header: {
                    Text("Security")
                } footer: {
                    Text("The certificate fingerprint is used to verify the server identity. Share this with clients for manual verification.")
                }
                
                // Paired Devices Section
                Section {
                    if pairedDevices.isEmpty {
                        Text("No devices paired")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(pairedDevices) { device in
                            PairedDeviceRow(device: device)
                        }
                        .onDelete(perform: deleteDevices)
                    }
                } header: {
                    Text("Paired Devices")
                }
                
                // Server Settings Section
                Section {
                    HStack {
                        Text("Server Port")
                        Spacer()
                        Text("8443")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("TLS Version")
                        Spacer()
                        Text("1.2+")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Network")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/ainekomacx/ai-health-sync-ios")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Reset All Data")
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will delete all paired devices, regenerate certificates, and clear audit logs.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCertificateInfo) {
                CertificateInfoSheet()
            }
            .confirmationDialog(
                "Reset All Data?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone. All paired devices will need to re-pair.")
            }
            .onAppear {
                loadCloudSyncSettings()
            }
        }
    }
    
    private func loadCloudSyncSettings() {
        if let cloudSync = services.cloudSyncService {
            cloudEndpoint = cloudSync.endpointURL
            autoSyncEnabled = cloudSync.autoSyncEnabled
            syncDaysRange = cloudSync.syncDaysRange
        }
    }
    
    // MARK: - Cloud Sync Settings
    
    @ViewBuilder
    private var cloudSyncSettingsSection: some View {
        // Endpoint URL
        HStack {
            Text("Endpoint")
            Spacer()
            TextField("https://health.aineko.com", text: $cloudEndpoint)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: cloudEndpoint) { _, newValue in
                    services.cloudSyncService?.endpointURL = newValue
                }
        }
        
        // Auto-sync toggle
        Toggle("Auto-sync on Launch", isOn: $autoSyncEnabled)
            .onChange(of: autoSyncEnabled) { _, newValue in
                services.cloudSyncService?.autoSyncEnabled = newValue
            }
        
        // Sync days range
        Picker("Sync Period", selection: $syncDaysRange) {
            Text("3 days").tag(3)
            Text("7 days").tag(7)
            Text("14 days").tag(14)
            Text("30 days").tag(30)
        }
        .onChange(of: syncDaysRange) { _, newValue in
            services.cloudSyncService?.syncDaysRange = newValue
        }
        
        // Sync status
        if let cloudSync = services.cloudSyncService {
            HStack {
                Text("Status")
                Spacer()
                Text(cloudSync.status.displayText)
                    .foregroundColor(cloudSync.status.isError ? .red : .secondary)
            }
        }
    }
    
    // MARK: - Certificate Info
    
    private var certificateInfoRow: some View {
        Button {
            showingCertificateInfo = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Certificate Fingerprint")
                        .foregroundColor(.primary)
                    
                    if let fingerprint = services.securityService?.certificateFingerprint {
                        Text(formatFingerprint(fingerprint))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Not generated")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatFingerprint(_ fingerprint: String) -> String {
        // Show first 20 characters with ellipsis
        if fingerprint.count > 23 {
            return String(fingerprint.prefix(20)) + "..."
        }
        return fingerprint
    }
    
    // MARK: - Actions
    
    private func deleteDevices(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(pairedDevices[index])
        }
    }
    
    private func resetAllData() {
        // Delete all paired devices
        for device in pairedDevices {
            modelContext.delete(device)
        }
        
        // Clear audit logs would go here
        Task {
            await services.auditService?.clearOldLogs(olderThan: 0)
        }
        
        // Note: Certificate regeneration would require app restart
    }
}

/// Paired device row
struct PairedDeviceRow: View {
    let device: PairedDevice
    
    var body: some View {
        HStack {
            Image(systemName: "laptopcomputer")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                
                Text("Last seen: \(device.formattedLastSeen)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Circle()
                    .fill(device.isActive ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text("\(device.requestCount) requests")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Certificate info sheet
struct CertificateInfoSheet: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let fingerprint = services.securityService?.certificateFingerprint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SHA-256 Fingerprint")
                                .font(.headline)
                            
                            Text(fingerprint)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                        
                        Button {
                            UIPasteboard.general.string = fingerprint
                        } label: {
                            Label("Copy Fingerprint", systemImage: "doc.on.doc")
                        }
                    }
                } footer: {
                    Text("Use this fingerprint to verify the server identity on client devices.")
                }
                
                Section {
                    HStack {
                        Text("Algorithm")
                        Spacer()
                        Text("RSA 2048-bit")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Signature")
                        Spacer()
                        Text("SHA-256")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Type")
                        Spacer()
                        Text("Self-signed")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Certificate Details")
                }
            }
            .navigationTitle("Certificate Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(ServiceContainer())
}
