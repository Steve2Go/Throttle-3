//
//  DownloadPicker.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 2/1/2026.
//

import SwiftUI
import Transmission
import KeychainAccess
import Combine

/// Represents a node in the file tree (either a file or folder)
struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]
    let fileIndex: Int? // Index in the torrent's file list
    let size: Int64
    var isSelected: Bool
    var isExpanded: Bool
    
    /// Calculate total size including all children
    var totalSize: Int64 {
        if isDirectory {
            return children.reduce(size) { $0 + $1.totalSize }
        }
        return size
    }
    
    /// Check if all children are selected
    var allChildrenSelected: Bool {
        guard isDirectory else { return isSelected }
        return !children.isEmpty && children.allSatisfy { node in
            node.isDirectory ? node.allChildrenSelected : node.isSelected
        }
    }
    
    /// Check if some (but not all) children are selected
    var someChildrenSelected: Bool {
        guard isDirectory else { return false }
        return children.contains { node in
            node.isSelected || node.someChildrenSelected
        } && !allChildrenSelected
    }
}

/// File picker for selecting which files to download from a torrent
struct DownloadPicker: View {
    let torrentID: Int
    let server: Servers
    
    @Environment(\.dismiss) private var dismiss
    @State private var rootNodes: [FileNode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedCount: Int = 0
    @State private var selectedSize: Int64 = 0
    
    private let keychain = Keychain(service: "com.srgim.throttle3")
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @EnvironmentObject var store: Store
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isApplying = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading files...")
                            .foregroundStyle(.secondary)
                            .padding(.top)
                    }
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Error")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await loadFiles()
                            }
                        }
                    }
                    .padding()
                } else if rootNodes.isEmpty {
                    VStack {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No files found")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach($rootNodes) { $node in
                                FileNodeRow(node: $node, level: 0, onSelectionChange: updateSelectionStats)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Select Files")
            .padding()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        applySelection()
                    }
                    .disabled(selectedCount == 0 || isApplying)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectedCount > 0 {
                    VStack {
                        Divider()
                        
                        HStack {
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(selectedCount) file\(selectedCount == 1 ? "" : "s") selected")
                            Spacer()
                            Text(formatBytes(selectedSize))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding()
                        .padding(.top, 0)
                        //                    .background(.quaternary)
                    }}
            }
        }
        .task {
            await loadFiles()
        }
    }
    
    // MARK: - File Loading
    
    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        
        guard let client = await createTransmissionClient() else {
            errorMessage = "Failed to connect to server"
            isLoading = false
            return
        }
        
        // Create request for this specific torrent
        let request = Request<[TorrentFile]>(
            method: "torrent-get",
            args: ["ids": [torrentID], "fields": ["id", "files", "fileStats"]],
            transform: { response -> Result<[TorrentFile], TransmissionError> in
                guard let arguments = response["arguments"] as? [String: Any],
                      let torrents = arguments["torrents"] as? [[String: Any]],
                      let torrentDict = torrents.first,
                      let filesDict = torrentDict["files"] as? [[String: Any]],
                      let statsDict = torrentDict["fileStats"] as? [[String: Any]]
                else {
                    return .failure(.unexpectedResponse)
                }
                
                let files = zip(filesDict, statsDict).enumerated().compactMap { index, element -> TorrentFile? in
                    let (fileDict, statsDict) = element
                    
                    guard let name = fileDict["name"] as? String,
                          let size = fileDict["length"] as? Int64,
                          let downloaded = fileDict["bytesCompleted"] as? Int64,
                          let priorityRaw = statsDict["priority"] as? Int,
                          let isWanted = statsDict["wanted"] as? Bool
                    else {
                        return nil
                    }
                    
                    let priority = Priority(rawValue: priorityRaw)
                    return TorrentFile(index: index, name: name, size: size, downloaded: downloaded, priority: priority, isWanted: isWanted)
                }
                
                return .success(files)
            }
        )
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            client.request(request)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("❌ Failed to fetch files: \(error)")
                            errorMessage = "Failed to load files: \(error.localizedDescription)"
                        }
                        continuation.resume()
                    },
                    receiveValue: { (files: [TorrentFile]) in
                        print("✅ Fetched \(files.count) files")
                        buildFileTree(from: files)
                        updateSelectionStats()
                        isLoading = false
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - File Tree Building
    
    private func buildFileTree(from files: [TorrentFile]) {
        // Build hierarchical tree from flat file list
        var nodesByPath: [String: FileNode] = [:]
        
        // First pass: create all nodes
        for file in files {
            let components = file.name.components(separatedBy: "/")
            var currentPath = ""
            
            for (index, component) in components.enumerated() {
                let isLast = index == components.count - 1
                currentPath += (currentPath.isEmpty ? "" : "/") + component
                
                if nodesByPath[currentPath] == nil {
                    nodesByPath[currentPath] = FileNode(
                        name: component,
                        path: currentPath,
                        isDirectory: !isLast,
                        children: [],
                        fileIndex: isLast ? file.index : nil,
                        size: isLast ? file.size : 0,
                        isSelected: isLast ? file.isWanted : false,
                        isExpanded: false
                    )
                }
            }
        }
        
        // Second pass: build parent-child relationships
        var finalNodes: [String: FileNode] = [:]
        
        for (path, var node) in nodesByPath {
            if node.isDirectory {
                // Find direct children
                node.children = nodesByPath.values.filter { child in
                    guard child.path != path else { return false }
                    let childParent = (child.path as NSString).deletingLastPathComponent
                    return childParent == path
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            
            finalNodes[path] = node
        }
        
        // Third pass: recursively update children and selection states
        func buildNodeWithChildren(path: String) -> FileNode? {
            guard var node = finalNodes[path] else { return nil }
            
            if node.isDirectory {
                // Recursively build children
                node.children = finalNodes.values
                    .filter { child in
                        let childParent = (child.path as NSString).deletingLastPathComponent
                        return childParent == path
                    }
                    .compactMap { child in
                        buildNodeWithChildren(path: child.path)
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                
                // Update directory selection based on children
                if !node.children.isEmpty {
                    node.isSelected = node.allChildrenSelected
                }
            }
            
            return node
        }
        
        // Extract root level nodes (no parent path)
        let rootPaths = finalNodes.keys.filter { !$0.contains("/") }
        rootNodes = rootPaths
            .compactMap { buildNodeWithChildren(path: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Selection Management
    
    private func updateSelectionStats() {
        var count = 0
        var size: Int64 = 0
        
        func countSelected(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isDirectory {
                    countSelected(node.children)
                } else if node.isSelected {
                    count += 1
                    size += node.size
                }
            }
        }
        
        countSelected(rootNodes)
        selectedCount = count
        selectedSize = size
    }
    
    private func applySelection() {
        guard !isApplying else { return }
        isApplying = true
        
        Task {
            await applyFileSelection()
            isApplying = false
        }
    }
    
    private func applyFileSelection() async {
        guard let client = await createTransmissionClient() else {
            errorMessage = "Failed to connect to server"
            isApplying = false
            return
        }
        
        // Collect selected and unselected file indices
        var wantedIndices: [Int] = []
        var unwantedIndices: [Int] = []
        
        func collectIndices(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isDirectory {
                    collectIndices(node.children)
                } else if let fileIndex = node.fileIndex {
                    if node.isSelected {
                        wantedIndices.append(fileIndex)
                    } else {
                        unwantedIndices.append(fileIndex)
                    }
                }
            }
        }
        
        collectIndices(rootNodes)
        
        print("📁 Applying selection: \(wantedIndices.count) wanted, \(unwantedIndices.count) unwanted")
        
        // Create torrent-set request
        var args: [String: Any] = ["ids": [torrentID]]
        if !wantedIndices.isEmpty {
            args["files-wanted"] = wantedIndices
        }
        if !unwantedIndices.isEmpty {
            args["files-unwanted"] = unwantedIndices
        }
        
        let request = Request<Bool>(
            method: "torrent-set",
            args: args,
            transform: { response -> Result<Bool, TransmissionError> in
                if response["result"] as? String == "success" {
                    return .success(true)
                    store.successIndicator = true
                }
                return .failure(.unexpectedResponse)
            }
        )
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            client.request(request)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [self] completion in
                        if case let .failure(error) = completion {
                            print("❌ Failed to apply file selection: \(error)")
                            errorMessage = "Failed to apply selection: \(error.localizedDescription)"
                        }
                        continuation.resume()
                    },
                    receiveValue: { [self] _ in
                        print("✅ Successfully applied file selection")
                        // Trigger refresh in Store
                        store.needsRefresh = true
                        dismiss()
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Helpers
    
    private func createTransmissionClient() async -> Transmission? {
        // Build Transmission URL using the tunnel port
        let scheme = server.usesSSL ? "https" : "http"
        var host: String
        var port: Int
        
        if server.tunnelWebOverSSH {
            host = "127.0.0.1"
            port = (Int(server.serverPort) ?? 80) + 8000
        } else if server.useTailscale {
            host = server.serverAddress
            port = Int(server.serverPort) ?? 9091
        } else {
            host = server.serverAddress
            port = Int(server.serverPort) ?? 9091
        }
        
        let urlString = "\(scheme)://\(host):\(port)\(server.rpcPath)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return nil
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        return Transmission(baseURL: url, username: server.user, password: password)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - File Node Row

struct FileNodeRow: View {
    @Binding var node: FileNode
    let level: Int
    let onSelectionChange: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                if node.isDirectory {
                    node.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Indentation
                    if level > 0 {
                        Color.clear
                            .frame(width: CGFloat(level * 20))
                    }
                    
                    // Checkbox
                    Button {
                        toggleSelection()
                    } label: {
                        Image(systemName: checkboxIcon)
                            .foregroundStyle(node.someChildrenSelected ? .blue : .primary)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    
                    // Folder/File icon
                    if node.isDirectory {
                        Image(systemName: node.isExpanded ? "folder.fill" : "folder")
                            .foregroundStyle(.blue)
                            .font(.system(size: 16))
                    } else {
                        Image(systemName: iconForFile(node.name))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                    }
                    
                    // Name
                    Text(node.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Size
                    Text(formatBytes(node.isDirectory ? node.totalSize : node.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Expansion indicator
                    if node.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Children (if expanded)
            if node.isDirectory && node.isExpanded {
                ForEach($node.children) { $child in
                    FileNodeRow(node: $child, level: level + 1, onSelectionChange: onSelectionChange)
                }
            }
        }
    }
    
    private var checkboxIcon: String {
        if node.isDirectory {
            if node.allChildrenSelected {
                return "checkmark.square.fill"
            } else if node.someChildrenSelected {
                return "minus.square.fill"
            } else {
                return "square"
            }
        } else {
            return node.isSelected ? "checkmark.square.fill" : "square"
        }
    }
    
    private func toggleSelection() {
        if node.isDirectory {
            // Toggle all children
            let newState = !node.allChildrenSelected
            setSelectionRecursively(&node, isSelected: newState)
        } else {
            node.isSelected.toggle()
        }
        onSelectionChange()
    }
    
    private func setSelectionRecursively(_ node: inout FileNode, isSelected: Bool) {
        node.isSelected = isSelected
        for index in node.children.indices {
            setSelectionRecursively(&node.children[index], isSelected: isSelected)
        }
    }
    
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ts", "m2ts"]
        let audioExtensions = ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma"]
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp"]
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
        
        if videoExtensions.contains(ext) {
            return "film"
        } else if audioExtensions.contains(ext) {
            return "music.note"
        } else if imageExtensions.contains(ext) {
            return "photo"
        } else if archiveExtensions.contains(ext) {
            return "doc.zipper"
        } else {
            return "doc"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - TorrentFile Definition
// This struct matches what's expected by the Transmission API

struct TorrentFile {
    let index: Int
    let name: String
    let size: Int64
    let downloaded: Int64
    let priority: Priority?
    let isWanted: Bool
}

// MARK: - Preview

#Preview {
    DownloadPicker(
        torrentID: 1,
        server: Servers(
            name: "Test Server",
            serverAddress: "localhost",
            serverPort: "9091"
        )
    )
}
