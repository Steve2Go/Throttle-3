//
//  ContentView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var servers: [Servers]
    @AppStorage("selectedServerUUID") private var selectedServerUUID: String = ""
    @AppStorage("currentFilter") private var currentFilter: String = "dateAdded"
    @AppStorage("currentStatusFilter") private var currentStatusFilter: String = "all"
    
    @EnvironmentObject var store: Store

    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    //@State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showTailscaleSheet = false

    var body: some View {

        NavigationSplitView {
            if servers.count == 0 {
                #if os(macOS)
                    EmptyView()
                #else
                    FirstRunView()
                #endif
            } else {
                VStack(alignment: .leading, spacing: 0) {

                    Text("Servers")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    ServerList()
                    Text("Order")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    
                    VStack(spacing: 4) {
                        Button(action: {
                            currentFilter = "dateAdded"
                            #if os(iOS)
                            store.navigationTrigger = store.currentServerID
                            #endif
                        }) {
                            HStack {
                                Image(systemName: currentFilter == "dateAdded" ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                Text("Date Added")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                           // .background(currentFilter == "dateAdded" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentFilter = "name"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentFilter == "name" ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                Text("Name")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            //.background(currentFilter == "name" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentFilter = "size"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentFilter == "size" ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                Text("Size")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            //.background(currentFilter == "size" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentFilter = "progress"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentFilter == "progress" ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                Text("Progress")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            //.background(currentFilter == "progress" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    
                    Text("Filters")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                        .padding(.top, 12)
                    
                    VStack(spacing: 4) {
                        Button(action: {
                            currentStatusFilter = "all"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentStatusFilter == "all" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                Text("All")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            //.background(currentStatusFilter == "all" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentStatusFilter = "downloading"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentStatusFilter == "downloading" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                Text("Downloading")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            //.background(currentStatusFilter == "downloading" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentStatusFilter = "seeding"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentStatusFilter == "seeding" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                Text("Seeding")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                           // .background(currentStatusFilter == "seeding" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentStatusFilter = "paused"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentStatusFilter == "paused" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                Text("Paused")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                          //  .background(currentStatusFilter == "paused" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            currentStatusFilter = "completed"
#if os(iOS)
store.navigationTrigger = store.currentServerID
#endif
                        }) {
                            HStack {
                                Image(systemName: currentStatusFilter == "completed" ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                Text("Completed")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                           // .background(currentStatusFilter == "completed" ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    
                    Spacer()
                }
                #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                   
                #else
                    //Ios only Settings nav
                    .toolbar {
                       
                            Button(action: {
                                store.showTailscaleSheet = true
                            }) {
                                Image("custom.circle.grid.3x3")
                                    .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)), isActive: tailscaleManager.isConnecting)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.primary, .secondary)
                            }
                        
                        
                        Button(
                            action: {
                                store.showAddServer = true
                            },
                            label: {
                                Image("custom.server.rack.badge.plus")
                            })
                            .buttonStyle(.plain)

                           Button(
                            action: {
                                store.showSettings = true
                            },
                            label: {
                                Image(systemName: "gearshape")
                            })
                            .buttonStyle(.plain)
                       
                    }
                #endif
            }

        } detail: {
            if servers.count == 0 {
                FirstRunView()
            } else {
                ContentUnavailableView {
                    Label("No Server Selected", systemImage: "externaldrive")
                } description: {
                    Text("Select a Server to start.")
                }
            }
        }
        .onAppear {
           
            #if os(macOS)
            // Ensure Tailscale monitoring is active when window appears
            tailscaleManager.ensureMonitoring()
            #endif
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Triggered when a window becomes key (active)
            tailscaleManager.ensureMonitoring()
        }
        #endif
        .sheet(isPresented: $store.showTailscaleSheet) {
            NavigationStack {
                TailscaleToggle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                store.showTailscaleSheet = false
                            }
                        }
                    }
                #if os(iOS)
                    .presentationDetents([.height(200)])
                #else
                    .frame(idealWidth: NSApp.keyWindow?.contentView?.bounds.width ?? 500, idealHeight: 100)
                #endif
            }
        }
        
        .sheet(isPresented: $store.showAddServer) {
            ServerView()
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
        }
    }
}
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
