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
    
    @State private var currentPath: String
    @State private var files: [SFTPFileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationPath: [String] = []
    
    private let sftpManager = SFTPManager.shared
    
    init(server: Servers) {
        self.server = server
        // Start at sftpBase if set, otherwise root
        _currentPath = State(initialValue: server.sftpBase.isEmpty ? "/" : server.sftpBase)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDirectory()
            }
            .navigationDestination(for: String.self) { newPath in
                SubdirectoryView(
                    server: server,
                    currentPath: newPath,
                    sftpManager: sftpManager
                )
            }
        }
    }
    
    private var pathTitle: String {
        if currentPath == "/" {
            return server.name
        }
        return currentPath.split(separator: "/").last.map(String.init) ?? server.name
    }
    
    private var fileListView: some View {
        List {
            // Parent directory button if not at root
            if currentPath != "/" && currentPath != server.sftpBase {
                Button {
                    navigateUp()
                } label: {
                    FileRowView(
                        name: "..",
                        isDirectory: true,
                        size: 0,
                        isParent: true
                    )
                }
            }
            
            // Files and folders
            ForEach(sortedFiles) { file in
                if file.isDirectory {
                    Button {
                        navigateToFolder(file.name)
                    } label: {
                        FileRowView(
                            name: file.name,
                            isDirectory: true,
                            size: file.size,
                            isParent: false
                        )
                    }
                } else {
                    FileRowView(
                        name: file.name,
                        isDirectory: false,
                        size: file.size,
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
    
    private func navigateToFolder(_ folderName: String) {
        let newPath = currentPath.hasSuffix("/") 
            ? currentPath + folderName 
            : currentPath + "/" + folderName
        navigationPath.append(newPath)
    }
    
    private func navigateUp() {
        if navigationPath.isEmpty {
            // We're in the root view, go up one level
            currentPath = (currentPath as NSString).deletingLastPathComponent
            if currentPath.isEmpty {
                currentPath = "/"
            }
            Task {
                await loadDirectory()
            }
        } else {
            // Pop navigation stack
            navigationPath.removeLast()
        }
    }
    
    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let loadedFiles = try await sftpManager.listDirectory(
                server: server,
                remotePath: currentPath,
                useTunnel: server.tunnelFilesOverSSH
            )
            files = loadedFiles
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Subdirectory View

struct SubdirectoryView: View {
    let server: Servers
    let currentPath: String
    let sftpManager: SFTPManager
    
    @State private var files: [SFTPFileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
        .task {
            await loadDirectory()
        }
    }
    
    private var pathTitle: String {
        currentPath.split(separator: "/").last.map(String.init) ?? "Files"
    }
    
    private var fileListView: some View {
        List {
            ForEach(sortedFiles) { file in
                if file.isDirectory {
                    NavigationLink(value: currentPath.hasSuffix("/") ? currentPath + file.name : currentPath + "/" + file.name) {
                        FileRowView(
                            name: file.name,
                            isDirectory: true,
                            size: file.size,
                            isParent: false
                        )
                    }
                } else {
                    FileRowView(
                        name: file.name,
                        isDirectory: false,
                        size: file.size,
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
            if file1.isDirectory != file2.isDirectory {
                return file1.isDirectory
            }
            return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
        }
    }
    
    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let loadedFiles = try await sftpManager.listDirectory(
                server: server,
                remotePath: currentPath,
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
                    Text(formattedSize)
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
    
    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
