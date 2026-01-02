//
//  SSHFS.swift
//  Throttle 3
//
//  Created by GitHub Copilot on 02/01/2026.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import KeychainAccess

#if os(macOS)

@MainActor
class SSHFSManager: ObservableObject {
    static let shared = SSHFSManager()
    
    // MARK: - Properties
    @Published var mountStatus: [String: Bool] = [:] // "host:port" -> mounted status
    @Published var mountPaths: [String: String] = [:] // "host:port" -> mount path
    
    private var processes: [String: Process] = [:] // "host:port" -> Process
    private let keychain = Keychain(service: "com.srgim.throttle3")
    
    private init() {}
    
    // MARK: - Binary Paths
    
    private var sshfsPath: String {
        // Try multiple paths to find the binary
        if let path = Bundle.main.path(forResource: "Resources/sshfs", ofType: nil) {
            return path
        }
        if let path = Bundle.main.path(forResource: "sshfs", ofType: nil) {
            return path
        }
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("sshfs")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        fatalError("sshfs binary not found in app bundle")
    }
    
    private var nfsServerPath: String {
        // Try multiple paths to find the binary
        if let path = Bundle.main.path(forResource: "Resources/go-nfsv4", ofType: nil) {
            return path
        }
        if let path = Bundle.main.path(forResource: "go-nfsv4", ofType: nil) {
            return path
        }
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("go-nfsv4")
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        fatalError("go-nfsv4 binary not found in app bundle")
    }
    
    private var binariesDirectory: String {
        return (sshfsPath as NSString).deletingLastPathComponent
    }
    
    // MARK: - Mount Key
    
    private func mountKey(for server: Servers) -> String {
        let host = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
        let port = server.sshPort
        return "\(host):\(port)"
    }
    
    // MARK: - Mount Path Creation
    
    private func createMountPoint(for server: Servers) -> String {
        let mountsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Throttle3")
            .appendingPathComponent("mounts")
        
        let host = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
        let sanitizedHost = host.replacingOccurrences(of: ":", with: "_")
        let mountPoint = mountsDir.appendingPathComponent(sanitizedHost)
        
        try? FileManager.default.createDirectory(at: mountsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        
        return mountPoint.path
    }
    
    // MARK: - Key File Management
    
    private func createTemporaryKeyFile(content: String, serverID: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let keyFileName = "sshfs_key_\(serverID)_\(UUID().uuidString)"
        let keyPath = tempDir.appendingPathComponent(keyFileName)
        
        do {
            try content.write(to: keyPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath.path)
            return keyPath.path
        } catch {
            print("❌ Failed to create key file: \(error)")
            return nil
        }
    }
    
    // MARK: - Mount All Servers
    
    func mountAllServers(servers: [Servers]) async {
        print("📂 SSHFSManager: Mounting \(servers.count) server(s)...")
        
        for server in servers {
            await mountServer(server)
        }
        
        let mountedCount = mountStatus.values.filter { $0 }.count
        print("✓ SSHFSManager: \(mountedCount) of \(servers.count) server(s) mounted")
    }
    
    // MARK: - Mount Single Server
    
    func mountServer(_ server: Servers) async {
        let key = mountKey(for: server)
        
        // Skip if already mounted
        if mountStatus[key] == true {
            print("⏭️  SSHFSManager: \(key) already mounted, skipping")
            return
        }
        
        guard server.sshOn, !server.sshUser.isEmpty else {
            print("⚠️ SSHFSManager: \(server.name) has SSH disabled or no user configured")
            return
        }
        
        let host = server.sshHost.isEmpty ? server.serverAddress : server.sshHost
        let user = server.sshUser
        let port = server.sshPort
        
        // Use sftpBase if set, otherwise mount at base "/"
        let remotePath = server.sftpBase.isEmpty ? "/" : server.sftpBase
        let mountPoint = createMountPoint(for: server)
        
        print("🔌 SSHFSManager: Mounting \(user)@\(host):\(remotePath) to \(mountPoint)")
        
        // Build sshfs command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        var sshfsOptions = [
            "ServerAliveInterval=30",
            "ServerAliveCountMax=6",
            "reconnect",
            "auto_cache",
            "kernel_cache",
            "location=localhost",
            "StrictHostKeyChecking=no",
            "UserKnownHostsFile=/dev/null",
            "Compression=no",
            "Ciphers=chacha20-poly1305@openssh.com",
            "volname=\(host)"
        ]
        
        var command: String
        var keyFilePath: String?
        
        if server.sshUsesKey {
            // Use SSH key authentication
            guard let keyContent = keychain["\(server.id.uuidString)-sshkey"],
                  !keyContent.isEmpty else {
                print("❌ SSHFSManager: No SSH key found for \(server.name)")
                mountStatus[key] = false
                return
            }
            
            guard let keyPath = createTemporaryKeyFile(content: keyContent, serverID: server.id.uuidString) else {
                print("❌ SSHFSManager: Failed to create key file for \(server.name)")
                mountStatus[key] = false
                return
            }
            keyFilePath = keyPath
            
            sshfsOptions.append("PreferredAuthentications=publickey")
            sshfsOptions.append("IdentityFile=\(keyPath)")
            
            let optionsString = sshfsOptions.joined(separator: ",")
            command = """
            export PATH="\(binariesDirectory):$PATH" && \
            "\(sshfsPath)" \(user)@\(host):\(remotePath) "\(mountPoint)" -p \(port) -o \(optionsString)
            """
        } else {
            // Use password authentication
            guard let password = keychain["\(server.id.uuidString)-sshpassword"],
                  !password.isEmpty else {
                print("❌ SSHFSManager: No SSH password found for \(server.name)")
                mountStatus[key] = false
                return
            }
            
            sshfsOptions.append("password_stdin")
            let optionsString = sshfsOptions.joined(separator: ",")
            
            command = """
            export PATH="\(binariesDirectory):$PATH" && \
            echo '\(password)' | "\(sshfsPath)" \(user)@\(host):\(remotePath) "\(mountPoint)" -p \(port) -o \(optionsString)
            """
        }
        
        process.arguments = ["-c", command]
        
        // Set up environment to find go-nfsv4
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binariesDirectory):/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        
        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                
                let success = process.terminationStatus == 0
                
