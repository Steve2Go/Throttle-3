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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(servers) { server in
                    Button(action: {
                        // Handle server selection
                    }) {
                        HStack {
                            Image(systemName: "externaldrive.badge.icloud")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.headline)
                            if !server.url.isEmpty {
                                Text(server.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(servers[index])
            }
        }
    }
}
