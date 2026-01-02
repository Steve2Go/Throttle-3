//
//  Throttle_3App.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData
import KeychainAccess
import Network
import Combine

@main
struct Throttle_3App: App {
    
    @Environment(\.scenePhase) private var scenePhase
    
    //init Sync Settings & local settings
    @AppStorage("syncKeychain") var syncKeychain = false
    @AppStorage("syncServers") var syncServers = false
    @AppStorage("syncLocalServers") var syncLocalServers = false
    @AppStorage("syncSettings") var syncSettings = false
    @AppStorage("instance") var instance: String = UUID().uuidString
    @AppStorage("TailscaleEnabled") var tailscaleEnabled = false
    @AppStorage("ServerToStart") var ServerToStart: String?
    
     @Environment(\.modelContext) private var modelContext
 
    @ObservedObject private var TSmanager = TailscaleManager.shared
    @StateObject var networkMonitor = NetworkMonitor()
    @StateObject private var store = Store()
    
    @State private var hasCompletedInitialSync = false
    @State private var containerRefreshTrigger = 0
    @State private var disconnectTask: Task<Void, Never>?
    
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
                .environmentObject(store)
                .environmentObject(networkMonitor)
                .onAppear {
                    if syncServers == true {
                        ///wait for icloud update
                        observeCloudKitActivity()
                    } else {
                        // Mark as ready - connections will be lazy
                        store.isConnected = true
                    }
                }
            ///Connect servers if known
                .onChange(of: hasCompletedInitialSync) { _, completed in
                    if completed {
                        // Mark as ready - connections will be lazy
                        store.isConnected = true
                    }
                }
            
                    .onChange(of: store.currentServerID) { oldID, newID in
                        // Just clear torrents - tunnel will be created on demand
                        store.torrents = []
                        store.isConnected = false
                    }
            #if os(iOS)
//                 .onChange(of: scenePhase) {
//                     ///opened from BG
//                     if scenePhase == .active {
//                         // Tunnels will recreate on demand
//                         store.isConnected = true
//                     } else {
//                         // Background - stop all tunnels
//                         Task {
//                             TunnelManager.shared.stopAllTunnels()
//                             await TSmanager.disconnect()
//                             store.isConnected = false
//                         }
// //                        disconnectTask = Task {
// //                            try? await Task.sleep(nanoseconds: 10_000_000_000)
// //                            guard !Task.isCancelled else { return }
// //                            
// //                        }
//                     }
//                 }
                // .onChange(of: networkMonitor.gateways) {
                //     ///network changed
                //     if scenePhase == .active {
                //         store.isConnected = true
                //     }
                    
                // }
            #endif  
        } 
        .modelContainer(sharedModelContainer)
                #if os(macOS)
 .commands {
                        CommandGroup(replacing: .appSettings) {
                            Button("Settings") {
                                store.showSettings = true
                            }.keyboardShortcut(",", modifiers: [.command])
                        Button("Tailscale") {
                            store.showTailscaleSheet = true
                        }
                        
                        Button("New Server..."){
                                store.showAddServer = true
                            }
                          
                    }
                    }
        #endif
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

class NetworkMonitor: ObservableObject {
    private let networkMonitor = NWPathMonitor()
    private let workerQueue = DispatchQueue(label: "Monitor")
    @Published var isConnected = false
    @Published var isExpensive = false
    @Published var gateways: [NWEndpoint] = []

    init() {
        networkMonitor.pathUpdateHandler = { path in
            Task { @MainActor in
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.gateways = path.gateways
            }
        }
        networkMonitor.start(queue: workerQueue)
    }
}
