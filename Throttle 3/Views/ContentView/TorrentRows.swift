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
#if os(iOS)
import TailscaleKit
#endif

struct TorrentRows: View {
    //let isSidebarVisible: Bool
    //@Binding var columnVisibility: NavigationSplitViewVisibility
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var store: Store
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @ObservedObject private var tailscaleManager = TailscaleManager.shared
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @ObservedObject private var thumbnailManager = TorrentThumbnailManager.shared
    @AppStorage("currentFilter") private var currentFilter: String = "dateAdded"
    @AppStorage("currentStatusFilter") private var currentStatusFilter: String = "all"
    @State private var searchText: String = ""
    @State private var showServerList = false
    @State private var isLoadingTorrents = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var visibleTorrentHashes: Set<String> = []
    @State private var thumbnailDebounceTask: Task<Void, Never>?
    @State private var showingTorrentDetails = false
    @State private var selectedTorrent: Torrent?
    @State private var showFilesPicker = false
    @State private var selectedTorrentForFiles: Int?
    @Query var servers: [Servers]
    @State private var doFetch = false
    @AppStorage("refreshRate") var refreshRate = "30"
    let keychain = Keychain(service: "com.srgim.throttle3")
    @AppStorage("showThumbs") var showThumbs = true
    @State var selectedTorrents: Set<Int> = []
    
    
     //Get the current server based on the store's currentServerID
        var currentServer: Servers? {
            guard let currentServerID = store.currentServerID else { return nil }
            return servers.first(where: { $0.id == currentServerID })
        }
    
