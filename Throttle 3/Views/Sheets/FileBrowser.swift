//
//  FileBrowser.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 03/01/2026.
//

import SwiftUI

struct FileBrowserView: View {
    let server: Servers
    let initialPath: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var navigationPath: [NavigationFolder] = []
    
    init(server: Servers, initialPath: String? = nil) {
        self.server = server
        self.initialPath = initialPath
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            DirectoryContentView(
                server: server,
                path: server.sftpBase.isEmpty ? "/" : server.sftpBase,
                isRoot: true
            )
            .navigationDestination(for: NavigationFolder.self) { navFolder in
                DirectoryContentView(
                    server: server,
                    path: navFolder.path,
                    isRoot: false
                )
            }
            .onAppear {
                // Navigate to initial path if provided
                if let initialPath = initialPath, !initialPath.isEmpty {
                    let sftpBase = server.sftpBase.isEmpty ? "/" : server.sftpBase
                    // Construct full path by combining base and relative path
                    let fullPath = (sftpBase as NSString).appendingPathComponent(initialPath)
                    navigationPath.append(NavigationFolder(path: fullPath))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        store.fileBrowserCover = false
                        store.fileBrowserSheet = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

// MARK: - Navigation Helper

struct NavigationFolder: Hashable {
    let path: String
}

// MARK: - Directory Content View

struct DirectoryContentView: View {
    let server: Servers
    let path: String
    let isRoot: Bool
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var files: [SFTPFileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showVideoPlayer = false
    @State private var videoPlayerURL: URL?
    @AppStorage("fileBrowserIconView") var icons: Bool = false
    @AppStorage("fileBrowserIconFoldersFirst") var foldersFirst: Bool = true
    @AppStorage("fileBrowserSortBy") var sortBy: String = "name"
    
    private let sftpManager = SFTPManager.shared
    #if os(iOS)
    private let streamServer = StreamServerManager.shared
    #endif
    
    var body: some View {
        Group {
            if isLoading && files.isEmpty {
                ProgressView("Loading...")
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await loadDirectory()
                        }
                    }
                }
            } else {
                fileListView
            }
        }
        .navigationTitle(pathTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isRoot {
                ToolbarItem {
                    Button {
                        store.fileBrowserCover = false
                        store.fileBrowserSheet = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            ToolbarItem {
                Menu {
                    Button {
                        // TODO: Select mode
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    
                    Button {
                        // TODO: New folder
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        // TODO: Upload
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Toggle(isOn: $foldersFirst) {
                        Label("Folders First", systemImage: "text.below.photo")
                    }
                    
                    Divider()
                    
                    Picker("View Mode", selection: $icons) {
                        Label("List", systemImage: "list.bullet")
                            .tag(false)
                        Label("Icons", systemImage: "square.grid.2x2")
                            .tag(true)
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Picker("Sort By", selection: $sortBy) {
                        Label("Name", systemImage: "textformat")
                            .tag("name")
                        Label("Date", systemImage: "calendar")
                            .tag("date")
                        Label("Size", systemImage: "arrow.up.arrow.down")
                            .tag("size")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
           
        }
        .task {
            await loadDirectory()
        }
        .onDisappear {
            store.fileBrowserPath = nil
        }
    }
    
    
    private var pathTitle: String {
        let effectiveRoot = server.sftpBase.isEmpty ? "/" : server.sftpBase
        if path == effectiveRoot || path == "/" {
            return server.name
        }
        return path.split(separator: "/").last.map(String.init) ?? server.name
    }
    
    private var fileListView: some View {
        Group {
            if icons {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
                    ], spacing: 16) {
                        ForEach(sortedFiles) { file in
                            if file.isDirectory {
                                NavigationLink(value: NavigationFolder(path: path.hasSuffix("/") ? path + file.name : path + "/" + file.name)) {
                                    FileRowView(
                                        name: file.name,
                                        isDirectory: true,
                                        size: file.size,
                                        modifiedTime: file.modifiedTime,
                                        isParent: false
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    handleFileTap(file)
                                } label: {
                                    FileRowView(
                                        name: file.name,
                                        isDirectory: false,
                                        size: file.size,
                                        modifiedTime: file.modifiedTime,
                                        isParent: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(sortedFiles) { file in
                        if file.isDirectory {
                            NavigationLink(value: NavigationFolder(path: path.hasSuffix("/") ? path + file.name : path + "/" + file.name)) {
                                FileRowView(
                                    name: file.name,
                                    isDirectory: true,
                                    size: file.size,
                                    modifiedTime: file.modifiedTime,
                                    isParent: false
                                )
                            }
                        } else {
                            Button {
                                handleFileTap(file)
                            } label: {
                                FileRowView(
                                    name: file.name,
                                    isDirectory: false,
                                    size: file.size,
                                    modifiedTime: file.modifiedTime,
                                    isParent: false
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable {
            await loadDirectory()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let url = videoPlayerURL {
                VideoPlayerSheet(url: url)
            }
        }
        #endif
    }
    
    private var sortedFiles: [SFTPFileInfo] {
        files
            .filter { !$0.name.hasPrefix(".") }
            .sorted { file1, file2 in
                // Directories first if enabled
                if foldersFirst && file1.isDirectory != file2.isDirectory {
                    return file1.isDirectory
                }
                
                // Then sort by selected criteria
                switch sortBy {
                case "date":
                    return file1.modifiedTime > file2.modifiedTime
                case "size":
                    return file1.size > file2.size
                default: // "name"
                    return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
                }
            }
    }
    
    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let loadedFiles = try await sftpManager.listDirectory(
                server: server,
                remotePath: path,
                useTunnel: server.tunnelFilesOverSSH
            )
            files = loadedFiles
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func handleFileTap(_ file: SFTPFileInfo) {
        #if os(iOS)
        // Check if it's a video file
        if isVideoFile(file.name) {
            // Ensure stream server is started
            if !streamServer.isActive {
                Task {
                    do {
                        try await streamServer.startServer(for: server)
                        print("✓ Stream server started for video playback")
                        openVideoPlayer(file)
                    } catch {
                        print("❌ Failed to start stream server: \(error)")
                    }
                }
            } else {
                openVideoPlayer(file)
            }
        } else {
            // For non-video files, you could implement download or other actions
            print("📄 Tapped file: \(file.name)")
        }
        #endif
    }
    
    #if os(iOS)
    private func openVideoPlayer(_ file: SFTPFileInfo) {
        // Build relative path from sftpBase
        let sftpBase = server.sftpBase.isEmpty ? "/" : server.sftpBase
        var relativePath = path
        if path.hasPrefix(sftpBase) && sftpBase != "/" {
            relativePath = String(path.dropFirst(sftpBase.count))
        }
        if !relativePath.hasSuffix("/") {
            relativePath += "/"
        }
        relativePath += file.name
        
        // Get streaming URL
        if let streamURL = streamServer.getStreamURL(for: relativePath) {
            videoPlayerURL = streamURL
            showVideoPlayer = true
            print("🎬 Opening video player for: \(relativePath)")
        }
    }
    
    private func isVideoFile(_ name: String) -> Bool {
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ts"]
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
    #endif
}

// MARK: - File Row View

struct FileRowView: View {
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedTime: Int64
    let isParent: Bool
    @AppStorage("fileBrowserIconView") var icons: Bool = false
    
    var body: some View {
        if icons {
            VStack(spacing: 4) {
                fileIcon
                    .frame(width: 100, height: 100)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !isParent && !isDirectory {
                    Text(formattedInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        } else {
            HStack(spacing: 12) {
                // Icon
                fileIcon
                    .frame(width: 50, height: 50)
                
                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if !isParent && !isDirectory {
                        Text(formattedInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
    }
    
    @ViewBuilder
    private var fileIcon: some View {
        if isParent {
            Image("folder-parent")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if isDirectory {
            Image("folder")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fileTypeIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
    
    private var fileTypeIcon: Image {
        let ext = (name as NSString).pathExtension.lowercased()
        
        // Video files
        if ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v"].contains(ext) {
            return Image("file-video")
        }
        
        // Audio files
        if ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma"].contains(ext) {
            return Image("file-audio")
        }
        
        // Image files
        if ["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "heic"].contains(ext) {
            return Image("file-image")
        }
        
        // Archive files
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"].contains(ext) {
            return Image("file-archive")
        }
        
        // Default to document
        return Image("file-document")
    }
    
    private var formattedInfo: String {
        let date = Date(timeIntervalSince1970: TimeInterval(modifiedTime))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let dateString = dateFormatter.string(from: date)
        
        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        
        if icons {
            return "\(dateString)\n\(sizeString)"
        }
        return "\(dateString) - \(sizeString)"
    }
}
