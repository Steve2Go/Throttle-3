//
//  ContentView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var servers: [Servers]
    
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
                        Button(action: {
                            //edit Servers
                        }, label: {
                            Image(systemName: "externaldrive.badge.plus")
                        })
                        
                        Button(action: {
                            //edit Servers
                        }, label: {
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
                Text("Select a server")     
            }
        }
    }
}
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
