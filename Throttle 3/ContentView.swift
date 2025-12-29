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
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true

    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showTailscaleSheet = false
    @State private var showAddServer = false
    @State private var checkServers = 0

    var body: some View {

        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                    ServerList(columnVisibility: $columnVisibility)
                    Text("Filters")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    Spacer()
                }
                #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #else
                    //Ios only Settings nav
                    .toolbar {
                        
                        Button(action: {
                            showTailscaleSheet = true
                        }) {
                            Image(systemName: tailscaleManager.isConnecting ? "circle.grid.3x3" : "circle.grid.3x3.fill")
                                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)), isActive: tailscaleManager.isConnecting)
                        }
                        
                        Button(
                            action: {
                                showAddServer = true
                            },
                            label: {
                                Image(systemName: "externaldrive.badge.plus")
                            })
                       
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
        }.id(checkServers) // Force view refresh when checkServers changes
        .onAppear {
            columnVisibility = sidebarVisible ? .all : .detailOnly
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
        .onChange(of: columnVisibility) { _, newValue in
            sidebarVisible = (newValue == .all)
        }
        .sheet(isPresented: $showTailscaleSheet) {
            TailscaleToggle()
                .presentationDetents([.height(150)])
        }
        .sheet(isPresented: $showAddServer) {
            ServerView()
            .onDisappear {
                // Force re-check servers in case more servers
                checkServers += 1
            }
        }
    }
}
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
