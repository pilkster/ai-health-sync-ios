//
//  ContentView.swift
//  HealthSync
//
//  Main content view with tab navigation.
//  Provides access to server control, pairing, and logs.
//

import SwiftUI
import SwiftData

/// Main content view with tab navigation
struct ContentView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        TabView {
            ServerView()
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }
            
            PairingView()
                .tabItem {
                    Label("Pairing", systemImage: "qrcode")
                }
            
            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet.rectangle")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(ServiceContainer())
}
