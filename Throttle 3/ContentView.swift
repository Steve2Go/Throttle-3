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

    var body: some View {

        NavigationSplitView(columnVisibility: $columnVisibility) {
            if servers.count == 0 {
                #if os(macOS)
                    EmptyView()
                #else
                    FirstRunView()
                #endif
            } else {
                // #if os(iOS)
                //                 if tailscaleManager.isConnecting {
                //                     ConnectingView(icon: "square.grid.3x3.topleft.filled", service: " to Tailscale")
                //                         .frame(maxWidth: .infinity, maxHeight: 30)
                //                         .background(Color(.systemBackground))
                //                         .offset(y: -50)
                //                 }
                // #endif
                VStack(alignment: .leading, spacing: 0) {

                    Text("Servers")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    ServerList(columnVisibility: $columnVisibility)
                    Text("Filters")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    Text("Tailscale")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    Spacer()
                }
                #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #else
                    //Ios only Settings nav
                    .toolbar {
                        ToolbarItem {
                            Button(
                                action: {
                                    //edit Servers
                                },
                                label: {
                                    Image(systemName: "externaldrive.badge.plus")
                                })

                            Button(
                                action: {
                                    //edit Servers
                                },
                                label: {
                                    Image(systemName: "ellipsis")
                                })
                        }
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
            columnVisibility = sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, newValue in
            sidebarVisible = (newValue == .all)
        }
    }
}
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