    // Computed property for filtered and sorted torrents
    var filteredAndSortedTorrents: [Torrent] {
        var result = store.torrents
        
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
            if store.torrents.isEmpty {
                ContentUnavailableView {
                    Label("Loading", systemImage: "arrow.trianglehead.clockwise")
                        .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 0.5)))
                } description: {
                    Text("Your downloads will appear in a moment")
                }
                
                    
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredAndSortedTorrents, id: \.hash) { torrent in
                            
                            HStack {
                                // Thumbnail display
                                if !selectedTorrents.isEmpty {
                                    Button {
                                        if selectedTorrents.contains(torrent.id!) {
                                            selectedTorrents.remove(torrent.id!)
                                        } else{
                                            selectedTorrents.insert(torrent.id!)
                                        }
                                    } label: {
                                        Image(systemName: selectedTorrents.contains(torrent.id!) ? "checkmark.circle" : "circle")
                                        #if os(iOS)
                                            .font(.system(size: 30))
                                        #endif
                                    } .buttonStyle(.plain)
                                        .symbolEffect(.wiggle.clockwise.byLayer, options: .repeat(.continuous))
                                    
                                }
                                if showThumbs {
                                    Button {
                                        handleThumbnailTap(torrent: torrent)
                                    } label: {
                                        HStack{
                                            if let progress = torrent.progress, progress < 1.0 {
                                                // Downloading
                                                Image("folder")
                                                    .resizable()
                                                    .frame(maxWidth: 65,maxHeight:65)
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
                                            }  else {
                                                // Complete but no thumbnail yet
                                                Image("placeholder-black")
                                                    .font(.system(size: 40))
                                            }
                                            
                                            //status icon
                                            
                                            
                                        }
                                        .frame(width: 70, height: 70)
                                        //.background(Color.secondary.opacity(0.1))
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
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Image(systemName: thumbnailManager.generatingHashes.contains(torrent.hash ?? "") ? "photo.badge.arrow.down.fill" : iconForStatus(torrent))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(.quaternary))
                                        .padding(.leading, -40)
                                        .padding(.top, 40)
                                        .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: torrent.status?.rawValue == 2)
                                        .symbolEffect(.breathe, isActive: torrent.status?.rawValue != 2 && thumbnailManager.generatingHashes.contains(torrent.hash ?? ""))
                                } else {
                                    Image(systemName: iconForStatus(torrent))
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(.quaternary))
                                        .padding(.top, 5)
                                        .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)), isActive: torrent.status?.rawValue == 2)
                                        .frame(width:30)
                                }
                                Button {
                                    if selectedTorrents.isEmpty {
                                        selectedTorrent = torrent
                                        showingTorrentDetails = true
                                    } else{
                                        if selectedTorrents.contains(torrent.id!) {
                                            selectedTorrents.remove(torrent.id!)
                                        } else{
                                            selectedTorrents.insert(torrent.id!)
                                        }
                                    }
                                }
                                label:{
                                    VStack (alignment: .leading) {
                                        
                                        Text(torrent.name ?? "Unknown")
                                            .padding(.leading, 0)
                                            .foregroundColor(.primary)
                                        
                                            //status
                                            VStack {
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
                                                
                                                
                                                HStack {
                                                    
                                                    if torrent.progress == 1{
                                                        Image(systemName: "internaldrive")
                                                            .foregroundStyle(.secondary)
                                                            .font(.system(size: 12, weight: .semibold))
                                                        Text("\(formatBytes(torrent.size ?? 0))")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    } else {
                                                        Image(systemName: "arrow.up.arrow.down")
                                                            .foregroundStyle(.secondary)
                                                            .font(.system(size: 12, weight: .semibold))
                                                        Text("\(formatBytes(torrent.bytesValid ?? 0).split(separator: " ")[0]) of \(formatBytes(torrent.size ?? 0))")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "plus.app")
                                                        .foregroundStyle(.secondary)
                                                        .font(.system(size: 12, weight: .semibold))
                                                    if let dateAdded = torrent.dateAdded {
                                                        Text(formatDate( dateAdded))
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            
                                            
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                }
                                    .padding(.horizontal)
                            
                            
                            .contextMenu {
                                if let torrentID = torrent.id, selectedTorrents.contains(torrentID) {
                                    Button {
                                        selectedTorrents.remove(torrentID)
                                    } label: {
                                        Image(systemName: "circle")
                                        Text("Remove Selection")
                                    }
                                } else if let torrentID = torrent.id {
                                    Button {
                                        selectedTorrents.insert(torrentID)
                                    } label: {
                                        Image(systemName: "checkmark.circle")
                                        Text("Select")
                                    }
                                    if let currentServer = currentServer {
                                        torrentMenu(torrentID: Set([torrent.id!]), stopped: torrent.status?.rawValue == 0 ? true : false, single: true, server: currentServer, showFilesPicker: Binding(
                                            get: { showFilesPicker && selectedTorrentForFiles == torrent.id },
                                            set: { newValue in
                                                showFilesPicker = newValue
                                                if newValue {
                                                    selectedTorrentForFiles = torrent.id
                                                } else {
                                                    selectedTorrentForFiles = nil
                                                }
                                            }
                                        ))
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            //.background(selectedTorrents.contains(torrent.id!) ? Color.accentColor.opacity(0.2) : Color.clear)
                            
                           
                        } .padding(.vertical, 0)
                    }
                    
                }
                .refreshable {
                    Task {
                        store.torrents = []
                        await fetchTorrents()
                    }
                }
            }
        }
        
        .toolbar {
            if selectedTorrents.isEmpty {
                ToolbarItemGroup(placement: .automatic) {
                    
                   
                    
                    if tailscaleManager.isConnecting {
                        Button(action: {}) {
                            Image("custom.circle.grid.3x3")
                                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
                                .symbolRenderingMode(.hierarchical)
                        }
                    } else if tunnelManager.isConnecting {
                        Button(action: {}) {
                            Image("custom.server.rack.shield")
                                .symbolEffect(.wiggle.clockwise.byLayer, options: .repeat(.periodic(delay: 0.5)))
                        }
                    } else if isLoadingTorrents {
                        Button(action: {}) {
                            Image(systemName: "arrow.up.arrow.down.square")
                                .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 0.0)))
                        }
                    } else {
#if os(macOS)
                        Button(action: {
                            Task {
                                store.torrents = []
                                await fetchTorrents()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeat(.periodic(delay: 0.5)), isActive: isLoadingTorrents)
                        }
#endif
                        
                    }
                    
                    if store.successIndicator {
                        Button(action: {}) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolEffect(.pulse)
                                .foregroundStyle(.green)
                        }
                    }
#if os(iOS)
                    Menu {
                        
                        Button(action: {}) {
                            Label("Add Torrent", systemImage: "plus")
                        }
                        
                        Button(action: {
                            // Create action
                        }) {
                            Label("Create Torrent", systemImage: "document.badge.plus")
                        }
                        
                        
                    } label: {
                        Image(systemName: "plus")
                    }
#endif
                    
                    
                    Button(action: {
                        #if os(macOS)
                        if let server = currentServer,
                           let mountPath = SSHFSManager.shared.getMountPath(server) {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPath)
                        }
                        #else
                        store.fileBrowserCover = true
                        #endif
                    }) {
                        Image(systemName: "internaldrive")
                    }
                    #if os(macOS)
                    .disabled(currentServer.flatMap { SSHFSManager.shared.getMountPath($0) } == nil)
                    #endif
                }
