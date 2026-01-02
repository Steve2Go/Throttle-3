//
//  TorrentThumbnailManager.swift
//  Throttle 3
//
//  Created on 28/12/2025.
//

import Foundation
import SwiftUI
import Transmission
import CryptoKit
import Combine
import KeychainAccess

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
import TailscaleKit
#endif

/// Manages thumbnail generation for torrents via server-side ffmpeg
@MainActor
class TorrentThumbnailManager: ObservableObject {
    static let shared = TorrentThumbnailManager()
    
    @Published private(set) var thumbnails: [String: PlatformImage] = [:]
    @Published private(set) var isGenerating = false
    @Published private(set) var generatingHashes: Set<String> = []
    
    private let sshManager = SSHManager.shared
    private let sftpManager = SFTPManager.shared
    private let cacheDirectory: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Setup cache directory in app's cache folder
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("TorrentThumbnails", isDirectory: true)
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Interface
    
    /// Get thumbnail for a torrent, loading from cache or returning nil
    func getThumbnail(for torrent: Torrent) -> PlatformImage? {
        guard let hash = torrent.hash else { return nil }
        
        // Check in-memory cache
        if let thumbnail = thumbnails[hash] {
            return thumbnail
        }
        
        // Check disk cache for generated thumbnails
        let cacheURL = cacheDirectory.appendingPathComponent("\(hash).jpg")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            #if os(macOS)
            if let image = NSImage(contentsOf: cacheURL) {
                // Defer update to avoid publishing during view updates
                Task { @MainActor in
                    self.thumbnails[hash] = image
                }
                return image
            }
            #else
            if let data = try? Data(contentsOf: cacheURL),
               let image = UIImage(data: data) {
                // Defer update to avoid publishing during view updates
                Task { @MainActor in
                    self.thumbnails[hash] = image
                }
                return image
            }
            #endif
        }
        
