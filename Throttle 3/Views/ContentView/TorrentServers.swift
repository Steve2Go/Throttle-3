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
    @AppStorage("onStartServer") private var onstartServer: String = ""
    @State private var editingServer: Servers?
    @EnvironmentObject var store: Store
    //@Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var hasAppeared = false
    
    var body: some View {
            VStack(spacing: 10) {
                ForEach(servers) { server in
                    HStack(spacing: 4) {
                        Button {
                            // Handle server switch - just update ID, tunnel is lazy
                            #if os(iOS)
                            // On iOS, always navigate even if already selected
                            if selectedServerUUID != server.id.uuidString {
                                print("🔄 Switching server from \(selectedServerUUID) to \(server.id.uuidString)")
                                selectedServerUUID = server.id.uuidString
                                store.currentServerID = server.id
                            }
                            store.navigationTrigger = server.id
                            #else
                            // On macOS, only navigate if switching to a different server
                            if selectedServerUUID != server.id.uuidString {
                                print("🔄 Switching server from \(selectedServerUUID) to \(server.id.uuidString)")
                                selectedServerUUID = server.id.uuidString
                                store.currentServerID = server.id
                                store.navigationTrigger = server.id
                            }
                            #endif
                        } label: {
                            HStack(spacing: 4) {
                                Image(server.id.uuidString == selectedServerUUID ? "custom.server.rack.circle.fill" : "custom.server.rack.circle")
                                    .padding(.leading, 6)
                                     .symbolRenderingMode(.monochrome)
                                    // .foregroundStyle(server.id.uuidString == selectedServerUUID ? .secondary : .primary,.primary)
                            
                                Text(server.name)
#if os(IOS)
                                    .font(.title3)
                                #endif
                                    .padding(.leading, 0)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
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
                    #if os(iOS)
                    .padding(.vertical, 5)
                    #endif
                    
                }
            }
            .padding()
            .sheet(item: $editingServer) { server in
                ServerView(server: server)
            }
            .onAppear {
                // Auto-navigate to selected server if it exists
                // Reset didLoad for new windows on macOS
                #if os(macOS)
                if hasAppeared {
                    store.didLoad = false
                }
                hasAppeared = true
                #endif
                
                
                //auto connect
                var uuid: UUID?
                if !store.didLoad {
                    if !onstartServer.isEmpty {
                        uuid = UUID(uuidString: onstartServer)
                    } else if !selectedServerUUID.isEmpty {
                        uuid = UUID(uuidString: selectedServerUUID)
                    }
                    if uuid != nil,
                       servers.contains(where: { $0.id == uuid }) {
                        store.didLoad = true
                        store.navigationTrigger = uuid
                        store.currentServerID = uuid
                    }
                }
                
               
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                // When a new window becomes key, reset and re-navigate
                store.didLoad = false
                if !selectedServerUUID.isEmpty,
                   let uuid = UUID(uuidString: selectedServerUUID),
                   servers.contains(where: { $0.id == uuid }) {
                    store.didLoad = true
                    store.navigationTrigger = uuid
                    store.currentServerID = uuid
                }
            }
            #endif
            .background(
                Group {
                    if let uuid = store.navigationTrigger,
                       let server = servers.first(where: { $0.id == uuid }) {
                        NavigationLink(
                            destination: TorrentRows()
                                .navigationTitle(server.name),
                            tag: uuid,
                            selection: $store.navigationTrigger,
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