#if os(iOS)
                ToolbarItem {
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
#endif
                
            } else {
                ToolbarItemGroup(placement: .automatic) {
                    
                    if selectedTorrents.count != store.torrents.count {
                        Button {
                            selectedTorrents = Set(store.torrents.compactMap { $0.id })
                        } label: {
                            Image(systemName: "checkmark.circle")
                            Text("All")
                        }
                    }
                    if !selectedTorrents.isEmpty {
                        Button {
                            selectedTorrents.removeAll()
                        } label: {
                            Image(systemName: "xmark.circle")
                            Text("Cancel")
                        }
                    }
                    if let currentServer = currentServer {
                        Menu {
                            torrentMenu(torrentID: selectedTorrents, stopped: false, single: false, server: currentServer, showFilesPicker: .constant(false))
                        } label: {
                            Image("custom.ellipsis.circle.badge.checkmark")
                        }
                    }
                }
            }
            
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $store.fileBrowserCover) {
            if let currentServer = currentServer {
                FileBrowserView(server: currentServer, initialPath: store.fileBrowserPath)
            }
        }
        .sheet(isPresented: $store.fileBrowserSheet) {
            if let currentServer = currentServer {
                FileBrowserView(server: currentServer)
            }
        }
    
        #endif
        .sheet(isPresented: $showingTorrentDetails) {
            if let torrent = selectedTorrent, let currentServer = currentServer {
                TorrentDetailsView(torrent: torrent, server: currentServer)
#if os(macOS)
                    .frame(minWidth: 400, minHeight: 710)
#endif
            }
        }
        .sheet(isPresented: $showFilesPicker) {
            if let torrentID = selectedTorrentForFiles, let currentServer = currentServer {
                DownloadPicker(torrentID: torrentID, server: currentServer)
                    #if os(macOS)
                    .frame(minWidth: 500, minHeight: 300)
                    #endif
            }
        }
        .navigationTitle(selectedTorrents.isEmpty ? currentServer?.name ?? "" : "Selection")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationBarBackButtonHidden(true)
    
        .searchable(text: $searchText)
