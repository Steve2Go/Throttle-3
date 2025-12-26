//
//  TunnelManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftUI
import Combine
#if os(macOS)
import SshLib_macOS
#else
import SshLib_iOS
import TailscaleKit
#endif

struct SSHCredentials {
    let username: String
    let password: String?
    let privateKey: String?
}

struct SSHTunnelConfig {
    let sshHost: String
    let sshPort: Int
    let remoteAddress: String
    let localAddress: String
    let credentials: SSHCredentials
    let useTailscale: Bool
}

struct TunnelState {
    var isActive: Bool = false
    var isConnecting: Bool = false
    var localPort: Int?
    var errorMessage: String?
    var config: SSHTunnelConfig?
}

@MainActor
class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    
    @Published var tunnels: [String: TunnelState] = [:]
    @Published var isConnecting: Bool = false
    
    // Convenience computed properties for backward compatibility with single tunnel
    var isActive: Bool { tunnels.values.contains(where: { $0.isActive }) }
    var errorMessage: String? { tunnels.values.compactMap({ $0.errorMessage }).first }
    
    private init() {}
    
    // MARK: - Public Interface
    
    func startTunnel(id: String, config: SSHTunnelConfig) async {
        // Initialize tunnel state if it doesn't exist
        if tunnels[id] == nil {
            tunnels[id] = TunnelState()
        }
        
        guard tunnels[id]?.isConnecting == false else { return }
        
        tunnels[id]?.isConnecting = true
        tunnels[id]?.errorMessage = nil
        tunnels[id]?.config = config
        
        // Update global connecting state
        updateGlobalConnectingState()
        
        do {
            if config.useTailscale {
                
                // Establish SSH tunnel through Tailscale
                try await establishSSHTunnel(config: config, socks5Address: "127.0.0.1:1080")
                
            } else {
                // Direct SSH tunnel without Tailscale
                try await establishSSHTunnel(config: config, socks5Address: nil)
            }
            
            tunnels[id]?.isActive = true
            tunnels[id]?.isConnecting = false
            
            // Update global connecting state
            updateGlobalConnectingState()
            
            // Parse local port from localAddress
            if let portString = config.localAddress.split(separator: ":").last,
               let port = Int(portString) {
                tunnels[id]?.localPort = port
            }
            
            print("✓ SSH tunnel [\(id)] established: \(config.localAddress) → \(config.remoteAddress)")
            
        } catch {
            tunnels[id]?.isConnecting = false
            tunnels[id]?.isActive = false
            tunnels[id]?.errorMessage = error.localizedDescription
            
            // Update global connecting state
            updateGlobalConnectingState()
            
            print("❌ SSH tunnel [\(id)] failed: \(error)")
        }
    }
    
    func stopTunnel(id: String) {
        // TODO: Implement tunnel shutdown
        // SshLib doesn't expose a stop function in the header we saw
        // May need to add that or track the process/connection
        
        tunnels[id]?.isActive = false
        tunnels[id]?.localPort = nil
        tunnels[id]?.config = nil
        
        print("✓ SSH tunnel [\(id)] stopped")
    }
    
    func stopAllTunnels() {
        for id in tunnels.keys {
            stopTunnel(id: id)
        }
    }
    
    func getTunnelState(id: String) -> TunnelState? {
        return tunnels[id]
    }
    
    func getLocalPort(id: String) -> Int? {
        return tunnels[id]?.localPort
    }
    
    // MARK: - Private Methods
    
    private func updateGlobalConnectingState() {
        isConnecting = tunnels.values.contains(where: { $0.isConnecting })
    }
    
    private func establishSSHTunnel(config: SSHTunnelConfig, socks5Address: String?) async throws {
        let sshAddress = "\(config.sshHost):\(config.sshPort)"
        
        // Call SshLib - works on both iOS and macOS!
        SshlibInitSSH(
            sshAddress,
            socks5Address,
            config.credentials.username,
            config.credentials.password,
            config.credentials.privateKey,
            config.remoteAddress,
            config.localAddress
        )
    }
}

// MARK: - Errors

enum TunnelError: LocalizedError {
    case tailscaleNotAvailable
    case tailscaleTimeout
    case tailscaleFailed
    case tailscaleNotRunning
    case invalidProxyAddress
    case macOSProxyNotSupported
    
    var errorDescription: String? {
        switch self {
        case .tailscaleNotAvailable:
            return "Tailscale is not available"
        case .tailscaleTimeout:
            return "Tailscale connection timed out"
        case .tailscaleFailed:
            return "Tailscale connection failed"
        case .tailscaleNotRunning:
            return "Tailscale is not running on this system"
        case .invalidProxyAddress:
            return "Invalid proxy address"
        case .macOSProxyNotSupported:
            return "On macOS, connect directly to tailnet hostnames instead of using proxy"
        }
    }
}


