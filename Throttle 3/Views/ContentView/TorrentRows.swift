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

struct TorrentRows: View {
    let isSidebarVisible: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var store: Store
    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @ObservedObject private var connectionManager = ConnectionManager.shared
    @ObservedObject private var thumbnailManager = TorrentThumbnailManager.shared
    @State private var showServerList = false
    @State private var torrents: [Torrent] = []
    @State private var isLoadingTorrents = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visibleTorrentHashes: Set<String> = []
    @State private var thumbnailDebounceTask: Task<Void, Never>?
    @Query private var servers: [Servers]
    let keychain = Keychain(service: "com.srgim.throttle3")
    
    
    // Get the current server based on the store's currentServerID
    private var currentServer: Servers? {
        guard let currentServerID = store.currentServerID else { return nil }
        return servers.first(where: { $0.id == currentServerID })
    }
    
    var body: some View {
        Group {
            if tailscaleManager.isConnecting {
                ContentUnavailableView {
                    Label("Connecting Tailscale", systemImage: "circle.grid.3x3")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                }
            }
            else if (currentServer != nil) && (connectionManager.isConnecting || ((currentServer!.tunnelWebOverSSH || currentServer!.tunnelFilesOverSSH)) && !connectionManager.isConnected && ((currentServer?.useTailscale) != false && tailscaleManager.isConnected) || ((currentServer?.useTailscale) == false)) {
                ContentUnavailableView {
                    Label("Tunneling...", systemImage: "externaldrive.connected.to.line.below")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                }
            } else if isLoadingTorrents {
                ContentUnavailableView {
                    Label("Fetching...", systemImage: "arrow.up.arrow.down.square")
                        .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 0.0)))
                }
            }  else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(torrents, id: \.hash) { torrent in
                       
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
                                        print("Selected torrent: \(torrent.name ?? "Unknown")")
                                        // TODO: Navigate to torrent detail
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
               
//                if tailscaleManager.isConnecting {
//                    Button(action: {}) {
//                        Image(systemName: "circle.grid.3x3")
//                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
//                    }
//                } else
#if os(macOS)
                if connectionManager.isConnecting {
                    Button(action: {}) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                    }
                } else {
                    
                    Button(action: {
                        Task {
                            await fetchTorrents()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeat(.periodic(delay: 0.5)), isActive: isLoadingTorrents)
                    }
                    
                }
#endif
                
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                
                
                Button(action: {}) {
                    Image(systemName: "internaldrive")
                }
            }
            #if os(iOS)
            ToolbarItem {
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "externaldrive.badge.person.crop")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        // Settings action
                    }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
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
            #else
            if !isSidebarVisible {
                ToolbarItem {
                    Button(action: {
                        showServerList = true
                    }) {
                        Image(systemName: "externaldrive.badge.person.crop")
                    }
                }
                
                //TODO - Make a filters & servers dropdown
                
            }
            #endif
            
            
            
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showServerList) {
            NavigationStack {
                ServerList(columnVisibility: $columnVisibility)
                    .navigationTitle("Servers")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showServerList = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            Task {
                await fetchTorrents()
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
        
        guard !isLoadingTorrents else { return }
        
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
        
        let urlString = "\(scheme)://\(host):\(port)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        print("Connecting to Transmission at: \(urlString)")
        
        // Create Transmission client
        let client = Transmission(baseURL: url, username: server.user, password: password)
        
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
