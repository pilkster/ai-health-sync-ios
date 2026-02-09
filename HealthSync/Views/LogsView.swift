//
//  LogsView.swift
//  HealthSync
//
//  Audit log viewer with filtering and search.
//  Displays all data access events for security review.
//

import SwiftUI
import SwiftData

/// Audit log viewer
struct LogsView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AuditLogEntry.timestamp, order: .reverse) private var allLogs: [AuditLogEntry]
    
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""
    
    enum LogFilter: String, CaseIterable {
        case all = "All"
        case security = "Security"
        case dataAccess = "Data Access"
        case server = "Server"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .security: return "shield"
            case .dataAccess: return "arrow.down.doc"
            case .server: return "server.rack"
            }
        }
    }
    
    var filteredLogs: [AuditLogEntry] {
        var logs = allLogs
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .security:
            logs = logs.filter { entry in
                entry.auditAction?.isSecurityRelated == true
            }
        case .dataAccess:
            logs = logs.filter { entry in
                entry.action == AuditAction.dataFetched.rawValue ||
                entry.action == AuditAction.typesListed.rawValue
            }
        case .server:
            logs = logs.filter { entry in
                entry.action == AuditAction.serverStarted.rawValue ||
                entry.action == AuditAction.serverStopped.rawValue
            }
        }
        
        // Apply search
        if !searchText.isEmpty {
            logs = logs.filter { entry in
                entry.action.localizedCaseInsensitiveContains(searchText) ||
                entry.details?.localizedCaseInsensitiveContains(searchText) == true ||
                entry.clientAddress?.localizedCaseInsensitiveContains(searchText) == true ||
                entry.dataType?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        return logs
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter picker
                filterPicker
                
                // Logs list
                if filteredLogs.isEmpty {
                    emptyState
                } else {
                    logsList
                }
            }
            .navigationTitle("Access Logs")
            .searchable(text: $searchText, prompt: "Search logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            clearOldLogs()
                        } label: {
                            Label("Clear Old Logs", systemImage: "trash")
                        }
                        
                        Button {
                            exportLogs()
                        } label: {
                            Label("Export Logs", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    // MARK: - Filter Picker
    
    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LogFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.icon)
                            Text(filter.rawValue)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? Color.blue : Color(.secondarySystemBackground))
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Logs List
    
    private var logsList: some View {
        List {
            ForEach(filteredLogs) { entry in
                LogEntryRow(entry: entry)
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Logs Found")
                .font(.headline)
            
            Text(searchText.isEmpty ? "No activity has been logged yet." : "No logs match your search.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func clearOldLogs() {
        Task {
            await services.auditService?.clearOldLogs(olderThan: 30)
        }
    }
    
    private func exportLogs() {
        // TODO: Implement export functionality
    }
}

/// Individual log entry row
struct LogEntryRow: View {
    let entry: AuditLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: entry.auditAction?.icon ?? "doc")
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 32)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.auditAction?.displayName ?? entry.action)
                    .font(.headline)
                
                if let details = entry.details {
                    Text(details)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    if let address = entry.clientAddress {
                        Label(address, systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let dataType = entry.dataType {
                        Label(dataType, systemImage: "heart.text.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(entry.relativeTimestamp)
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var iconColor: Color {
        guard let action = entry.auditAction else { return .gray }
        
        switch action {
        case .authenticationFailed:
            return .red
        case .authenticationSuccess, .devicePaired:
            return .green
        case .serverStarted, .serverStopped:
            return .blue
        case .dataFetched:
            return .orange
        default:
            return .gray
        }
    }
}

#Preview {
    LogsView()
        .environment(ServiceContainer())
}
