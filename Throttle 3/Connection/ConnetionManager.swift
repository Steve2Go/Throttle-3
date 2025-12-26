//
//  ConnetionManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftUI
import Combine
import KeychainAccess

//1 - Tailscale if set, or tunnel()

//2 Tunnels up - Http if set, plus one for the sftp, and one for the file server.

//traverse using ssh exec and install / start dufs if needed

//3 Start queue

@MainActor
class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    @Published var isConnecting: Bool = false
    @Published var isConnected: Bool = false
    @Published var errorMessage: String?
    
    private let tailscaleManager = TailscaleManager.shared
    private let tunnelManager = TunnelManager.shared
    private let keychain = Keychain(service: "com.srgim.throttle3")
    
    private init() {}
    
    // MARK: - Credential Loading
    
    private func loadCredentials(for server: Servers) -> SSHCredentials {
        if server.sshUsesKey {
            let privateKey = keychain["\(server.id.uuidString)-sshkey"] ?? ""
            return SSHCredentials(
                username: server.sshUser,
                password: nil,
                privateKey: privateKey
            )
        } else {
            let password = keychain["\(server.id.uuidString)-sshpassword"] ?? ""
            return SSHCredentials(
                username: server.sshUser,
                password: password,
                privateKey: nil
            )
        }
    }
    
    // MARK: - Public Interface
    
    /// Connect tunnels for a server configuration
    /// This handles Tailscale waiting and establishes all necessary SSH tunnels
    func connect(server: Servers) async {
        guard !isConnecting else { return }
        
        isConnecting = true
        
        errorMessage = nil
        
        print("🔌 ConnectionManager: Starting connection for server '\(server.name)'")
        
        // Give SwiftUI time to render the connecting state
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Start both tunnels concurrently - they run on background threads
        async let webTunnelResult: Void = server.tunnelWebOverSSH ? startWebTunnel(server: server) : ()
        async let fileServerResult: Void = server.serveFilesOverTunnels ? startFileServerTunnel(server: server) : ()
        
        // Wait for both to be initiated (not connected yet)
        _ = await (webTunnelResult, fileServerResult)
        
        // Monitor tunnel states by checking port connectivity
        var expectedTunnels: [String] = []
        if server.tunnelWebOverSSH { expectedTunnels.append("web") }
        if server.serveFilesOverTunnels { expectedTunnels.append("fileserver") }
        
        // Wait for tunnels to become active (check port connectivity)
        var attempts = 0
        let maxAttempts = 40 // 40 * 500ms = 20 seconds max
        
        while attempts < maxAttempts {
            var allActive = true
            
            for tunnelId in expectedTunnels {
                if await tunnelManager.checkTunnelConnectivity(id: tunnelId) {
                    // Mark as active if not already
                    if tunnelManager.getTunnelState(id: tunnelId)?.isActive != true {
                        tunnelManager.markTunnelActive(id: tunnelId)
                    }
                } else {
                    allActive = false
                }
            }
            
            if allActive {
                isConnected = true
                isConnecting = false
                print("✓ ConnectionManager: All tunnels are active and ports are listening")
                return
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            attempts += 1
        }
        
        // Timeout - tunnels didn't all become active
        isConnecting = false
        isConnected = false
        print("⚠️ ConnectionManager: Timeout - not all tunnel ports are listening")
    }
    
    /// Disconnect all tunnels
    func disconnect() {
        tunnelManager.stopAllTunnels()
        isConnected = false
        print("✓ ConnectionManager: All tunnels disconnected")
    }
    
    // MARK: - Private Methods
    
    private func startWebTunnel(server: Servers) async {
        let credentials = loadCredentials(for: server)
        
        // Use port + 8000 for local web tunnel (e.g., 80 -> 8080, 9091 -> 17091)
        let localWebPort = (Int(server.serverPort) ?? 80) + 8000
        
        let config = SSHTunnelConfig(
            sshHost: server.sshHost.isEmpty ? server.serverAddress : server.sshHost,
            sshPort: Int(server.sshPort) ?? 22,
            remoteAddress: "127.0.0.1:\(server.serverPort)",
            localAddress: "127.0.0.1:\(localWebPort)",
            credentials: credentials,
            useTailscale: server.useTailscale
        )
        
        await tunnelManager.startTunnel(id: "web", config: config)
        
        if let state = tunnelManager.getTunnelState(id: "web"), state.isActive {
            print("✓ Web tunnel connected on port \(state.localPort ?? 0)")
        } else if let state = tunnelManager.getTunnelState(id: "web"), let error = state.errorMessage {
            print("❌ Web tunnel failed: \(error)")
        }
    }
    
    private func startFileServerTunnel(server: Servers) async {

        
        print("🔧 Starting file server tunnel...")
        
        let credentials = loadCredentials(for: server)
        

        // Use port + 18000 for file server local (e.g., 80 -> 18080, 9091 -> 27091)
        let localFileServerPort = (Int(server.serverPort) ?? 80) + 18000
        // File server typically runs on different port on remote, use port + 10000
        let remoteFileServerPort = (Int(server.serverPort) ?? 80) + 10000
        
        let config = SSHTunnelConfig(
            sshHost: server.sshHost.isEmpty ? server.serverAddress : server.sshHost,
            sshPort: Int(server.sshPort) ?? 22,
            remoteAddress: "127.0.0.1:\(remoteFileServerPort)",
            localAddress: "127.0.0.1:\(localFileServerPort)",
            credentials: credentials,
            useTailscale: server.useTailscale
        )
        
        await tunnelManager.startTunnel(id: "fileserver", config: config)
        
        if let state = tunnelManager.getTunnelState(id: "fileserver"), state.isActive {
            print("✓ File server tunnel connected on port \(state.localPort ?? 0)")
        } else if let state = tunnelManager.getTunnelState(id: "fileserver"), let error = state.errorMessage {
            print("❌ File server tunnel failed: \(error)")
        }
    }
    
    // MARK: - Public Getters
    
    func getWebTunnelPort() -> Int? {
        return tunnelManager.getLocalPort(id: "web")
    }
    
    func getFileServerTunnelPort() -> Int? {
        return tunnelManager.getLocalPort(id: "fileserver")
    }
}
