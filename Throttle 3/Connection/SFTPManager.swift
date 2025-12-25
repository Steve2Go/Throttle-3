//
//  SFTPManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import mft
import KeychainAccess

enum SFTPError: LocalizedError {
    case noPassword
    case noSSHKey
    case connectionFailed(String)
    case authenticationFailed
    case operationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noPassword:
            return "No password found in keychain"
        case .noSSHKey:
            return "No SSH key found in keychain"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        }
    }
}

@MainActor
class SFTPManager: ObservableObject {
    static let shared = SFTPManager()
    
    private let keychain = Keychain(service: "com.srgim.throttle3")
    
    @Published var isConnected = false
    @Published var currentConnection: MFTSftpConnection?
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Simple API: Connect, Execute, Disconnect
    
    /// Execute an SFTP operation with automatic connect/disconnect
    /// - Parameters:
    ///   - server: The server configuration
    ///   - operation: The async operation to perform with the connection
    /// - Returns: The result of the operation
    func withConnection<T>(
        server: Servers,
        operation: @escaping (MFTSftpConnection) async throws -> T
    ) async throws -> T {
        let connection = try await connect(to: server)
        
        defer {
            disconnect(connection)
        }
        
        return try await operation(connection)
    }
    
    /// Execute a shell command via SSH exec
    /// - Parameters:
    ///   - server: The server configuration
    ///   - command: The command to execute
    /// - Returns: The command output
    func executeCommand(
        server: Servers,
        command: String
    ) async throws -> String {
        // Note: MFT framework doesn't expose SSH exec in the interface we saw
        // This would require using SshLib_macOS instead
        // For now, throw an error indicating this needs implementation
        throw SFTPError.operationFailed("SSH exec not implemented - use SshLib_macOS for command execution")
    }
    
    // MARK: - Connection Management
    
    /// Connect to an SFTP server
    /// - Parameter server: The server configuration
    /// - Returns: An active SFTP connection
    func connect(to server: Servers) async throws -> MFTSftpConnection {
        let connection: MFTSftpConnection
        
        // Determine port from server config (default to 22 for SSH/SFTP)
        let basePort = Int(server.sshPort) ?? 22
        
        // Determine hostname and port: use localhost with high port if Tailscale is enabled
        let hostname: String
        let port: Int
        
        if server.useTailscale {
            hostname = "localhost"
            // Use high port: 80 + sshPort (e.g., 22 -> 8022)
            port = Int("80\(server.sshPort)") ?? (8000 + basePort)
        } else {
            hostname = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
            port = basePort
        }
        
        // Get credentials from keychain
        if server.sshUsesKey {
            // Use SSH key authentication
            guard let privateKey = keychain["\(server.id.uuidString)-ssh-key"] else {
                throw SFTPError.noSSHKey
            }
            
            let passphrase = keychain["\(server.id.uuidString)-ssh-passphrase"] ?? ""
            
            connection = MFTSftpConnection(
                hostname: hostname,
                port: port,
                username: server.sshUser,
                prvKey: privateKey,
                passphrase: passphrase
            )
        } else {
            // Use password authentication
            guard let password = keychain["\(server.id.uuidString)-ssh-password"] else {
                throw SFTPError.noPassword
            }
            
            connection = MFTSftpConnection(
                hostname: hostname,
                port: port,
                username: server.sshUser,
                password: password
            )
        }
        
        // Attempt connection
        do {
            try connection.connect()
            try connection.authenticate()
            
            isConnected = true
            currentConnection = connection
            errorMessage = nil
            
            return connection
            
        } catch {
            isConnected = false
            throw SFTPError.connectionFailed(error.localizedDescription)
        }
    }
    
    /// Disconnect from the SFTP server
    /// - Parameter connection: The connection to disconnect (optional, uses current if nil)
    func disconnect(_ connection: MFTSftpConnection? = nil) {
        let conn = connection ?? currentConnection
        conn?.disconnect()
        
        if connection == nil || connection === currentConnection {
            isConnected = false
            currentConnection = nil
        }
    }
    
    // MARK: - Common SFTP Operations
    
    /// List directory contents
    func listDirectory(
        server: Servers,
        path: String,
        maxItems: Int64 = 10000
    ) async throws -> [MFTSftpItem] {
        try await withConnection(server: server) { connection in
            try connection.contentsOfDirectory(atPath: path, maxItems: maxItems)
        }
    }
    
    /// Get file info
    func fileInfo(
        server: Servers,
        path: String
    ) async throws -> MFTSftpItem {
        try await withConnection(server: server) { connection in
            try connection.infoForFile(atPath: path)
        }
    }
    
    /// Download a file
    func downloadFile(
        server: Servers,
        remotePath: String,
        localPath: String,
        progress: ((UInt64, UInt64) -> Bool)? = nil
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.downloadFile(
                atPath: remotePath,
                toFileAtPath: localPath,
                progress: progress
            )
        }
    }
    
    /// Upload a file
    func uploadFile(
        server: Servers,
        localPath: String,
        remotePath: String,
        progress: ((UInt64) -> Bool)? = nil
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.uploadFile(
                atPath: localPath,
                toFileAtPath: remotePath,
                progress: progress
            )
        }
    }
    
    /// Create a directory
    func createDirectory(
        server: Servers,
        path: String
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.createDirectory(atPath: path)
        }
    }
    
    /// Delete a file
    func deleteFile(
        server: Servers,
        path: String
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.removeFile(atPath: path)
        }
    }
    
    /// Delete a directory
    func deleteDirectory(
        server: Servers,
        path: String
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.removeDirectory(atPath: path)
        }
    }
    
    /// Move/rename a file or directory
    func moveItem(
        server: Servers,
        fromPath: String,
        toPath: String
    ) async throws {
        try await withConnection(server: server) { connection in
            try connection.moveItem(atPath: fromPath, toPath: toPath)
        }
    }
    
    /// Get filesystem statistics
    func filesystemStats(
        server: Servers,
        path: String = "/"
    ) async throws -> MFTFilesystemStats {
        try await withConnection(server: server) { connection in
            try connection.filesystemStats(forPath: path)
        }
    }
    
    /// Get connection information
    func connectionInfo(
        server: Servers
    ) async throws -> MFTSftpConnectionInfo {
        try await withConnection(server: server) { connection in
            try connection.connectionInfo()
        }
    }
}