                if success {
                    self.mountStatus[key] = true
                    self.mountPaths[key] = mountPoint
                    print("✓ SSHFSManager: \(key) mounted successfully at \(mountPoint)")
                } else {
                    self.mountStatus[key] = false
                    
                    let errorData = try? errorPipe.fileHandleForReading.readToEnd()
                    if let errorData = errorData, let errorString = String(data: errorData, encoding: .utf8) {
                        print("❌ SSHFSManager: \(key) mount failed: \(errorString)")
                    } else {
                        print("❌ SSHFSManager: \(key) mount failed with status \(process.terminationStatus)")
                    }
                }
                
                // Clean up key file
                if let keyFilePath = keyFilePath {
                    try? FileManager.default.removeItem(atPath: keyFilePath)
                }
                
                // Remove from processes
                self.processes.removeValue(forKey: key)
            }
        }
        
        do {
            try process.run()
            processes[key] = process
            
            // Wait a moment for mount to initialize
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check if still running (should be for successful mount)
            if process.isRunning {
                mountStatus[key] = true
                mountPaths[key] = mountPoint
            }
        } catch {
            print("❌ SSHFSManager: Failed to start mount process for \(key): \(error)")
            mountStatus[key] = false
            
            // Clean up key file
            if let keyFilePath = keyFilePath {
                try? FileManager.default.removeItem(atPath: keyFilePath)
            }
        }
    }
    
    // MARK: - Unmount
    
    func unmountServer(_ server: Servers) async {
        let key = mountKey(for: server)
        
        guard let mountPoint = mountPaths[key] else {
            print("⚠️ SSHFSManager: \(key) not mounted")
            return
        }
        
        print("🔌 SSHFSManager: Unmounting \(key) from \(mountPoint)")
        
        // Terminate the sshfs process
        if let process = processes[key] {
            process.terminate()
            processes.removeValue(forKey: key)
        }
        
        // Wait a moment
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Force unmount
        let unmountProcess = Process()
        unmountProcess.executableURL = URL(fileURLWithPath: "/sbin/umount")
        unmountProcess.arguments = ["-f", mountPoint]
        
        do {
            try unmountProcess.run()
            unmountProcess.waitUntilExit()
            
            if unmountProcess.terminationStatus == 0 {
                print("✓ SSHFSManager: \(key) unmounted successfully")
            } else {
                print("⚠️ SSHFSManager: \(key) unmount returned status \(unmountProcess.terminationStatus)")
            }
        } catch {
            print("❌ SSHFSManager: Failed to unmount \(key): \(error)")
        }
        
        // Update status
        mountStatus[key] = false
        mountPaths.removeValue(forKey: key)
        
        // Remove mount point directory
        try? FileManager.default.removeItem(atPath: mountPoint)
    }
    
    func unmountAll() async {
        print("📂 SSHFSManager: Unmounting all servers...")
        
        let allKeys = Array(mountPaths.keys)
        for key in allKeys {
            if let mountPoint = mountPaths[key] {
                // Terminate process
                if let process = processes[key] {
                    process.terminate()
                }
                
                // Force unmount
                let unmountProcess = Process()
                unmountProcess.executableURL = URL(fileURLWithPath: "/sbin/umount")
                unmountProcess.arguments = ["-f", mountPoint]
                try? unmountProcess.run()
                unmountProcess.waitUntilExit()
                
                // Clean up
                try? FileManager.default.removeItem(atPath: mountPoint)
            }
        }
        
        processes.removeAll()
        mountStatus.removeAll()
        mountPaths.removeAll()
        
        print("✓ SSHFSManager: All servers unmounted")
    }
    
    // MARK: - Status Checks
    
    func isMounted(_ server: Servers) -> Bool {
        let key = mountKey(for: server)
        return mountStatus[key] == true
    }
    
    func getMountPath(_ server: Servers) -> String? {
        let key = mountKey(for: server)
        return mountPaths[key]
    }
}

#endif

