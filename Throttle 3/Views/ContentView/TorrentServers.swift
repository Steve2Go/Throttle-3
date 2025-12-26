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
    @AppStorage("selectedServerUUID") private var selectedServerUUID: String = ""
    @State private var navigationTrigger: UUID?
    @State private var editingServer: Servers?
    @EnvironmentObject var store: Store
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    var body: some View {
            HStack(spacing: 8) {
                ForEach(servers) { server in
                    HStack(spacing: 4) {
                        NavigationLink {
                            TorrentRows(isSidebarVisible: columnVisibility == .all, columnVisibility: $columnVisibility)
                                .navigationTitle(server.name)
                                .onAppear {
                                    selectedServerUUID = server.id.uuidString
                                }
                        } label: {
                            Image(systemName: server.id.uuidString == selectedServerUUID ? "externaldrive.badge.checkmark" : "externaldrive")
                                .padding(.leading, 6)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(server.id.uuidString == selectedServerUUID ?.green : .primary,.primary)
                        
                            Text(server.name)
                                .padding(.leading, 0)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button {
                            editingServer = server
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .sheet(item: $editingServer) { server in
                ServerView(server: server)
            }
            .onAppear {
                // Auto-navigate to selected server if it exists
                if !selectedServerUUID.isEmpty && !store.didLoad,
                   let uuid = UUID(uuidString: selectedServerUUID),
                   servers.contains(where: { $0.id == uuid }) {
                    store.didLoad = true
                    navigationTrigger = uuid
                }
            }
            .background(
                Group {
                    if let uuid = navigationTrigger,
                       let server = servers.first(where: { $0.id == uuid }) {
                        NavigationLink(
                            destination: TorrentRows(isSidebarVisible: columnVisibility == .all, columnVisibility: $columnVisibility),
                            tag: uuid,
                            selection: $navigationTrigger,
                            label: { EmptyView() }
                        )
                    }
                }
                .opacity(0)
            )
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(servers[index])
            }
        }
    }
}