//#if os(iOS)
//       // .applySearchToolbarBehaviorIfAvailable()
//#endif
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await fetchTorrents()
                }
            }
        }
        .onChange(of: store.currentServerID){
            store.torrents = []
            visibleTorrentHashes.removeAll()
            cancellables.removeAll()
            doFetch = false
            Task{
                await fetchTorrents()
            }
        }
        // .onChange(of: store.isConnected) {
        //     if store.isConnected {
        //         Task {
        //             await fetchTorrents()
        //         }
        //     }
        // }
        .onAppear {
            // Fetch torrents when view appears
            Task {
                await fetchTorrents()
            }
        }
        .onChange(of:store.successIndicator){
            if store.successIndicator == true {
                Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 0.1 seconds
                   await fetchTorrents()
                }
            }
        }
        .onChange(of: store.needsRefresh) {
            if store.needsRefresh {
                store.needsRefresh = false
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
        
        guard !isLoadingTorrents else {
            print("⚠️ Already loading torrents, skipping duplicate fetch")
            return
        }
        
        print("📡 Fetching torrents for server: \(server.name) (ID: \(server.id))")
        
        isLoadingTorrents = true
        defer { isLoadingTorrents = false }
        
        // Ensure tunnel exists and get local port
        guard let port = await tunnelManager.ensureTunnel(for: server) else {
            print("❌ Failed to establish tunnel for server: \(server.name)")
            return
        }
        
        // Build Transmission URL using the tunnel port
        let scheme = "http"
        let host = "127.0.0.1"
        
        let urlString = "\(scheme)://\(host):\(port)\(server.rpcPath)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        print("Connecting to Transmission at: \(urlString)")
        
        let client = Transmission(baseURL: url, username: server.user, password: password)

        // Use Combine to async/await bridge with timeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            var hasResumed = false
            
            // Set a timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if !hasResumed {
                    hasResumed = true
                    cancellable?.cancel()
                    print("⚠️ Transmission request timed out after 30 seconds")
                    continuation.resume()
                }
            }
            
            cancellable = client.request(.torrents(properties: Torrent.PropertyKeys.allCases))
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("❌ Failed to fetch torrents: \(error)")
                        }
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume()
                        }
                    },
                    receiveValue: { (fetchedTorrents: [Torrent]) in
                        store.torrents = fetchedTorrents
                        print("✅ Fetched \(fetchedTorrents.count) torrents")
                        doFetch = true
                        fetchTimer()
                    }
                )
            
            if let cancellable = cancellable {
                cancellables.insert(cancellable)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func iconForStatus(_ torrent: Torrent) -> String {
        let status = torrent.status?.rawValue
        
        if torrent.progress == 1 && status != 2 {
            if isVideoFile(torrent.name!){
                return "play.fill"
            } else {
                return "externaldrive.fill"
            }
        }
        switch status {
        case 0:
            return "stop.fill"
        case 2:
            return "arrow.clockwise.fill"
        case 4:
            return "arrowshape.down.fill"
        case 6:
            return "arrowshape.up.fill"
        default:
            return "icloud.fill"
        }
    }
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    private func fetchTimer() {
        if !doFetch {
            return
        }
        Task {
            await fetchTorrents()
            if let rr = Double(refreshRate) {
                try? await Task.sleep(for: .seconds(rr))
            }
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
        let visibleTorrents = store.torrents.filter { torrent in
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
    
    // MARK: - Video File Detection
    
    private func isVideoFile(_ name: String) -> Bool {
        let videoExtensions = [".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".mpg", ".mpeg", ".3gp", ".ogv"]
        let lowercasedName = name.lowercased()
        return videoExtensions.contains { lowercasedName.hasSuffix($0) }
    }
    
    // MARK: - Thumbnail Tap Handler
    
    private func handleThumbnailTap(torrent: Torrent) {
        guard let torrentName = torrent.name else { return }
        
        // Check if it's a video file
        if isVideoFile(torrentName) {
            // TODO: Handle video file playback
            print("📹 Video file tapped: \(torrentName)")
            return
        }
        
        guard let server = currentServer else { return }
        
        // Calculate the full path to the torrent folder
        let sftpBase = server.sftpBase.isEmpty ? "/" : server.sftpBase
        let downloadPath = torrent.downloadPath ?? sftpBase
        
        // Append torrent name to get full folder path
        // Example: downloadPath="/storage/downloads", name="mytorrent" -> fullPath="/storage/downloads/mytorrent"
        let fullPath = (downloadPath as NSString).appendingPathComponent(torrentName)
        
        // Calculate relative path from sftpBase
        // Example: sftpBase="/storage", fullPath="/storage/downloads/mytorrent" -> relativePath="/downloads/mytorrent"
        var relativePath = fullPath
        if fullPath.hasPrefix(sftpBase) {
            relativePath = String(fullPath.dropFirst(sftpBase.count))
            // Ensure it starts with /
            if !relativePath.hasPrefix("/") {
                relativePath = "/" + relativePath
            }
        }
        
        // Open folder for non-video files
        #if os(macOS)
        // Open in Finder
        guard let mountPath = SSHFSManager.shared.getMountPath(server) else {
            print("❌ No mount path available for server")
            return
        }
        
        // Construct full path to torrent folder using relative path
        let torrentPath = (mountPath as NSString).appendingPathComponent(relativePath)
        
        // Check if path exists and open it
        if FileManager.default.fileExists(atPath: torrentPath) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: torrentPath)
        } else {
            // Fallback to opening mount root
            print("⚠️ Path doesn't exist: \(torrentPath), opening mount root")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPath)
        }
        #else
        // Open in file browser on iOS with relative path
        store.fileBrowserPath = relativePath
        store.fileBrowserCover = true
        print("📂 Opening folder: \(relativePath) (fullPath: \(fullPath))")
        #endif
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

