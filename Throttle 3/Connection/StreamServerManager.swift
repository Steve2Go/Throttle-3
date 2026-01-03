//
//  StreamServerManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 03/01/2026.
//

import Foundation
import SwiftUI
import Combine
import KeychainAccess
#if os(iOS)
import SshLib_iOS
import TailscaleKit
#endif

enum StreamServerError: LocalizedError {
    case invalidProxyAddress
    case credentialsNotFound
    case serverStartFailed(String)
    case serverStopFailed(String)
    case onlyiOSSupported
    
    var errorDescription: String? {
        switch self {
        case .invalidProxyAddress:
            return "Invalid SOCKS5 proxy address"
        case .credentialsNotFound:
            return "SSH credentials not found in keychain"
        case .serverStartFailed(let message):
            return "Failed to start stream server: \(message)"
        case .serverStopFailed(let message):
            return "Failed to stop stream server: \(message)"
        case .onlyiOSSupported:
            return "Stream server is only supported on iOS"
        }
    }
}

struct StreamServerConfig {
    let server: Servers
    let localAddress: String  // e.g., "localhost:8080" or ":8080"
    let basePath: String       // Remote base path for video files
}

struct StreamServerState {
    var isActive: Bool = false
    var isStarting: Bool = false
    var localAddress: String?
    var basePath: String?
    var errorMessage: String?
    var config: StreamServerConfig?
}

@MainActor
class StreamServerManager: ObservableObject {
    static let shared = StreamServerManager()
    
    @Published var serverState = StreamServerState()
    @Published var isStarting: Bool = false
    
    private let tailscaleManager = TailscaleManager.shared
    private let keychain = Keychain(service: "com.srgim.throttle3")
    
    // Convenience computed properties
    var isActive: Bool { serverState.isActive }
    var errorMessage: String? { serverState.errorMessage }
    var localPort: Int? {
        guard let address = serverState.localAddress,
              let portString = address.split(separator: ":").last,
              let port = Int(portString) else {
            return nil
        }
        return port
    }
    
    private init() {}
    
    // MARK: - Public Interface
    
    #if os(iOS)
    /// Start the HTTP stream server for the given server configuration
    /// If a server is already running with different config, it will be stopped and restarted
    func startServer(config: StreamServerConfig) async throws {
        // Don't restart if already starting
        guard !serverState.isStarting else {
            print("⚠️ Stream server is already starting")
            return
        }
        
        // If already active, check if it's the same configuration
        if serverState.isActive {
            // Check if configuration is different
            let isSameServer = serverState.config?.server.id == config.server.id
            let isSameAddress = serverState.localAddress == config.localAddress
            let isSamePath = serverState.basePath == config.basePath
            
            if isSameServer && isSameAddress && isSamePath {
                print("ℹ️ Stream server already running with same configuration")
                return
            }
            
            // Different config - stop the current server first
            print("🔄 Stopping current stream server to start with new configuration...")
            try stopServer()
        }
        
        serverState.isStarting = true
        serverState.errorMessage = nil
        serverState.config = config
        isStarting = true
        
        do {
            // Load credentials
            let credentials = try loadCredentials(for: config.server)
            
            // Get connection parameters
            let (sshHost, socks5Address, socks5ProxyAuth) = try await getConnectionParams(server: config.server)
            
            // Start the HTTP stream server
            var error: NSError?
            let success = SshlibStartHTTPStreamServer(
                config.localAddress,
                config.basePath,
                sshHost,
                socks5Address,
                socks5ProxyAuth,
                config.server.sshUser,
                credentials.password,
                credentials.privateKey,
                &error
            )
            
            if let error = error {
                throw StreamServerError.serverStartFailed(error.localizedDescription)
            }
            
            if !success {
                throw StreamServerError.serverStartFailed("Unknown error")
            }
            
            // Mark as active
            serverState.isActive = true
            serverState.isStarting = false
            serverState.localAddress = config.localAddress
            serverState.basePath = config.basePath
            isStarting = false
            
            print("✓ HTTP Stream Server started on \(config.localAddress)")
            print("  Base path: \(config.basePath)")
            print("  SSH host: \(sshHost)")
            
        } catch {
            serverState.isStarting = false
            serverState.isActive = false
            serverState.errorMessage = error.localizedDescription
            isStarting = false
            
            print("❌ Stream server failed to start: \(error)")
            throw error
        }
    }
    
