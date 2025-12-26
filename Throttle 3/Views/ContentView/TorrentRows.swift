//
//  TorrentRows.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData

struct TorrentRows: View {
    let isSidebarVisible: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var store: Store
    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @State private var showServerList = false
    @Query private var servers: [Servers]
    
    // Get the current server based on the store's currentServerID
    private var currentServer: Servers? {
        guard let currentServerID = store.currentServerID else { return nil }
        return servers.first(where: { $0.id == currentServerID })
    }
    
    // Dummy data for testing
    let dummyTorrents = [
        DummyTorrent(name: "Ubuntu 24.04 LTS", icon: "arrow.down.circle"),
        DummyTorrent(name: "Big Buck Bunny", icon: "arrow.down.circle"),
        DummyTorrent(name: "Debian 12 ISO", icon: "arrow.down.circle")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(dummyTorrents) { torrent in
                Button {
                    print("Selected torrent: \(torrent.name)")
                    // TODO: Navigate to torrent detail
                }
                    label:{
                        Image(systemName: torrent.icon)
                            .padding(.leading, 6)
                            .foregroundStyle(.primary)
                    
                        Text(torrent.name)
                            .padding(.leading, 0)
                            .foregroundColor(.primary)
                    
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
               
                if tailscaleManager.isConnecting {
                    Button(action: {}) {
                        Image(systemName: "circle.grid.3x3")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                    }
                } else if connectionManager.isConnecting {
                    Button(action: {}) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                    }
                } else {
                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                
                
                Button(action: {}) {
                    Image(systemName: "internaldrive")
                }
            }
            #if os(iOS)
            ToolbarItem {
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "externaldrive.badge.person.crop")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        // Settings action
                    }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    Button(action: {
                        // Create action
                    }) {
                        Label("Create", systemImage: "document.badge.plus")
                    }
                    
                    Button(action: {
                        // Selection action
                    }) {
                        Label("Selection", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            
        }
            #else
            if !isSidebarVisible {
                ToolbarItem {
                    Button(action: {
                        showServerList = true
                    }) {
                        Image(systemName: "externaldrive.badge.person.crop")
                    }
                }
                
                //TODO - Make a filters & servers dropdown
                
            }
            #endif
            
            
            
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showServerList) {
            NavigationStack {
                ServerList(columnVisibility: $columnVisibility)
                    .navigationTitle("Servers")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showServerList = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            if let server = currentServer {
                if (tailscaleManager.isConnected || !server.useTailscale) && server.tunnelWebOverSSH {
                    print("Ready to connect.")
                    Task {
                        connectionManager.disconnect()
                        await connectionManager.connect(server: server)
                        //start torrent fetching here
                    }
                }
            }
        }
        .onChange(of: tailscaleManager.isConnected) { _, isConnected in
            if isConnected, let server = currentServer, server.tunnelWebOverSSH {
                print("Proceeding to connect tunnel.")
                Task {
                    await connectionManager.connect(server: server)
                    //start torrent fetching here
                }
            }
        }
    }
}

// Dummy torrent model for testing
struct DummyTorrent: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
}
