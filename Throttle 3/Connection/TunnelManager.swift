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
    
    private let tailscaleManager = TailscaleManager.shared
    
    // Convenience computed properties for backward compatibility with single tunnel
    var isActive: Bool { tunnels.values.contains(where: { $0.isActive }) }
    var errorMessage: String? { tunnels.values.compactMap({ $0.errorMessage }).first }
    
    private init() {}
    
    // MARK: - Public Interface
    
    func startTunnel(id: String, config: SSHTunnelConfig) async {
        await stopTunnel(id: id)
        // Initialize tunnel state if it doesn't exist
        if tunnels[id] == nil {
            tunnels[id] = TunnelState()
        }
        
        guard tunnels[id]?.isConnecting == false else { return }
        guard tunnels[id]?.isActive == false else { return }
        
        tunnels[id]?.isConnecting = true
        tunnels[id]?.errorMessage = nil
        tunnels[id]?.config = config
        
        // Update global connecting state
        updateGlobalConnectingState()
        
        do {
            #if os(iOS)
            if config.useTailscale {
                guard let proxyConfig = tailscaleManager.proxyConfig,
                      let proxyPort = proxyConfig.port else {
                    throw TunnelError.invalidProxyAddress
                }
                // Establish SSH tunnel through Tailscale with authentication
                let socks5Address = "127.0.0.1:\(proxyPort)"
                let socks5Auth = "tsnet:\(proxyConfig.proxyCredential)"
                print("Proxy via Tailscale Port: \(proxyPort) with auth")
                
                // Start tunnel in background - it will run indefinitely
                Task.detached {
                    try await self.establishSSHTunnel(tunnelID: id, config: config, socks5Address: socks5Address, socks5ProxyAuth: socks5Auth)
                }
                
            } else {
                // Direct SSH tunnel without Tailscale - start in background
                Task.detached {
                   try await self.establishSSHTunnel(tunnelID: id, config: config, socks5Address: nil, socks5ProxyAuth: nil)
                }
            }
            #else
            Task.detached {
               try await self.establishSSHTunnel(tunnelID: id, config: config, socks5Address: nil, socks5ProxyAuth: nil)
            }
            #endif
            
            // Mark as connecting - will be updated to active when "Port forward active" is detected
            tunnels[id]?.isConnecting = true
            
            // Parse and store expected local port from localAddress
            if let portString = config.localAddress.split(separator: ":").last,
               let port = Int(portString) {
                tunnels[id]?.localPort = port
            }
            
            print("🔄 SSH tunnel [\(id)] initiating: \(config.localAddress) → \(config.remoteAddress)")
            
        } catch {
            tunnels[id]?.isConnecting = false
            tunnels[id]?.isActive = false
            tunnels[id]?.errorMessage = error.localizedDescription
            
            // Update global connecting state
            updateGlobalConnectingState()
            
            print("❌ SSH tunnel [\(id)] failed: \(error)")
        }
    }
    
    func stopTunnel(id: String) async {
        guard tunnels[id] != nil else {
            print("⚠️ Tunnel [\(id)] not found")
            return
        }
        
        // Call the library's stop function
        var error: NSError?
        SshlibStopSSHTunnel(id, &error)
        
        if let error = error {
            print("❌ Error stopping tunnel [\(id)]: \(error.localizedDescription)")
        } else {
            print("✓ SSH tunnel [\(id)] stopped successfully")
        }
        while await checkTunnelConnectivity(id: id){
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        // Remove the tunnel state
        tunnels.removeValue(forKey: id)
        
        // Update global connecting state
        updateGlobalConnectingState()
    }
    
    func stopAllTunnels() {
        for id in tunnels.keys {
            Task {
                await stopTunnel(id: id)
            }
        }
    }
    
    func getTunnelState(id: String) -> TunnelState? {
        return tunnels[id]
    }
    
    func getLocalPort(id: String) -> Int? {
        return tunnels[id]?.localPort
    }
    
    /// Mark a tunnel as active (called when "Port forward active" is detected)
    func markTunnelActive(id: String) {
        tunnels[id]?.isActive = true
        tunnels[id]?.isConnecting = false
        updateGlobalConnectingState()
        print("✓ SSH tunnel [\(id)] confirmed active")
    }
    
    /// Check if all expected tunnels are active
    func areAllTunnelsActive(ids: [String]) -> Bool {
        return ids.allSatisfy { id in
            tunnels[id]?.isActive == true
        }
    }
    
    /// Check if a tunnel's local port is listening (confirms tunnel is active)
    func checkTunnelConnectivity(id: String) async -> Bool {
        guard let port = tunnels[id]?.localPort else {
            print("⚠️ No local port found for tunnel [\(id)]")
            return false
        }
        
        print("🔍 Checking connectivity for tunnel [\(id)] on port \(port)")
        
        // Try to connect to the local port
        let host = "127.0.0.1"
        let streamTask = URLSession.shared.streamTask(withHostName: host, port: port)
        
        return await withCheckedContinuation { continuation in
            streamTask.resume()
            
            // Give it a moment to connect
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if streamTask.state == .running {
                    streamTask.cancel()
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateGlobalConnectingState() {
        isConnecting = tunnels.values.contains(where: { $0.isConnecting })
    }
    
    private func establishSSHTunnel(tunnelID: String, config: SSHTunnelConfig, socks5Address: String?, socks5ProxyAuth: String?) async throws {
        let sshAddress = "\(config.sshHost):\(config.sshPort)"
        
        // Call SshLib on a background thread since it's a blocking call
        try await Task.detached {
            var error: NSError?
            SshlibStartSSHTunnel(
                tunnelID,
                sshAddress,
                socks5Address ?? "",
                socks5ProxyAuth ?? "",
                config.credentials.username,
                config.credentials.password ?? "",
                config.credentials.privateKey ?? "",
                config.remoteAddress,
                config.localAddress,
                &error
            )
            if let error = error {
                throw error
            }
        }.value
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


