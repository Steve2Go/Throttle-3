//
//  Throttle_3App.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData
import KeychainAccess

@main
struct Throttle_3App: App {
    
    //init Sync Settings & local settings
    @AppStorage("syncKeychain") var syncKeychain = true
    @AppStorage("syncServers") var syncServers = true
    @AppStorage("syncLocalServers") var syncLocalServers = true
    @AppStorage("syncSettings") var syncSettings = true
    @AppStorage("instance") var instance: String = UUID().uuidString
    @AppStorage("TailscaleAuth") var TailScaleReady: String?
    @AppStorage("ServerToStart") var ServerToStart: String?
    
    func startKeychain() -> Keychain {
        Keychain(service: "com.srgim.throttle3")
            .synchronizable(syncKeychain)
    }
    
    //Init Settings
    
    
    
    func startSettings() {
        // Get swiftdata settings
    }
    
    //Init Servers
    var sharedModelContainer: ModelContainer {
        let schema = Schema([
            Item.self,
            Servers.self,
            Settings.self,
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: (syncServers || syncSettings) ? .automatic : .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("ModelContainer creation failed with error: \(error)")
            print("CloudKit enabled: \(syncServers || syncSettings)")
            print("Check: 1) iCloud container is selected in Xcode Signing & Capabilities")
            print("       2) iCloud is enabled for your Apple ID in System Settings")
            print("       3) You're signed into iCloud in Xcode")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
