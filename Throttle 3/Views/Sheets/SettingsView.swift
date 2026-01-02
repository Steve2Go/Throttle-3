//
//  SettingsView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 27/12/2025.
//

//
//  ServerView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @Query private var servers: [Servers]
    @Environment(\.horizontalSizeClass) var sizeClass
    @AppStorage("refreshRate") var refreshRate = "30"
    @AppStorage("syncKeychain") var syncKeychain = true
    @AppStorage("syncServers") var syncServers = true
    @AppStorage("syncLocalServers") var syncLocalServers = true
    @AppStorage("onStartServer") var onstartServer = ""
    @AppStorage("chooseFiles") var chooseFiles = false
    @AppStorage("showThumbs") var showThumbs = true
    
    
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Startup Server", selection: $onstartServer) {
                        Text("Last Used").tag(String?.none)
                        ForEach(servers) { server in
                            Text(server.name).tag(String?.some(server.id.uuidString))
                        }
                    }
                    Toggle("Choose Files when Adding", isOn: $chooseFiles)
                    Toggle("Torrent Thumbnails", isOn: $showThumbs)
                    HStack {
                        #if os(iOS)
                        Text("Refresh Rate:")
                        Spacer()
                        #endif
                        TextField("Refresh Seconds", text: $refreshRate)
                    }
#if os(iOS)
                        .autocapitalization(.none)
                    
                        .keyboardType(.numberPad)
#endif
                }
                
                Section("Sync via iCloud") {
                    Toggle("Sync Servers", isOn: $syncServers)
#if os(macOS)
                    Toggle("Sync Local Server", isOn: $syncLocalServers)
#endif
                    Toggle("Sync Authentication", isOn: $syncKeychain)
                }
#if os(iOS)
                Section("Tailscale") {
                    Button("Clear Tailscale Auth") {
                        let tailscaleManager = TailscaleManager.shared
                        Task {
                            await tailscaleManager.clear()
                        }
                    }

                }
                #endif
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
#if os(macOS)
            .padding()
#endif
            
        }
    }
}
