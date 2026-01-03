//
//  FileBrowser.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 03/01/2026.
//

import SwiftUI

struct FileBrowserView: View {
    let server: Servers
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem {
                    Button {
                        dismiss()
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
    @State private var files: [SFTPFileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let sftpManager = SFTPManager.shared
    
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
            ToolbarItem(placement: .navigationBarTrailing) {
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
                    
                    Button {
                        // TODO: Folders first toggle
                    } label: {
                        Label("Folders First", systemImage: "text.below.photo")
                    }
                    
                    Button {
                        // TODO: Icons view
                    } label: {
                        Label("Icons", systemImage: "square.grid.2x2")
                    }
                    
                    Button {
                        // TODO: List view
                    } label: {
                        Label("List", systemImage: "list.bullet")
                    }
                    
                    Button {
                        // TODO: Sort by name
                    } label: {
                        Label("Name", systemImage: "textformat")
                    }
                    
                    Button {
                        // TODO: Sort by date
                    } label: {
                        Label("Date", systemImage: "calendar")
                    }
                    
                    Button {
                        // TODO: Sort by size
                    } label: {
                        Label("Size", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            if !isRoot {
                ToolbarItem {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            await loadDirectory()
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
        .listStyle(.plain)
        .refreshable {
            await loadDirectory()
        }
    }
    
    private var sortedFiles: [SFTPFileInfo] {
        files.sorted { file1, file2 in
            // Directories first
            if file1.isDirectory != file2.isDirectory {
                return file1.isDirectory
            }
            // Then alphabetical
            return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
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
}

// MARK: - File Row View

struct FileRowView: View {
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedTime: Int64
    let isParent: Bool
    
    var body: some View {
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
        
        return "\(dateString) - \(sizeString)"
    }
}
