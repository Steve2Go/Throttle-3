//
//  TorrentRows.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData
import Transmission
import KeychainAccess
import Combine
import TailscaleKit

struct TorrentRows: View {
    //let isSidebarVisible: Bool
    //@Binding var columnVisibility: NavigationSplitViewVisibility
    
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var store: Store
    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @ObservedObject private var thumbnailManager = TorrentThumbnailManager.shared
    @AppStorage("currentFilter") private var currentFilter: String = "dateAdded"
    @AppStorage("currentStatusFilter") private var currentStatusFilter: String = "all"
    @State private var searchText: String = ""
    @State private var showServerList = false
    @State private var torrents: [Torrent] = []
    @State private var isLoadingTorrents = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visibleTorrentHashes: Set<String> = []
    @State private var thumbnailDebounceTask: Task<Void, Never>?
    @State private var showingTorrentDetails = false
    @State private var selectedTorrent: Torrent?
    @Query private var servers: [Servers]
    let keychain = Keychain(service: "com.srgim.throttle3")
    
    
    // Get the current server based on the store's currentServerID
    var currentServer: Servers? {
        guard let currentServerID = store.currentServerID else { return nil }
        return servers.first(where: { $0.id == currentServerID })
    }
    
    // Computed property for filtered and sorted torrents
    var filteredAndSortedTorrents: [Torrent] {
        var result = torrents
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { torrent in
                (torrent.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply status filter
        switch currentStatusFilter {
        case "downloading":
            result = result.filter { torrent in
                guard let status = torrent.status?.rawValue else { return false }
                return status == 4 || status == 2 // Downloading or Verifying
            }
        case "seeding":
            result = result.filter { torrent in
                torrent.status?.rawValue == 6 // Seeding
            }
        case "paused":
            result = result.filter { torrent in
                torrent.status?.rawValue == 0 // Stopped
            }
        case "completed":
            result = result.filter { torrent in
                (torrent.progress ?? 0) >= 1.0
            }
        default: // "all"
            break
        }
        
        // Apply sorting
        switch currentFilter {
        case "name":
            result = result.sorted { (t0: Torrent, t1: Torrent) in
                (t0.name ?? "").localizedCaseInsensitiveCompare(t1.name ?? "") == .orderedAscending
            }
        case "size":
            result = result.sorted { (t0: Torrent, t1: Torrent) in
                (t0.size ?? 0) > (t1.size ?? 0)
            }
        case "progress":
            result = result.sorted { (t0: Torrent, t1: Torrent) in
                (t0.progress ?? 0) > (t1.progress ?? 0)
            }
        default: // "dateAdded"
            result = result.sorted { (t0: Torrent, t1: Torrent) in
                (t0.dateAdded ?? Date.distantPast) > (t1.dateAdded ?? Date.distantPast)
            }
        }
        
        return result
    }
    
    var body: some View {
        Group {
            if tailscaleManager.isConnecting && torrents.isEmpty {
                ContentUnavailableView (
                    "Connecting Tailscale",
                    image : "custom.circle.grid.3x3"
                        
            )
                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary, .secondary)
            }
            else if (currentServer != nil) && torrents.isEmpty && (connectionManager.isConnecting || ((currentServer!.tunnelWebOverSSH || currentServer!.tunnelFilesOverSSH)) && !connectionManager.isConnected && ((currentServer?.useTailscale) != false && tailscaleManager.isConnected) || ((currentServer?.useTailscale) == false)) {
                ContentUnavailableView {
                    Label("Tunneling...", systemImage: "externaldrive.connected.to.line.below")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                }
            } else if torrents.isEmpty && isLoadingTorrents {
                ContentUnavailableView {
                    Label("Fetching...", systemImage: "arrow.up.arrow.down.square")
                        .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 0.0)))
                }
            }  else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredAndSortedTorrents, id: \.hash) { torrent in
                       
                                HStack {
                                    // Thumbnail display
                                    Group {
                                        if let progress = torrent.progress, progress < 1.0 {
                                            // Downloading
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.secondary)
                                        } else if let thumbnail = thumbnailManager.getThumbnail(for: torrent) {
                                            // Has cached thumbnail
                                            #if os(macOS)
                                            Image(nsImage: thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                            #else
                                            Image(uiImage: thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                            #endif
                                        } else {
                                            // Complete but no thumbnail yet
                                            Image("placeholder-black")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 70, height: 70)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onAppear {
                                        if let hash = torrent.hash {
                                            visibleTorrentHashes.insert(hash)
                                            scheduleThumbnailGeneration()
                                        }
                                    }
                                    .onDisappear {
                                        if let hash = torrent.hash {
                                            visibleTorrentHashes.remove(hash)
                                        }
                                    }
                                    
                                    Button {
                                        selectedTorrent = torrent
                                        showingTorrentDetails = true
                                    }
                                    label:{
                                        VStack (alignment: .leading) {
                                            HStack {
                                                Image(systemName: iconForStatus(torrent.status?.rawValue))
                                                    .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)), isActive:  torrent.status?.rawValue == 2)
                                                    .padding(.leading, 6)
                                                    .foregroundStyle(.primary)
                                                
                                                Text(torrent.name ?? "Unknown")
                                                    .padding(.leading, 0)
                                                    .foregroundColor(.primary)
                                            }
                                            //status
                                            switch torrent.status?.rawValue {
                                            case 0:
                                                ProgressView(value: torrent.progress)
                                                    .tint(.red)
                                            case 2:
                                                ProgressView(value: torrent.progress)
                                                    .tint(.yellow)
                                            case 4:
                                                ProgressView(value: torrent.progress)
                                                    .tint(.blue)
                                            case 6:
                                                ProgressView(value: torrent.progress)
                                                    .tint(.green)
                    //                        case 6:
                    //                            ProgressView(value: torrent.progress)
                    //                                .tint(.orange)
                                            default:
                                                ProgressView(value: torrent.progress)
                                                    .tint(.gray)
                                            }
                                            Text("Downloaded \(formatBytes(torrent.bytesValid ?? 0)) of \(formatBytes(torrent.size ?? 0))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        
                    }
                    .padding()
                }
                .refreshable {
                    Task {
                        await fetchTorrents()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
               
               if tailscaleManager.isConnecting  && !torrents.isEmpty {
                   Button(action: {}) {
                       Image("custom.circle.grid.3x3")
                       .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                       .symbolRenderingMode(.hierarchical)
                   }
               } else if connectionManager.isConnecting && !torrents.isEmpty {
                    Button(action: {}) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                    }
                } else if isLoadingTorrents && !torrents.isEmpty {
                    Button(action: {}) {
                        Image(systemName: "arrow.up.arrow.down.square")
                            .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 0.0)))
                    }
                } else {
                    #if os(macOS)
                    Button(action: {
                        Task {
                            await fetchTorrents()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeat(.periodic(delay: 0.5)), isActive: isLoadingTorrents)
                    }
                    #endif
                    
                }

                
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                
                
                Button(action: {}) {
                    Image(systemName: "externaldrive.badge.icloud")
                }
            }
            #if os(iOS)
            ToolbarItem {
                
                Button(action: {
                    dismiss()
                }) {
                    Image("custom.externaldrive.badge.ellipsis")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    
                    
                    Button(action: {
                        // Create action
                    }) {
                        Label("Create", systemImage: "document.badge.plus")
                    }
                    
                    Button(action: {
                        // Selection action
                    }) {
                        Label("Selection", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            
        }
            #endif
            
            
            
        }
        .sheet(isPresented: $showingTorrentDetails) {
            if let torrent = selectedTorrent {
                TorrentDetailsView(torrent: torrent)
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 710)
                #endif
            }
        }
        .navigationTitle(currentServer?.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
       
        .searchable(text: $searchText)
#if os(iOS)
        .applySearchToolbarBehaviorIfAvailable()
        #endif
        .onAppear {
            if tailscaleManager.isConnected || (currentServer?.useTailscale == false) {
            Task {
                await fetchTorrents()
            }
            } else if currentServer?.useTailscale == true && !tailscaleManager.isConnecting {
                    Task {
                        await tailscaleManager.connect()
                    }
                }
            
        }
        .onChange(of: store.currentServerID) { oldID, newID in
            print("🔄 Server switch detected: \(String(describing: oldID)) -> \(String(describing: newID))")
            
            // Clear all state when switching servers
            torrents = []
            visibleTorrentHashes.removeAll()
            cancellables.removeAll()
            
            Task {
                // Disconnect from old server
                connectionManager.disconnect()
                
                // Wait for disconnect to complete
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Wait for currentServerID to clear
                while connectionManager.currentServerID != nil {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                
                print("✓ Disconnected from old server, fetching from new server...")
                if tailscaleManager.isConnected || (currentServer?.useTailscale == false) {
                    await fetchTorrents()
                }
                
            }
        }
        .onChange(of: tailscaleManager.isConnected) { _, isConnected in
            if isConnected {
                Task {
                    await fetchTorrents()
                }
            }
        }
    }
    
    // MARK: - Fetch Torrents
    
    func fetchTorrents() async {
        guard let server = currentServer else {
            print("No server selected")
            return
        }
        
        // Ensure we're not fetching torrents for a different server
        if let connectedServerID = connectionManager.currentServerID,
           connectedServerID != server.id {
            print("⚠️ Connection mismatch: Connected to \(connectedServerID) but trying to fetch for \(server.id)")
            print("   Disconnecting and reconnecting to correct server...")
            connectionManager.disconnect()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        guard !isLoadingTorrents else {
            print("⚠️ Already loading torrents, skipping duplicate fetch")
            return
        }
        
        print("📡 Fetching torrents for server: \(server.name) (ID: \(server.id))")
        
        isLoadingTorrents = true
        defer { isLoadingTorrents = false }
        
        // Check Tailscale connection
        if server.useTailscale && !tailscaleManager.isConnected {
            print("Connecting to Tailscale...")
            await tailscaleManager.connect()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        // Check tunnel connection
        if server.tunnelWebOverSSH && !tunnelManager.isActive {
            print("Connecting tunnel...")
            await connectionManager.connect(server: server)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        // Build Transmission URL
        let scheme = server.usesSSL ? "https" : "http"
        var host: String
        var port: Int
        
        if server.tunnelWebOverSSH {
            // Using SSH tunnel: connect to localhost on serverPort + 8000
            host = "127.0.0.1"
            port = (Int(server.serverPort) ?? 80) + 8000
        } else if server.useTailscale {
            // Using Tailscale: connect to server address with reverse proxy port
            host = server.serverAddress
            port = Int(server.reverseProxyPort) ?? (Int(server.serverPort) ?? 9091)
        } else {
            // Direct connection
            host = server.serverAddress
            port = Int(server.serverPort) ?? 9091
        }
        
        let urlString = "\(scheme)://\(host):\(port)\(server.rpcPath)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        print("Connecting to Transmission at: \(urlString)")
        
        // Create Transmission client
//        #if os(iOS)
//        var client: Transmission?
//        if server.useTailscale && !server.tunnelWebOverSSH && (tailscaleManager.node != nil){
//            do {
//                let (sessionConfig, _) = try await URLSessionConfiguration.tailscaleSession(tailscaleManager.node!)
//                let session = URLSession(configuration: sessionConfig)
//                client = Transmission(baseURL: url, username: server.user, password: password, session: session)
//            } catch {
//                
//            }
////        } else {
//            client = Transmission(baseURL: url, username: server.user, password: password, )
////        }
//
//        #else
        let client = Transmission(baseURL: url, username: server.user, password: password, )
//        #endif

        // Use Combine to async/await bridge
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            client.request(.torrents(properties: Torrent.PropertyKeys.allCases))
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("❌ Failed to fetch torrents: \(error)")
                        }
                        continuation.resume()
                    },
                    receiveValue: { fetchedTorrents in
                        torrents = fetchedTorrents
                        print("✅ Fetched \(fetchedTorrents.count) torrents")
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Helpers
    
    private func iconForStatus(_ status: Int?) -> String {
        switch status {
        case 0:
            return "xmark.icloud"
        case 2:
            return "arrow.trianglehead.clockwise.icloud"
        case 4:
            return "icloud.and.arrow.down"
        case 6:
            return "icloud.and.arrow.up"
        default:
            return "icloud"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Thumbnail Generation
    
    private func scheduleThumbnailGeneration() {
        // Cancel previous debounce task
        thumbnailDebounceTask?.cancel()
        
        // Start new debounce task (1 second delay)
        thumbnailDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            guard !Task.isCancelled else { return }
            await generateVisibleThumbnails()
        }
    }
    
    private func generateVisibleThumbnails() async {
        guard let server = currentServer else { return }
        
        // Get visible torrents
        let visibleTorrents = torrents.filter { torrent in
            guard let hash = torrent.hash else { return false }
            return visibleTorrentHashes.contains(hash)
        }
        
        guard !visibleTorrents.isEmpty else { return }
        
        // Get download directory from ConnectionManager
        // For now, use a default or query from Transmission session
        let downloadDir = "~/Downloads" // TODO: Get from ConnectionManager or Transmission session
        
        await thumbnailManager.generateThumbnails(
            for: visibleTorrents,
            server: server,
            downloadDir: downloadDir
        )
    }
}

// Dummy torrent model for testing
struct DummyTorrent: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
}

// Dummy data for testing
let dummyTorrents = [
    DummyTorrent(name: "Ubuntu 24.04 LTS", icon: "arrow.down.circle"),
    DummyTorrent(name: "Big Buck Bunny", icon: "arrow.down.circle"),
    DummyTorrent(name: "Debian 12 ISO", icon: "arrow.down.circle")
]

// Extension to conditionally apply searchToolbarBehavior for iOS 26+
#if os(iOS)
extension View {
    @ViewBuilder
    func applySearchToolbarBehaviorIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}
#endif
