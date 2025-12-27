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
        let remoteFileServerPort = (Int(server.serverPort) ?? 80) + 10000
        
        // Step 1: Wait for web tunnel if needed, then get Transmission download directory
        var downloadDir: String?
        
        if server.tunnelWebOverSSH {
            // Wait for web tunnel to be active
            print("⏳ Waiting for web tunnel to get Transmission session info...")
            var attempts = 0
            while attempts < 20 && tunnelManager.getTunnelState(id: "web")?.isActive != true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
            }
        }
        
        // Get download directory from Transmission
        downloadDir = await getTransmissionDownloadDir(server: server)
        
        if downloadDir == nil {
            print("⚠️ Could not get Transmission download directory, using default ~/Downloads")
            downloadDir = "~/Downloads"
        } else {
            print("✓ Transmission download directory: \(downloadDir!)")
        }
        
        // Step 2: Setup dufs on remote server
        do {
            try await setupDufsServer(server: server, downloadDir: downloadDir!, port: remoteFileServerPort)
        } catch {
            print("❌ Failed to setup dufs server: \(error)")
        }
        
        // Step 3: Start SSH tunnel for file server
        let localFileServerPort = (Int(server.serverPort) ?? 80) + 18000
        
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
    
    // MARK: - File Server Setup
    
    /// Get Transmission download directory from session
    private func getTransmissionDownloadDir(server: Servers) async -> String? {
        // Build Transmission URL
        let scheme = server.usesSSL ? "https" : "http"
        var host: String
        var port: Int
        
        if server.tunnelWebOverSSH {
            host = "127.0.0.1"
            port = (Int(server.serverPort) ?? 80) + 8000
        } else if server.useTailscale {
            host = server.serverAddress
            port = Int(server.reverseProxyPort) ?? (Int(server.serverPort) ?? 9091)
        } else {
            host = server.serverAddress
            port = Int(server.serverPort) ?? 9091
        }
        
        let urlString = "\(scheme)://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid Transmission URL: \(urlString)")
            return nil
        }
        
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        let client = Transmission(baseURL: url, username: server.user, password: password)
        
        // Create custom request for session-get to get download-dir
        let sessionRequest = Request<String>(
            method: "session-get",
            args: ["fields": ["download-dir"]],
            transform: { response -> Result<String, TransmissionError> in
                guard let arguments = response["arguments"] as? [String: Any],
                      let downloadDir = arguments["download-dir"] as? String
                else {
                    return .failure(.unexpectedResponse)
                }
                return .success(downloadDir)
            }
        )
        
        return await withCheckedContinuation { continuation in
            client.request(sessionRequest)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            print("❌ Failed to get Transmission session: \(error)")
                            continuation.resume(returning: nil)
                        }
                    },
                    receiveValue: { downloadDir in
                        continuation.resume(returning: downloadDir)
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    /// Setup dufs server on remote machine
    private func setupDufsServer(server: Servers, downloadDir: String, port: Int) async throws {
        print("📦 Setting up dufs server...")
        
        // Step 1: Check if dufs is already running on this port
        print("🔍 Checking if dufs is already running on port \(port)...")
        let checkCommand = "(ss -tln | grep '127.0.0.1:\(port)' || lsof -i TCP:\(port) -sTCP:LISTEN) && pgrep -f 'dufs.*-p \(port)' > /dev/null && echo 'running' || echo 'not running'"
        let checkOutput = try? await sshManager.executeCommand(
            server: server,
            command: checkCommand,
            timeout: 5,
            useTunnel: false
        )
        
        if checkOutput?.contains("running") == true {
            print("✓ dufs is already running on port \(port)")
            return
        }
        
        print("⚠️ dufs not running, checking if binary exists...")
        
        // Step 2: Check if dufs binary exists
        let dufsExistsCommand = "test -f ~/.throttle3/bin/dufs && echo 'exists' || echo 'not found'"
        let dufsExists = try? await sshManager.executeCommand(
            server: server,
            command: dufsExistsCommand,
            timeout: 5,
            useTunnel: false
        )
        
        if dufsExists?.contains("not found") == true {
            print("📥 dufs not installed, running installation...")
            
            // Step 3: Upload install script - try multiple paths
            // Step 3: Upload install script - try multiple paths
        var scriptURL = Bundle.main.url(forResource: "install-tools", withExtension: "sh", subdirectory: "Resources")
        if scriptURL == nil {
            scriptURL = Bundle.main.url(forResource: "install-tools", withExtension: "sh")
        }
        
        guard let scriptURL = scriptURL else {
            throw NSError(domain: "ConnectionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "install-tools.sh not found in bundle"])
        }
        
        print("📄 Found script at: \(scriptURL.path)")
        
        let tempScriptPath = NSTemporaryDirectory() + "install-tools.sh"
        let tempScriptURL = URL(fileURLWithPath: tempScriptPath)
        
        // Remove existing temp file if it exists
        try? FileManager.default.removeItem(at: tempScriptURL)
        
        // Copy script to temp location
        try FileManager.default.copyItem(at: scriptURL, to: tempScriptURL)
        
        print("📤 Uploading install script...")
        try await sftpManager.uploadFile(
            server: server,
            localPath: tempScriptPath,
            remotePath: ".throttle3/install-tools.sh",
            useTunnel: false
        )
        
        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempScriptPath)
        
        // Step 4: Make script executable and run it
        print("🔧 Installing dufs and ffmpeg...")
        _ = try await sshManager.executeCommand(
            server: server,
            command: "chmod +x ~/.throttle3/install-tools.sh && bash ~/.throttle3/install-tools.sh",
            timeout: 180,
            useTunnel: false
        )
        
        print("✓ Tools installed")
        } else {
            print("✓ dufs binary found, skipping installation")
        }
        
        // Step 5: Kill any existing dufs on this port (in case it's stuck)
        print("🔄 Ensuring clean start...")
        let killCommand = "pkill -f 'dufs.*-p \(port)' || true"
        _ = try? await sshManager.executeCommand(
            server: server,
            command: killCommand,
            timeout: 5,
            useTunnel: false
        )
        
        // Step 6: Start dufs server
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        let dufsCommand = """
        nohup ~/.throttle3/bin/dufs '\(downloadDir)' \
            -p \(port) \
            --bind 127.0.0.1 \
            -a '\(server.user):\(password)@/:rw' \
            > ~/.throttle3/dufs.log 2>&1 &
        """
        
        print("🚀 Starting dufs server on port \(port)...")
        try await sshManager.executeCommandBackground(
            server: server,
            command: dufsCommand,
            useTunnel: false
        )
        
        // Give dufs a moment to start
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify it's running
        let verifyCommand = "ss -tln | grep '127.0.0.1:\(port)' || lsof -i TCP:\(port) -sTCP:LISTEN || echo 'not running'"
        let verifyOutput = try await sshManager.executeCommand(
            server: server,
            command: verifyCommand,
            timeout: 5,
            useTunnel: false
        )
        
        if verifyOutput.contains("not running") {
            print("❌ dufs failed to start - check ~/.throttle3/dufs.log on remote server")
        } else {
            print("✓ dufs server running on port \(port)")
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
