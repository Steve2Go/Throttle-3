//
//  ConnetionManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftUI
import Combine

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
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Connect tunnels for a server configuration
    /// This handles Tailscale waiting and establishes all necessary SSH tunnels
    func connect(server: Servers) async {
        guard !isConnecting else { return }
        
        isConnecting = true
        
        errorMessage = nil
        
        print("🔌 ConnectionManager: Starting connection for server '\(server.name)'")
        
        // Step 2: Start web tunnel if enabled
        if server.tunnelWebOverSSH {
            await startWebTunnel(server: server)
        }
        
        // Step 4: Start file server tunnel if needed
        if server.serveFilesOverTunnels {
            await startFileServerTunnel(server: server)
        }
        
        isConnecting = false
        isConnected = true
        print("✓ ConnectionManager: All tunnels established")
    }
    
    /// Disconnect all tunnels
    func disconnect() {
        tunnelManager.stopAllTunnels()
        isConnected = false
        print("✓ ConnectionManager: All tunnels disconnected")
    }
    
    // MARK: - Private Methods
    
    private func startWebTunnel(server: Servers) async {
            let credentials = SSHCredentials(
            username: server.sshUser,
            password: "", // TODO: Get from keychain
            privateKey: nil // TODO: Get from keychain if using key
        )
        
        let config = SSHTunnelConfig(
            sshHost: server.sshHost.isEmpty ? server.serverAddress : server.sshHost,
            sshPort: Int(server.sshPort) ?? 22,
            remoteAddress: "127.0.0.1:\(server.serverPort)",
            localAddress: "127.0.0.1:80\(server.serverPort)", // Let system assign a port
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
        
        let credentials = SSHCredentials(
            username: server.sshUser,
            password: "", // TODO: Get from keychain
            privateKey: nil // TODO: Get from keychain if using key
        )
        

        let config = SSHTunnelConfig(
            sshHost: server.sshHost.isEmpty ? server.serverAddress : server.sshHost,
            sshPort: Int(server.sshPort) ?? 22,
            remoteAddress: "127.0.0.1:8\(server.serverPort)",
            localAddress: "127.0.0.1:88\(server.serverPort)",
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
