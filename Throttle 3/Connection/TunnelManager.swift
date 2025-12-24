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

@MainActor
class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    
    @Published var isActive = false
    @Published var isConnecting = false
    @Published var localPort: Int?
    @Published var errorMessage: String?
    
    private var currentConfig: SSHTunnelConfig?
    
    private init() {}
    
    // MARK: - Public Interface
    
    func startTunnel(config: SSHTunnelConfig) async {
        guard !isConnecting else { return }
        
        isConnecting = true
        errorMessage = nil
        currentConfig = config
        
        do {
            if config.useTailscale {
                // Wait for Tailscale to be connected first
                try await ensureTailscaleConnected()
                
                // Get Tailscale SOCKS5 proxy details
                let socks5Address = try await getTailscaleProxyAddress()
                
                // Establish SSH tunnel through Tailscale
                try await establishSSHTunnel(config: config, socks5Address: socks5Address)
                
            } else {
                // Direct SSH tunnel without Tailscale
                try await establishSSHTunnel(config: config, socks5Address: nil)
            }
            
            isActive = true
            isConnecting = false
            
            print("✓ SSH tunnel established: \(config.localAddress) → \(config.remoteAddress)")
            
        } catch {
            isConnecting = false
            isActive = false
            errorMessage = error.localizedDescription
            print("❌ SSH tunnel failed: \(error)")
        }
    }
    
    func stopTunnel() {
        // TODO: Implement tunnel shutdown
        // SshLib doesn't expose a stop function in the header we saw
        // May need to add that or track the process/connection
        
        isActive = false
        localPort = nil
        currentConfig = nil
        
        print("✓ SSH tunnel stopped")
    }
    
    // MARK: - Private Methods
    
    private func ensureTailscaleConnected() async throws {
        let manager = TailscaleManager.shared
        
        #if os(iOS)
        // iOS: Wait for embedded Tailscale
        if manager.isConnected {
            return
        }
        
        if !manager.isConnecting {
            await manager.connect()
        }
        
        let startTime = Date()
        let timeout: TimeInterval = 30.0
        
        while !manager.isConnected {
            if Date().timeIntervalSince(startTime) > timeout {
                throw TunnelError.tailscaleTimeout
            }
            
            if manager.errorMessage != nil {
                throw TunnelError.tailscaleFailed
            }
            
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        #else
        // macOS: Just check if system Tailscale is running
        if !manager.isConnected {
            throw TunnelError.tailscaleNotRunning
        }
        #endif
    }
    
    private func getTailscaleProxyAddress() async throws -> String {
        #if os(iOS)
        guard let node = TailscaleManager.shared.node else {
            throw TunnelError.tailscaleNotAvailable
        }
        
        let loopback = try await node.loopback()
        guard let ip = loopback.ip, let port = loopback.port else {
            throw TunnelError.invalidProxyAddress
        }
        
        return "\(ip):\(port)"
        #else
        // macOS: Tailscale doesn't expose SOCKS5 proxy by default
        // We can use `tailscale nc` as ProxyCommand instead, or connect directly via tailnet
        // For simplicity, if using tailscale on macOS, just use the tailnet hostname directly
        // and don't use SOCKS5 proxy - SSH will resolve via Tailscale's DNS
        throw TunnelError.macOSProxyNotSupported
        #endif
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
        
        // Parse local port from localAddress
        if let portString = config.localAddress.split(separator: ":").last,
           let port = Int(portString) {
            localPort = port
        }
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