        // Don't return asset icons here - let generation attempt first
        // Asset icons will only be used after generation determines it's non-media
        return nil
    }
    
    /// Generate thumbnails for visible torrents
    /// Call this from onAppear and after scroll stops (debounced)
    func generateThumbnails(for torrents: [Torrent], server: Servers, downloadDir: String) async {
        // Only run one generation at a time
        guard !isGenerating else { return }
        
        // Filter: only complete torrents without cached thumbnails
        let torrentsNeedingThumbs = torrents.filter { torrent in
            guard let progress = torrent.progress,
                  progress >= 1.0,
                  let hash = torrent.hash else {
                return false
            }
            return getThumbnail(for: torrent) == nil
        }
        
        guard !torrentsNeedingThumbs.isEmpty else { return }
        
        isGenerating = true
        // Add all hashes to generatingHashes
        let hashes = Set(torrentsNeedingThumbs.compactMap { $0.hash })
        generatingHashes.formUnion(hashes)
        defer { 
            isGenerating = false
            // Remove all hashes from generatingHashes
            generatingHashes.subtract(hashes)
        }
        
        print("🎬 Generating \(torrentsNeedingThumbs.count) thumbnails...")
        
        // Run generation directly (not detached) so UI updates happen in real-time
        do {
            try await generateThumbnailsBatch(
                torrents: torrentsNeedingThumbs,
                server: server,
                downloadDir: downloadDir
            )
        } catch {
            print("❌ Thumbnail generation failed: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func generateThumbnailsBatch(torrents: [Torrent], server: Servers, downloadDir: String) async throws {
        // Step 1: Get file info for all torrents in one RPC call
        guard let filesDict = await getAllTorrentFiles(torrents: torrents, server: server) else {
            print("⚠️ Failed to fetch torrent files")
            return
        }
        
        // Step 2: Find largest media file for each torrent, assign asset icons for non-media
        var videoFiles: [(hash: String, filePath: String)] = []
        var imageFiles: [(hash: String, filePath: String)] = []
        var nonMediaTorrents: [Torrent] = []
        
        for torrent in torrents {
            guard let hash = torrent.hash,
                  let id = torrent.id,
                  let files = filesDict[id] else { continue }
            
            // Use torrent's downloadPath if available, otherwise use provided downloadDir
            let basePath = torrent.downloadPath ?? downloadDir
            
            // Check for image first, then video
            if let largestImage = getLargestImageFile(from: files, basePath: basePath) {
                imageFiles.append((hash: hash, filePath: largestImage))
                print("🖼️ Found image for \(torrent.name ?? hash): \(largestImage)")
            } else if let largestVideo = getLargestVideoFile(from: files, basePath: basePath) {
                videoFiles.append((hash: hash, filePath: largestVideo))
                print("📹 Found video for \(torrent.name ?? hash): \(largestVideo)")
            } else {
                // Not a media torrent - assign appropriate file type icon
                print("📄 Non-media torrent \(torrent.name ?? hash), assigning file type icon")
                nonMediaTorrents.append(torrent)
                
                // Load asset icon immediately on main actor
                await MainActor.run {
                    let iconName = getFileTypeIconFromFiles(files: files)
                    #if os(macOS)
                    if let image = NSImage(named: iconName) {
                        self.thumbnails[hash] = image
                    }
                    #else
                    if let image = UIImage(named: iconName) {
                        self.thumbnails[hash] = image
                    }
                    #endif
                }
            }
        }
        
        guard !videoFiles.isEmpty || !imageFiles.isEmpty else {
            print("⚠️ No media files found for thumbnails")
            return
        }
        
        print("📁 Found \(videoFiles.count) videos and \(imageFiles.count) images")
        
        // Step 3: Handle images - download them directly instead of using ffmpeg
        if !imageFiles.isEmpty {
            print("🖼️ Downloading \(imageFiles.count) images directly...")
            await downloadImagesDirectly(imageFiles: imageFiles, server: server)
        }
        
        // If no videos to process, we're done
        guard !videoFiles.isEmpty else {
            print("✅ Image downloads complete")
            return
        }
        
        // Step 4: Create thumbnail directory in ~/.throttle3 and generate video thumbnails in parallel
        // For shell commands, use ~ which will be expanded by the shell
        let thumbsDirShell = "~/.throttle3/thumbnails"
        // For SFTP, we need the absolute path (SFTP doesn't expand ~)
        let homeDir = try await sshManager.executeCommand(server: server, command: "echo $HOME", timeout: 5).trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbsDirAbsolute = "\(homeDir)/.throttle3/thumbnails"
        
        let setupCommand = "mkdir -p \(thumbsDirShell)"
        try await sshManager.executeCommand(server: server, command: setupCommand, timeout: 5)
        
        // Build parallel ffmpeg command with proper error handling
        var ffmpegCommands: [String] = []
        for (hash, filePath) in videoFiles {
            let escapedPath = shellEscape(filePath)
            let thumbPath = "\(thumbsDirShell)/\(hash).jpg"
            // Remove error suppression to see actual failures, add success marker
            let ffmpegCmd = "~/.throttle3/bin/ffmpeg -y -ss 00:00:05 -i \(escapedPath) -vframes 1 -vf scale=300:-1 -q:v 3 \(thumbPath) && echo 'OK:\(hash)' || echo 'FAIL:\(hash)'"
            ffmpegCommands.append("(" + ffmpegCmd + ") &")
        }
        
        ffmpegCommands.append("wait") // Wait for all background jobs
        ffmpegCommands.append("echo 'DONE'") // Final marker
        
        let parallelCommand = ffmpegCommands.joined(separator: "\n")
        
        print("🎬 Running ffmpeg for \(videoFiles.count) files...")
        let output = try await sshManager.executeCommand(server: server, command: parallelCommand, timeout: 120)
        
        // Parse output to see which thumbnails actually succeeded
        let successHashes = output.components(separatedBy: "\n")
            .filter { $0.hasPrefix("OK:") }
            .map { String($0.dropFirst(3)) }
        
        let failedHashes = output.components(separatedBy: "\n")
            .filter { $0.hasPrefix("FAIL:") }
            .map { String($0.dropFirst(5)) }
        
        print("✅ Successfully generated \(successHashes.count) thumbnails")
        if !failedHashes.isEmpty {
            print("⚠️ Failed to generate \(failedHashes.count) thumbnails")
        }
        
        // Step 3: Download thumbnails via SFTP (only the successful ones)
        // Use absolute path for SFTP (it doesn't expand ~)
        await downloadThumbnailsViaSFTP(hashes: successHashes, server: server, thumbsDir: thumbsDirAbsolute)
        
        print("✅ Thumbnail generation complete")
    }
    
    private func downloadThumbnailsViaSFTP(hashes: [String], server: Servers, thumbsDir: String) async {
        for hash in hashes {
            let remotePath = "\(thumbsDir)/\(hash).jpg"
            let localURL = cacheDirectory.appendingPathComponent("\(hash).jpg")
            
            do {
                try await sftpManager.downloadFile(
                    server: server,
                    remotePath: remotePath,
                    localPath: localURL.path
                )
                
                // Load into memory cache immediately on main actor
                await MainActor.run {
                    #if os(macOS)
                    if let image = NSImage(contentsOf: localURL) {
                        self.thumbnails[hash] = image
                    }
                    #else
                    if let data = try? Data(contentsOf: localURL),
                       let image = UIImage(data: data) {
                        self.thumbnails[hash] = image
                    }
                    #endif
                }
                
                print("✓ Downloaded thumbnail for \(hash)")
            } catch {
                print("⚠️ Failed to download thumbnail for \(hash): \(error)")
            }
        }
    }
    
    /// Download images directly to use as thumbnails (no ffmpeg needed)
    private func downloadImagesDirectly(imageFiles: [(hash: String, filePath: String)], server: Servers) async {
        for (hash, remotePath) in imageFiles {
            let localURL = cacheDirectory.appendingPathComponent("\(hash).jpg")
            
            do {
                try await sftpManager.downloadFile(
                    server: server,
                    remotePath: remotePath,
                    localPath: localURL.path
                )
                
                // Load into memory cache immediately on main actor
                await MainActor.run {
                    #if os(macOS)
                    if let image = NSImage(contentsOf: localURL) {
                        self.thumbnails[hash] = image
                    }
                    #else
                    if let data = try? Data(contentsOf: localURL),
                       let image = UIImage(data: data) {
                        self.thumbnails[hash] = image
                    }
                    #endif
                }
                
                print("✓ Downloaded image for \(hash)")
            } catch {
                print("⚠️ Failed to download image for \(hash): \(error)")
            }
        }
    }
    
    /// Get files for all torrents in one batch RPC call
    private func getAllTorrentFiles(torrents: [Torrent], server: Servers) async -> [Int: [TorrentFile]]? {
        guard let client = await createTransmissionClient(server: server) else {
            return nil
        }
        
        let torrentIds = torrents.compactMap { $0.id }
        guard !torrentIds.isEmpty else { return [:] }
        
        // Create custom batch request for multiple torrents
        let batchRequest = Request<[Int: [TorrentFile]]>(
            method: "torrent-get",
            args: ["ids": torrentIds, "fields": ["id", "files", "fileStats"]],
            transform: { response -> Result<[Int: [TorrentFile]], TransmissionError> in
                guard let arguments = response["arguments"] as? [String: Any],
                      let torrents = arguments["torrents"] as? [[String: Any]]
                else {
                    return .failure(.unexpectedResponse)
                }
                
                var result: [Int: [TorrentFile]] = [:]
                
                for torrentDict in torrents {
                    guard let id = torrentDict["id"] as? Int,
                          let filesDict = torrentDict["files"] as? [[String: Any]],
                          let statsDict = torrentDict["fileStats"] as? [[String: Any]]
                    else {
                        continue
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
                    
                    result[id] = files
                }
                
                return .success(result)
            }
        )
        
        return await withCheckedContinuation { continuation in
            client.request(batchRequest)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("⚠️ Failed to fetch files for torrents: \(error)")
                            continuation.resume(returning: nil)
                        }
                    },
                    receiveValue: { (filesDict: [Int: [TorrentFile]]) in
                        print("✅ Fetched files for \(filesDict.count) torrents")
                        continuation.resume(returning: filesDict)
                    }
                )
                .store(in: &self.cancellables)
        }
    }
    
    /// Get the largest video file from a list of files
    private func getLargestVideoFile(from files: [TorrentFile], basePath: String) -> String? {
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ts", "m2ts"]
        
        // Filter for video files
        let videoFiles = files.filter { file in
            let ext = (file.name as NSString).pathExtension.lowercased()
            return videoExtensions.contains(ext)
        }
        
        // Get the largest video file
        guard let largestFile = videoFiles.max(by: { $0.size < $1.size }) else {
            return nil
        }
        
        return "\(basePath)/\(largestFile.name)"
    }
    
    /// Get the largest image file from a list of files
    private func getLargestImageFile(from files: [TorrentFile], basePath: String) -> String? {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "ico"]
        
        // Filter for image files
        let imageFiles = files.filter { file in
            let ext = (file.name as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }
        
        // Get the largest image file
        guard let largestFile = imageFiles.max(by: { $0.size < $1.size }) else {
            return nil
        }
        
        return "\(basePath)/\(largestFile.name)"
    }
    
    /// Get file type icon name from torrent info
    private func getFileTypeIcon(for torrent: Torrent) -> String? {
        // Check if torrent name indicates a folder
        if let name = torrent.name {
            let ext = (name as NSString).pathExtension.lowercased()
            return getIconForExtension(ext)
        }
        return "file-document" // Default fallback
    }
    
    /// Get file type icon from file list
    private func getFileTypeIconFromFiles(files: [TorrentFile]) -> String {
        // Check the largest file to determine type
        guard let largestFile = files.max(by: { $0.size < $1.size }) else {
            return "file-document"
        }
        
        let ext = (largestFile.name as NSString).pathExtension.lowercased()
        return getIconForExtension(ext)
    }
    
    /// Map file extension to asset icon name
    private func getIconForExtension(_ ext: String) -> String {
        let audioExtensions = ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma", "aiff"]
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ts", "m2ts"]
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp", "ico"]
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "dmg"]
        
        if audioExtensions.contains(ext) {
            return "file-audio"
        } else if videoExtensions.contains(ext) {
            return "file-video"
        } else if imageExtensions.contains(ext) {
            return "file-image"
        } else if archiveExtensions.contains(ext) {
            return "file-archive"
        } else if ext.isEmpty {
            return "folder" // No extension likely means it's a folder
        } else {
            return "file-document" // Default fallback
        }
    }
    
    /// Create a Transmission client for the given server
    private func createTransmissionClient(server: Servers) async -> Transmission? {
        let keychain = Keychain(service: "com.srgim.throttle3")
        
        // Build Transmission URL
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
            print("❌ Invalid Transmission URL: \(urlString)")
            return nil
        }
        
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        // Create Transmission client with SOCKS5 proxy support on iOS with Tailscale
        #if os(iOS)
        if server.useTailscale, let node = TailscaleManager.shared.node {
            do {
                let config = URLSessionConfiguration.default
                let _ = try await config.proxyVia(node)
                let customSession = URLSession(configuration: config)
                return Transmission(baseURL: url, username: server.user, password: password, session: customSession)
            } catch {
                print("⚠️ Failed to configure Tailscale proxy: \(error), using default session")
                return Transmission(baseURL: url, username: server.user, password: password)
            }
        } else {
            return Transmission(baseURL: url, username: server.user, password: password)
        }
        #else
        return Transmission(baseURL: url, username: server.user, password: password)
        #endif
    }
    
    /// Escape shell arguments to prevent injection
    private func shellEscape(_ str: String) -> String {
        return "'\(str.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    
    /// Clear all cached thumbnails
    func clearCache() {
        thumbnails.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
