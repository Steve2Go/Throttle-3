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
    @AppStorage("syncKeychain") var syncKeychain = false
    @AppStorage("syncServers") var syncServers = false
    @AppStorage("syncLocalServers") var syncLocalServers = false
    @AppStorage("syncSettings") var syncSettings = false
    @AppStorage("instance") var instance: String = UUID().uuidString
    @AppStorage("TailscaleEnabled") var tailscaleEnabled = false
    @AppStorage("ServerToStart") var ServerToStart: String?

    @ObservedObject private var TSmanager = TailscaleManager.shared
    
    @State private var hasCompletedInitialSync = false
    @State private var containerRefreshTrigger = 0
    
    private static var _sharedModelContainer: ModelContainer?
    private static let containerLock = NSLock()
    
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
        Self.containerLock.lock()
        defer { Self.containerLock.unlock() }
        
        // Force recreation if settings changed
        _ = containerRefreshTrigger
        
        if let existing = Self._sharedModelContainer, containerRefreshTrigger == 0 {
            return existing
        }
        
        // Clear existing container
        Self._sharedModelContainer = nil
        
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
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            Self._sharedModelContainer = container
            return container
        } catch {
            print("ModelContainer creation failed with error: \(error)")
            print("CloudKit enabled: \(syncServers || syncSettings)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func refreshModelContainer() {
        containerRefreshTrigger += 1
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    observeCloudKitActivity()
                }
                .onChange(of: hasCompletedInitialSync) { _, completed in
                    if completed && tailscaleEnabled && !TSmanager.isConnected {
                        Task {
                            await TSmanager.connect()
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func observeCloudKitActivity() {
        // Observe CloudKit activity notifications
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSPersistentStoreRemoteChangeNotification"),
            object: nil,
            queue: .main
        ) { _ in
            // CloudKit activity detected - wait a bit more
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second after last activity
                self.hasCompletedInitialSync = true
            }
        }
        
        // Fallback: If CloudKit not enabled or no activity after 5 seconds, proceed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !(self.syncServers || self.syncSettings) {
                self.hasCompletedInitialSync = true
            }
        }
    }
}

