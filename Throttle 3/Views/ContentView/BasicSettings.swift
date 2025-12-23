//
//  BasicSettings.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI

struct BasicSettings: View {
    @AppStorage("syncKeychain") var syncKeychain = true
    @AppStorage("syncServers") var syncServers = true
    @AppStorage("syncLocalServers") var syncLocalServers = true
    @AppStorage("syncSettings") var syncSettings = true
    
    var body: some View {
        List {
            Section("Sync Settings") {
                
                Toggle("Sync Servers", isOn: $syncServers)
                #if os(macOS)
                Toggle("Sync Local Servers", isOn: $syncLocalServers)
                #endif
                Toggle("Sync Authentication", isOn: $syncKeychain)
                Toggle("Sync Settings", isOn: $syncSettings)
            }
        }
        .scrollContentBackground(.hidden)
        //.navigationTitle("Settings")
    }
}