    /// Stop the HTTP stream server
    func stopServer() throws {
        guard serverState.isActive else {
            print("⚠️ Stream server is not active")
            return
        }
        
        var error: NSError?
        let success = SshlibStopHTTPStreamServer(&error)
        
        if let error = error {
            throw StreamServerError.serverStopFailed(error.localizedDescription)
        }
        
        if !success {
            throw StreamServerError.serverStopFailed("Unknown error")
        }
        
        // Clear state
        serverState.isActive = false
        serverState.isStarting = false
        serverState.localAddress = nil
        serverState.basePath = nil
        serverState.errorMessage = nil
        serverState.config = nil
        
        print("✓ HTTP Stream Server stopped")
    }
    
    /// Convenience method to start server with default settings from Server object
    func startServer(for server: Servers, localPort: Int = 8080) async throws {
        let localAddress = "localhost:\(localPort)"
        let basePath = server.sftpBase.isEmpty ? "/" : server.sftpBase
        
        let config = StreamServerConfig(
            server: server,
            localAddress: localAddress,
            basePath: basePath
        )
        
        try await startServer(config: config)
    }
    
    /// Get the URL to access files through the stream server
    func getStreamURL(for relativePath: String) -> URL? {
        guard isActive,
              let localAddress = serverState.localAddress else {
            return nil
        }
        
        // Remove leading slash from relative path if present
        let cleanPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        
        // Build URL: http://localhost:8080/path/to/file.mp4
        return URL(string: "http://\(localAddress)/\(cleanPath)")
    }
    
    /// Check if the stream server is actually responding to requests
    func isServerResponding() async -> Bool {
        guard isActive,
              let localAddress = serverState.localAddress else {
            return false
        }
        
        // Try a simple HEAD request to test if server is alive
        guard let url = URL(string: "http://\(localAddress)/") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // Any response (even 404) means server is up
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCredentials(for server: Servers) throws -> (password: String?, privateKey: String?) {
        if server.sshUsesKey {
            guard let privateKey = try? keychain.getString("\(server.id.uuidString)-sshkey") else {
                throw StreamServerError.credentialsNotFound
            }
            return (password: nil, privateKey: privateKey)
        } else {
            guard let password = try? keychain.getString("\(server.id.uuidString)-sshpassword") else {
                throw StreamServerError.credentialsNotFound
            }
            return (password: password, privateKey: nil)
        }
    }
    
    private func getConnectionParams(server: Servers) async throws -> (sshHost: String, socks5Address: String, socks5ProxyAuth: String) {
        // Use serverAddress as fallback if sshHost is empty (same as SFTPManager logic)
        let host = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
        let port = server.sshPort
        
        if server.useTailscale {
            // Use Tailscale connection
            guard let proxyConfig = tailscaleManager.proxyConfig,
                  let proxyPort = proxyConfig.port else {
                throw StreamServerError.invalidProxyAddress
            }
            
            let sshHost = "\(host):\(port)"
            let socks5Address = "127.0.0.1:\(proxyPort)"
            let socks5ProxyAuth = "tsnet:\(proxyConfig.proxyCredential)"
            
            print("📡 Using Tailscale proxy: \(socks5Address) with auth")
            return (sshHost, socks5Address, socks5ProxyAuth)
        } else {
            // Direct connection
            let sshHost = "\(host):\(port)"
            return (sshHost, "", "")
        }
    }
    
    #else
    // macOS stubs - this feature is iOS only
    func startServer(config: StreamServerConfig) async throws {
        throw StreamServerError.onlyiOSSupported
    }
    
    func stopServer() throws {
        throw StreamServerError.onlyiOSSupported
    }
    
    func startServer(for server: Servers, localPort: Int = 8080) async throws {
        throw StreamServerError.onlyiOSSupported
    }
    
    func getStreamURL(for relativePath: String) -> URL? {
        return nil
    }
    #endif
}
