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

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIImage
typealias PlatformImage = UIImage
#endif

/// Manages thumbnail generation for torrents via server-side ffmpeg
@MainActor
class TorrentThumbnailManager: ObservableObject {
    static let shared = TorrentThumbnailManager()
    
    @Published private(set) var thumbnails: [String: PlatformImage] = [:]
    @Published private(set) var isGenerating = false
    
    private let sshManager = SSHManager.shared
    private let cacheDirectory: URL
    
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
        
        // Check disk cache
        let cacheURL = cacheDirectory.appendingPathComponent("\(hash).jpg")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            #if os(macOS)
            if let image = NSImage(contentsOf: cacheURL) {
                thumbnails[hash] = image
                return image
            }
            #else
            if let data = try? Data(contentsOf: cacheURL),
               let image = UIImage(data: data) {
                thumbnails[hash] = image
                return image
            }
            #endif
        }
        
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
        defer { isGenerating = false }
        
        print("🎬 Generating \(torrentsNeedingThumbs.count) thumbnails...")
        
        // Run generation in background task
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.generateThumbnailsBatch(
                    torrents: torrentsNeedingThumbs,
                    server: server,
                    downloadDir: downloadDir
                )
            } catch {
                print("❌ Thumbnail generation failed: \(error)")
            }
        }.value
    }
    
    // MARK: - Private Methods
    
    private func generateThumbnailsBatch(torrents: [Torrent], server: Servers, downloadDir: String) async throws {
        // Step 1: Build list of media files for each torrent
        var torrentFiles: [(hash: String, filePath: String)] = []
        
        for torrent in torrents {
            guard let hash = torrent.hash,
                  let name = torrent.name else { continue }
            
            // Determine if single-file or multi-file torrent
            let torrentPath = "\(downloadDir)/\(name)"
            
            // Find first media file using SSH find command
            let findCommand = """
            if [ -f "\(torrentPath)" ]; then
                echo "\(torrentPath)"
            else
                find "\(torrentPath)" -type f \\( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \\) -print -quit 2>/dev/null
            fi
            """
            
            do {
                let output = try await sshManager.executeCommand(server: server, command: findCommand, timeout: 10)
                let filePath = output.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !filePath.isEmpty {
                    torrentFiles.append((hash: hash, filePath: filePath))
                }
            } catch {
                print("⚠️ Could not find media file for \(name): \(error)")
                continue
            }
        }
        
        guard !torrentFiles.isEmpty else {
            print("⚠️ No media files found for thumbnails")
            return
        }
        
        print("📁 Found \(torrentFiles.count) media files")
        
        // Step 2: Create .thumbs directory and generate all thumbnails in parallel
        let thumbsDir = "\(downloadDir)/.thumbs"
        let setupCommand = "mkdir -p \(thumbsDir)"
        try await sshManager.executeCommand(server: server, command: setupCommand, timeout: 5)
        
        // Build parallel ffmpeg command
        var ffmpegCommands: [String] = []
        for (hash, filePath) in torrentFiles {
            let escapedPath = shellEscape(filePath)
            let thumbPath = "\(thumbsDir)/\(hash).jpg"
            let ffmpegCmd = "~/.throttle3/bin/ffmpeg -ss 00:00:02 -i \(escapedPath) -vframes 1 -vf scale=300:-1 -q:v 3 \(thumbPath) 2>/dev/null || true"
            ffmpegCommands.append(ffmpegCmd + " &")
        }
        
        ffmpegCommands.append("wait") // Wait for all background jobs
        
        let parallelCommand = ffmpegCommands.joined(separator: " \n")
        
        print("🎬 Running ffmpeg for \(torrentFiles.count) files...")
        try await sshManager.executeCommand(server: server, command: parallelCommand, timeout: 60)
        
        // Step 3: Download thumbnails via dufs HTTP
        await downloadThumbnailsViaHTTP(hashes: torrentFiles.map { $0.hash }, server: server)
        
        print("✅ Thumbnail generation complete")
    }
    
    private func downloadThumbnailsViaHTTP(hashes: [String], server: Servers) async {
        // Determine dufs URL
        let scheme = "http" // dufs typically runs on http
        var host: String
        var port: Int
        
        if server.serveFilesOverTunnels {
            // Using SSH tunnel for file server
            host = "127.0.0.1"
            port = 8081 // Default file server tunnel port (adjust based on ConnectionManager)
        } else if server.useTailscale {
            // Direct via Tailscale
            host = server.serverAddress
            port = 5000 // Default dufs port
        } else {
            // Direct connection
            host = server.serverAddress
            port = 5000
        }
        
        for hash in hashes {
            let urlString = "\(scheme)://\(host):\(port)/.thumbs/\(hash).jpg"
            guard let url = URL(string: urlString) else { continue }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("⚠️ Failed to download thumbnail for \(hash): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    continue
                }
                
                // Save to disk cache
                let cacheURL = cacheDirectory.appendingPathComponent("\(hash).jpg")
                try data.write(to: cacheURL)
                
                // Load into memory cache
                await MainActor.run {
                    #if os(macOS)
                    if let image = NSImage(data: data) {
                        self.thumbnails[hash] = image
                    }
                    #else
                    if let image = UIImage(data: data) {
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
