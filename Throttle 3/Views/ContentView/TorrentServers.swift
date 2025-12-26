//
//  TorrentServers.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//
import SwiftUI
import SwiftData

struct ServerList: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var servers: [Servers]
    
    var body: some View {
            HStack(spacing: 8) {
                ForEach(servers) { server in
                    Button {
                        // Handle server selection
                    }
                        label:{
                            Image(systemName: "externaldrive.badge.icloud")
                                .padding(.leading, 6)
                                .foregroundStyle(.primary)
                        
                            Text(server.name)
                                .padding(.leading, 0)
                                .foregroundColor(.primary)
                        
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(servers[index])
            }
        }
    }
}
