//
//  SSHManager.swift
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
#endif

/// SSHManager provides SSH command execution using the SshLib framework
@MainActor
class SSHManager {
    static let shared = SSHManager()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Execute a command on the remote server and wait for output
    /// - Parameters:
    ///   - server: Server configuration
    ///   - command: Command to execute
    ///   - timeout: Timeout in seconds (default 30)
    ///   - useTunnel: If true, connects via localhost tunnel (for iOS with Tailscale)
    /// - Returns: Command output as string
    func executeCommand(
        server: Servers,
        command: String,
        timeout: Int = 30,
        useTunnel: Bool = false
    ) async throws -> String {
        let credentials = try loadCredentials(for: server)
        
        // Determine connection parameters
        let (sshHost, socks5Address) = try await getConnectionParams(
            server: server,
            useTunnel: useTunnel
        )
        
        // Execute via SshLib
        var error: NSError?
        let output = SshlibExecuteCommand(
            sshHost,
            socks5Address,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            command,
            timeout,
            &error
        )
        
        if let error = error {
            throw SSHError.executionFailed(error.localizedDescription)
        }
        
        return output
    }
    
    /// Execute a command in the background (fire and forget)
    /// Useful for starting long-running services like dufs
    /// - Parameters:
    ///   - server: Server configuration
    ///   - command: Command to execute
    ///   - useTunnel: If true, connects via localhost tunnel (for iOS with Tailscale)
    func executeCommandBackground(
        server: Servers,
        command: String,
        useTunnel: Bool = false
    ) async throws {
        let credentials = try loadCredentials(for: server)
        
        // Determine connection parameters
        let (sshHost, socks5Address) = try await getConnectionParams(
            server: server,
            useTunnel: useTunnel
        )
        
        // Execute via SshLib
        var error: NSError?
        let success = SshlibExecuteCommandBackground(
            sshHost,
            socks5Address,
            server.sshUser,
            credentials.password,
            credentials.privateKey,
            command,
            &error
        )
        
        if let error = error {
            throw SSHError.executionFailed(error.localizedDescription)
        }
        
        if !success {
            throw SSHError.executionFailed("Command failed to start")
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCredentials(for server: Servers) throws -> (password: String?, privateKey: String?) {
        if server.sshUsesKey {
            // Load private key from keychain
            guard let privateKey = try? Keychain(service: "com.srgim.throttle3")
                .getString("\(server.id.uuidString)-ssh-key") else {
                throw SSHError.missingCredentials
            }
            return (password: nil, privateKey: privateKey)
        } else {
            // Load password from keychain
            guard let password = try? Keychain(service: "com.srgim.throttle3")
                .getString("\(server.id.uuidString)-ssh-password") else {
                throw SSHError.missingCredentials
            }
            return (password: password, privateKey: nil)
        }
    }
    
    private func getConnectionParams(
        server: Servers,
        useTunnel: Bool
    ) async throws -> (sshHost: String, socks5Address: String?) {
        #if os(iOS)
        // iOS: Always use tunnel approach with Tailscale's SOCKS5 proxy
        if server.useTailscale {
            let tsManager = TailscaleManager.shared
            guard let socks5Addr = await tsManager.getSocks5Address() else {
                throw SSHError.tailscaleNotAvailable
            }
            
            let sshHost = "\(server.sshHost):\(server.sshPort)"
            return (sshHost, socks5Addr)
        } else {
            // Direct connection on iOS (if server is directly reachable)
            let sshHost = "\(server.sshHost):\(server.sshPort)"
            return (sshHost, nil)
        }
        #else
        // macOS: Direct connection to tailnet hostname
        let sshHost = "\(server.sshHost):\(server.sshPort)"
        return (sshHost, nil)
        #endif
    }
}

// MARK: - Errors

enum SSHError: LocalizedError {
    case missingCredentials
    case tailscaleNotAvailable
    case executionFailed(String)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "SSH credentials not found in keychain"
        case .tailscaleNotAvailable:
            return "Tailscale SOCKS5 proxy not available"
        case .executionFailed(let message):
            return "SSH command execution failed: \(message)"
        case .invalidConfiguration:
            return "Invalid SSH configuration"
        }
    }
}
