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
import Transmission
#if os(iOS)
import TailscaleKit
#endif
//1 - Tailscale if set, or tunnel()

//2 Tunnels up - Http if set, plus one for SFTP

//3 Start queue

@MainActor
class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    @Published var isConnecting: Bool = false
    @Published var isConnected: Bool = false
    @Published var errorMessage: String?
    @Published var currentServerID: UUID?
    
    // Operation tracking
    private var activeOperations: Set<UUID> = []
    private var isDisconnecting: Bool = false
    
    private let tailscaleManager = TailscaleManager.shared
    private let tunnelManager = TunnelManager.shared
    private let sshManager = SSHManager.shared
    private let sftpManager = SFTPManager.shared
    private let keychain = Keychain(service: "com.srgim.throttle3")
    private var cancellables = Set<AnyCancellable>()
    
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
        // Don't connect if we're in the middle of disconnecting
        guard !isDisconnecting else {
            print("⚠️ ConnectionManager: Cannot connect while disconnecting")
            return
        }
        guard !isConnecting else { return }
        
        isConnecting = true
        currentServerID = server.id
        errorMessage = nil
        
//        if server.useTailscale {
//            // Wait for Tailscale connection
//            print("🔌 ConnectionManager: Waiting for Tailscale connection...")
//            await tailscaleManager.connect()
//            while !tailscaleManager.isConnected {
//                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
//            }
//            print("✓ Tailscale connected")
//        } else{
//            await tailscaleManager.disconnect()
//        }
        
        print("🔌 ConnectionManager: Starting connection for server '\(server.name)' (ID: \(server.id))")
        
        // Clear all previous tunnel states to avoid port conflicts
//        tunnelManager.stopAllTunnels()
        print("✓ Cleared previous tunnel states")
        
        
        // Give SwiftUI time to render the connecting state
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Start web tunnel if needed
       
        await startWebTunnel(server: server)
        
        
        // Monitor tunnel states by checking port connectivity
        var expectedTunnels: [String] = []
        expectedTunnels.append("web") // Always expect web tunnel
        
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
    
    /// Disconnect all tunnels - waits for active operations to complete
    func disconnect() async {
        guard !isDisconnecting else { return }
        
        isDisconnecting = true
        isConnected = false
        isConnecting = false
        
        // Wait for active operations to complete (max 5 seconds)
        var waitAttempts = 0
        let maxWaitAttempts = 10 // 10 * 500ms = 5 seconds
        
        while !activeOperations.isEmpty && waitAttempts < maxWaitAttempts {
            print("⏳ Waiting for \(activeOperations.count) active operation(s) to complete...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            waitAttempts += 1
        }
        
        if !activeOperations.isEmpty {
            print("⚠️ Force disconnecting with \(activeOperations.count) operation(s) still active")
        }
        
        // Stop all tunnels
        tunnelManager.stopAllTunnels()
        
        // Wait for port release
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for port cleanup
        
        currentServerID = nil
        isDisconnecting = false
        
        print("✓ ConnectionManager: All tunnels disconnected, state cleared")
    }
    
    /// Register an active operation (like torrent fetch)
    func beginOperation() -> UUID {
        let operationID = UUID()
        activeOperations.insert(operationID)
        return operationID
    }
    
    /// Unregister an active operation
    func endOperation(_ operationID: UUID) {
        activeOperations.remove(operationID)
    }
    
    // MARK: - Private Methods
    
    private func startWebTunnel(server: Servers) async {
//        if await tunnelManager.checkTunnelConnectivity(id: "web") {
//            return
//        }
        
        // Check and install ffmpeg if needed (before starting tunnel)
        if !server.ffmpegInstalled {
            await checkAndInstallFfmpeg(server: server)
        } else{
            print("✓ ffmpeg already installed, skipping check")
        }
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
    
    // MARK: - FFmpeg Installation
    
    private func checkAndInstallFfmpeg(server: Servers) async {
        print("🔍 Checking for ffmpeg installation...")
        
        // Check if ffmpeg exists
        let checkCommand = "test -f ~/.throttle3/bin/ffmpeg && echo 'exists' || echo 'not found'"
        let ffmpegExists = try? await sshManager.executeCommand(
            server: server,
            command: checkCommand,
            timeout: 5,
            useTunnel: false
        )
        
        if ffmpegExists?.contains("not found") == true {
            print("📥 ffmpeg not installed, downloading...")
            
            // Install command that detects OS/arch and downloads ffmpeg
            let installCommand = """
            mkdir -p ~/.throttle3/bin && cd /tmp && \
            OS=$(uname -s | tr '[:upper:]' '[:lower:]') && \
            ARCH=$(uname -m) && \
            if [ "$OS" = "linux" ]; then
                case "$ARCH" in
                    x86_64) FFMPEG_ARCH="amd64" ;;
                    aarch64) FFMPEG_ARCH="arm64" ;;
                    armv7l) FFMPEG_ARCH="armhf" ;;
                    armv6l) FFMPEG_ARCH="armel" ;;
                    *) echo "Unsupported arch: $ARCH" && exit 1 ;;
                esac
                wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${FFMPEG_ARCH}-static.tar.xz -O ffmpeg.tar.xz && \
                tar -xJf ffmpeg.tar.xz && \
                FFMPEG_DIR=$(find . -type d -name "ffmpeg-*-${FFMPEG_ARCH}-static" | head -n 1) && \
                mv $FFMPEG_DIR/ffmpeg ~/.throttle3/bin/ffmpeg && \
                chmod +x ~/.throttle3/bin/ffmpeg && \
                rm -rf ffmpeg* && \
                echo "✓ Linux ffmpeg installed"
            elif [ "$OS" = "darwin" ]; then
                curl -sL https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip -o ffmpeg.zip && \
                unzip -q ffmpeg.zip && \
                mv ffmpeg ~/.throttle3/bin/ffmpeg && \
                chmod +x ~/.throttle3/bin/ffmpeg && \
                rm -rf ffmpeg* && \
                echo "✓ macOS ffmpeg installed"
            else
                echo "Unsupported OS: $OS" && exit 1
            fi
            """
            
            do {
                print("🔧 Installing ffmpeg...")
                let result = try await sshManager.executeCommand(
                    server: server,
                    command: installCommand,
                    timeout: 180,
                    useTunnel: false
                )
                
                print("✓ ffmpeg installed: \(result)")
                
                // Mark as installed in the server model
                server.ffmpegInstalled = true
            } catch {
                print("❌ Failed to install ffmpeg: \(error)")
            }
        } else {
            print("✓ ffmpeg already installed")
            // Mark as installed to skip future checks
            server.ffmpegInstalled = true
        }
    }
    

    
    // MARK: - Public Getters
    
    func getWebTunnelPort() -> Int? {
        return tunnelManager.getLocalPort(id: "web")
    }
}
