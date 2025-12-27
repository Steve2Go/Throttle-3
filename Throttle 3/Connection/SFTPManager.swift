//
//  SFTPManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 26/12/2025.
//

import Foundation
import KeychainAccess
#if os(macOS)
import SshLib_macOS
#else
import SshLib_iOS
import TailscaleKit
#endif

/// FileInfo represents remote file metadata
struct SFTPFileInfo: Codable, Identifiable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let modifiedTime: Int64 // Unix timestamp
    let permissions: String
    
    var id: String { name }
    var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modifiedTime)) }
}

/// SFTPManager provides SFTP file operations using the SshLib framework
@MainActor
class SFTPManager {
    static let shared = SFTPManager()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// List files in a remote directory
    func listDirectory(
        server: Servers,
        remotePath: String,
        useTunnel: Bool = false
    ) async throws -> [SFTPFileInfo] {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let jsonString = SshlibSftpListDirectory(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            remotePath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            throw SFTPError.invalidResponse
        }
        
        let files = try JSONDecoder().decode([SFTPFileInfo].self, from: data)
        return files
    }
    
    /// Download a file from remote to local path
    func downloadFile(
        server: Servers,
        remotePath: String,
        localPath: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let success = SshlibSftpDownloadFile(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            remotePath,
            localPath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        if !success {
            throw SFTPError.operationFailed("Download failed")
        }
    }
    
    /// Upload a file from local to remote path
    func uploadFile(
        server: Servers,
        localPath: String,
        remotePath: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let success = SshlibSftpUploadFile(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            localPath,
            remotePath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        if !success {
            throw SFTPError.operationFailed("Upload failed")
        }
    }
    
    /// Delete a remote file
    func deleteFile(
        server: Servers,
        remotePath: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let success = SshlibSftpDeleteFile(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            remotePath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        if !success {
            throw SFTPError.operationFailed("Delete failed")
        }
    }
    
    /// Create a remote directory (recursively)
    func makeDirectory(
        server: Servers,
        remotePath: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let success = SshlibSftpMakeDirectory(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            remotePath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        if !success {
            throw SFTPError.operationFailed("Create directory failed")
        }
    }
    
    /// Get file info for a remote path
    func stat(
        server: Servers,
        remotePath: String,
        useTunnel: Bool = false
    ) async throws -> SFTPFileInfo {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let jsonString = SshlibSftpStat(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            remotePath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            throw SFTPError.invalidResponse
        }
        
        let fileInfo = try JSONDecoder().decode(SFTPFileInfo.self, from: data)
        return fileInfo
    }
    
    /// Rename or move a remote file/directory
    func rename(
        server: Servers,
        oldPath: String,
        newPath: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: server, useTunnel: useTunnel)
        
        var error: NSError?
        let success = SshlibSftpRename(
            sshHost,
            socks5Address,
            socks5ProxyAuth,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            oldPath,
            newPath,
            &error
        )
        
        if let error = error {
            throw SFTPError.operationFailed(error.localizedDescription)
        }
        
        if !success {
            throw SFTPError.operationFailed("Rename failed")
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCredentials(for server: Servers) throws -> (password: String, privateKey: String) {
        if server.sshUsesKey {
            guard let privateKey = try? Keychain(service: "com.srgim.throttle3")
                .getString("\(server.id.uuidString)-sshkey") else {
                throw SFTPError.missingCredentials
            }
            return (password: "", privateKey: privateKey)
        } else {
            guard let password = try? Keychain(service: "com.srgim.throttle3")
                .getString("\(server.id.uuidString)-sshpassword") else {
                throw SFTPError.missingCredentials
            }
            return (password: password, privateKey: "")
        }
    }
    
    private func getConnectionParams(
        server: Servers,
        useTunnel: Bool
    ) async throws -> (sshHost: String, socks5Address: String, socks5ProxyAuth: String) {
        // Use serverAddress as fallback if sshHost is empty (same as tunnel logic)
        let host = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
        let port = server.sshPort
        
        #if os(iOS)
        // iOS: Use Tailscale's SOCKS5 proxy when enabled
        if server.useTailscale {
            let tsManager = TailscaleManager.shared
            guard tsManager.isConnected else {
                throw SFTPError.tailscaleNotAvailable
            }
            
            // Get SOCKS5 proxy config from TailscaleManager
            guard let proxyConfig = tsManager.proxyConfig,
                  let proxyPort = proxyConfig.port else {
                throw SFTPError.tailscaleNotAvailable
            }
            
            // Separate parameters: address and auth
            let socks5Address = "127.0.0.1:\(proxyPort)"
            let socks5ProxyAuth = "tsnet:\(proxyConfig.proxyCredential)"
            let sshHost = "\(host):\(port)"
            return (sshHost, socks5Address, socks5ProxyAuth)
        } else {
            // Direct connection on iOS (if server is directly reachable)
            let sshHost = "\(host):\(port)"
            return (sshHost, "", "")
        }
        #else
        // macOS: Direct connection (Tailscale works at system level)
        let sshHost = "\(host):\(port)"
        return (sshHost, "", "")
        #endif
    }
}

// MARK: - Errors

enum SFTPError: LocalizedError {
    case missingCredentials
    case tailscaleNotAvailable
    case operationFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "SSH credentials not found in keychain"
        case .tailscaleNotAvailable:
            return "Tailscale SOCKS5 proxy not available"
        case .operationFailed(let message):
            return "SFTP operation failed: \(message)"
        case .invalidResponse:
            return "Invalid response from SFTP server"
        }
    }
}

