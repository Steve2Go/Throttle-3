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
                                Image(systemName: "externaldrive.badge.plus")
                            })
                            .buttonStyle(.plain)

                           Button(
                            action: {
                                store.showAddServer = true
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
    }
}
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
