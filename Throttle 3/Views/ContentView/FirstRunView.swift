//
//  ConnectingView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData

struct FirstRunView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var servers: [Servers]
    
    @State private var showAddServer = false
    @State private var checkServers = 0
    
    var body: some View {
        ContentUnavailableView{
            Label("Welcome.\nAdd a server to get started", systemImage: "figure.wave")
        }
        BasicSettings()
        //TailscaleToggle()
        Button("Server Information"){
            // Force re-check servers in case CloudKit synced
            checkServers += 1
            
            // Only show sheet if still no servers
            if servers.isEmpty {
                showAddServer = true
            }
        }
        .padding(.top)
        .buttonStyle(.bordered)
        .sheet(isPresented: $showAddServer) {
            ServerView()
        }
        .id(checkServers) // Force view refresh when checkServers changes
        Spacer()
    }
    
}
// tailscale icon square.grid.3x3.topleft.filled
// ssh icon externaldrive.connected.to.line.below
// transmission externaldrive.badge.icloud
