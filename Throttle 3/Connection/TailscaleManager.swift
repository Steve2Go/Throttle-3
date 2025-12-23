//
//  TailscaleManager.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftUI
import Combine
#if os(iOS)
import SafariServices
import TailscaleKit
#endif

#if os(iOS)
@MainActor
class TailscaleManager: ObservableObject {
    static let shared = TailscaleManager()
    
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?
    @Published var authURL: URL?
    
    
    private var node: TailscaleNode?
    private var localAPIClient: LocalAPIClient?
    private var messageProcessor: MessageProcessor?
    private var safariViewController: SFSafariViewController?
    
    private init() {
        // Load stored auth state
        isConnected = UserDefaults.standard.string(forKey: "TailscaleAuth") != nil
    }
    
    // MARK: - Connection Management
    
    func connect() async {
        guard !isConnecting else { return }
        
        isConnecting = true
        errorMessage = nil
        
        do {
            // Setup data directory
            let dataDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("tailscale")
            
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            
            // Get stored auth key if we have one
            let storedAuth = UserDefaults.standard.string(forKey: "TailscaleAuth")
            
            let config = Configuration(
                hostName: "Throttle-iOS",
                path: dataDir.path,
                authKey: storedAuth,
                controlURL: kDefaultControlURL,
                ephemeral: true
            )
            
            // Create node
            let node = try TailscaleNode(config: config, logger: SimpleLogger())
            self.node = node
            
            // Set up LocalAPI client
            let apiClient = LocalAPIClient(localNode: node, logger: SimpleLogger())
            self.localAPIClient = apiClient
            
            // Set up IPN bus watcher BEFORE calling node.up()
            let consumer = TailscaleMessageConsumer(manager: self)
            let processor = try await apiClient.watchIPNBus(
                mask: [.initialState, .prefs],
                consumer: consumer
            )
            self.messageProcessor = processor
            
            // Bring the node up - this will trigger auth flow if needed
            try await node.up()
            
        } catch {
            isConnecting = false
            errorMessage = error.localizedDescription
            print("❌ Tailscale connection failed: \(error)")
        }
    }
    
    func disconnect() async {
        guard let node = node else { return }
        
        do {
            try await node.down()
            
            // Clean up
            messageProcessor?.cancel()
            messageProcessor = nil
            localAPIClient = nil
            self.node = nil
            
            // Wipe the auth
            UserDefaults.standard.removeObject(forKey: "TailscaleAuth")
            
            isConnected = false
            isConnecting = false
            authURL = nil
            
            // Dismiss Safari if open
            dismissSafariViewController()
            
            print("✓ Tailscale disconnected and auth cleared")
        } catch {
            errorMessage = "Failed to disconnect: \(error.localizedDescription)"
            print("❌ Tailscale disconnect failed: \(error)")
        }
    }
    
    // MARK: - Auth Flow
    
    func handleAuthURL(_ url: URL) {
        authURL = url
        presentSafariViewController(url: url)
    }
    
    func handleConnected() {
        isConnecting = false
        isConnected = true
        dismissSafariViewController()
        
        // Store a simple connected flag
        // The auth key is already stored in the node's data directory
        UserDefaults.standard.set("connected", forKey: "TailscaleAuth")
        
        print("✓ Tailscale connected")
    }
    
    // MARK: - Safari View Controller
    
    private func presentSafariViewController(url: URL) {
        dismissSafariViewController()
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            print("⚠️ Could not find root view controller")
            return
        }
        
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        let safariVC = SFSafariViewController(url: url)
        safariVC.dismissButtonStyle = .cancel
        safariViewController = safariVC
        
        topController.present(safariVC, animated: true) {
            print("✓ Safari view controller presented for auth")
        }
    }
    
    private func dismissSafariViewController() {
        guard let safariVC = safariViewController else { return }
        
        safariVC.dismiss(animated: true) {
            print("✓ Safari view controller dismissed")
        }
        safariViewController = nil
    }
}

// MARK: - Message Consumer

actor TailscaleMessageConsumer: MessageConsumer {
    weak var manager: TailscaleManager?
    
    init(manager: TailscaleManager) {
        self.manager = manager
    }
    
    func notify(_ notify: Ipn.Notify) {
        Task { @MainActor [weak manager] in
            guard let manager = manager else { return }
            
            // Capture the auth URL if provided
            if let browseURL = notify.BrowseToURL, let url = URL(string: browseURL) {
                print("📍 Got auth URL from Tailscale: \(url)")
                manager.handleAuthURL(url)
            }
            
            // Update status based on state
            if let state = notify.State {
                switch state {
                case .Running:
                    manager.handleConnected()
                    
                case .Starting:
                    manager.isConnecting = true
                    
                case .NeedsLogin:
                    manager.isConnected = false
                    manager.isConnecting = false
                    
                default:
                    break
                }
            }
        }
    }
    
    func error(_ error: Error) {
        Task { @MainActor [weak manager] in
            guard let manager = manager else { return }
            manager.errorMessage = error.localizedDescription
            print("❌ Tailscale error: \(error)")
        }
    }
}

// MARK: - Simple Logger

class SimpleLogger: LogSink {
    var logFileHandle: Int32? = nil
    
    func log(_ message: String) {
        print("[Tailscale] \(message)")
    }
}
#endif

// MARK: - macOS Implementation

#if os(macOS)
class TailscaleManager: ObservableObject {
    private static var _shared: TailscaleManager?
    private static let lock = NSLock()
    
    static var shared: TailscaleManager {
        lock.lock()
        defer { lock.unlock() }
        
        if _shared == nil {
            _shared = TailscaleManager()
        }
        return _shared!
    }
    
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String?
    @Published var showDownloadSheet: Bool = false
    
    private var cliPath: String?
    private var statusCheckTimer: Timer?
    private var isInitialized = false
    private var isMonitoring = false
    
    private init() {
        // Do nothing during init - defer all work
    }
    
    @MainActor
    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        detectCLI()
    }
    
    // MARK: - CLI Detection
    
    private func detectCLI() {
        // Try system PATH first (Standalone with CLI integration)
        if let whichPath = runCommand("/usr/bin/which", args: ["tailscale"]), !whichPath.isEmpty {
            cliPath = whichPath.trimmingCharacters(in: .whitespacesAndNewlines)
            print("✓ Found Tailscale CLI at: \(cliPath!)")
            return
        }
        
        // Try App Store/Standalone bundle location
        let bundlePath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        if FileManager.default.fileExists(atPath: bundlePath) {
            cliPath = bundlePath
            print("✓ Found Tailscale app at: \(bundlePath)")
            return
        }
        
        print("⚠️ Tailscale not found")
        cliPath = nil
    }
    
    // MARK: - Connection Management
    
    @MainActor
    func connect() async {
        ensureInitialized()
        
        guard !isConnecting else { return }
        
        // Check if CLI is available
        guard let path = cliPath else {
            showDownloadSheet = true
            return
        }
        
        isConnecting = true
        errorMessage = nil
        
        // Check current status first
        checkStatus()
        
        // If already connected, we're done
        if isConnected {
            isConnecting = false
            print("✓ Already connected to Tailscale")
            return
        }
        
        // Run tailscale up
        let output = runCommand(path, args: ["up"])
        
        // Wait a moment for connection to establish
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Start rapid checking for 15 seconds while connecting
        startRapidStatusChecking()
        
        // Check status
        checkStatus()
        
        if !isConnected {
            // Only show error if there's actual output indicating a problem
            if let output = output, !output.isEmpty, output.contains("error") || output.contains("Error") {
                errorMessage = "Connection failed"
                print("❌ Tailscale connection error: \(output)")
            }
        }
        
        isConnecting = false
    }
    
    @MainActor
    func disconnect() async {
        ensureInitialized()
        
        guard let path = cliPath else { return }
        
        // Run tailscale down
        _ = runCommand(path, args: ["down"])
        
        // Update status immediately
        checkStatus()
        
        // Wipe the auth
        UserDefaults.standard.removeObject(forKey: "TailscaleAuth")
        
        print("✓ Tailscale disconnected")
    }
    
    // MARK: - Status Checking
    
    @MainActor
    func checkStatus() {
        ensureInitialized()
        
        guard let path = cliPath else {
            isConnected = false
            return
        }
        
        // Get status (plain text, not JSON)
        guard let statusOutput = runCommand(path, args: ["status"]) else {
            isConnected = false
            return
        }
        
        // Update connection state
        let wasConnected = isConnected
        
        // Check if Tailscale is stopped
        if statusOutput.contains("Tailscale is stopped") {
            isConnected = false
        } else if !statusOutput.isEmpty && statusOutput.contains("100.") {
            // If we have output with Tailscale IPs (100.x.x.x), it's running
            isConnected = true
        } else {
            isConnected = false
        }
        
        // Store auth state
        if isConnected && !wasConnected {
            UserDefaults.standard.set("connected", forKey: "TailscaleAuth")
           // print("✓ Tailscale connected")
        } else if !isConnected && wasConnected {
            UserDefaults.standard.removeObject(forKey: "TailscaleAuth")
          //  print("✓ Tailscale disconnected")
        }
    }
    
    @MainActor
    func startStatusMonitoring() {
        guard !isMonitoring else { return }
        ensureInitialized()
        
        isMonitoring = true
        stopStatusMonitoring()
        
        // Do an immediate check
        checkStatus()
        
        // Start with rapid checking (3 seconds) for initial state
        startRapidStatusChecking()
        
        // After 15 seconds, switch to slow checking
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            await switchToSlowStatusChecking()
        }
    }
    
    @MainActor
    private func startRapidStatusChecking() {
        stopStatusMonitoring()
        
        // Check every 3 seconds (rapid)
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStatus()
            }
        }
      //  print("🔄 Started rapid status checking (3s)")
    }
    
    @MainActor
    private func switchToSlowStatusChecking() {
        guard isMonitoring else { return }
        stopStatusMonitoring()
        
        // Check every 15 seconds (background)
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStatus()
            }
        }
      //  print("🔄 Switched to slow status checking (15s)")
    }
    
    @MainActor
    func stopStatusMonitoring() {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
        isMonitoring = false
    }
    
    // MARK: - Command Execution
    
    private func runCommand(_ command: String, args: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.launchPath = command
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Force CLI mode for Tailscale executable
        var environment = ProcessInfo.processInfo.environment
        environment["TAILSCALE_BE_CLI"] = "1"
        process.environment = environment
        
        do {
          //  print("🔧 Running: \(command) \(args.joined(separator: " "))")
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
           // print("🔧 Exit code: \(process.terminationStatus)")
            // if !output.isEmpty {
            //     print("🔧 Output length: \(output.count)")
            // }
            // if !error.isEmpty {
            //     print("🔧 Error output: \(error)")
            // }
            
            return output.isEmpty ? error : output
        } catch {
          //  print("❌ Failed to run command: \(error)")
            return nil
        }
    }
}

// MARK: - Status Models

struct TailscaleStatus: Codable {
    let BackendState: String
    let selfNode: NodeInfo?
    
    enum CodingKeys: String, CodingKey {
        case BackendState
        case selfNode = "Self"
    }
    
    struct NodeInfo: Codable {
        let HostName: String?
        let TailscaleIPs: [String]?
    }
}

// MARK: - Download Sheet View

struct TailscaleDownloadSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Tailscale Not Installed")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Tailscale is required to connect over your tailnet. Please install it to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button(action: {
                    if let url = URL(string: "https://apps.apple.com/au/app/tailscale/id1475387142?mt=12") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "app.badge")
                        Text("Download from App Store")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Text("Or download from [tailscale.com/download](https://tailscale.com/download)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            Button("Dismiss") {
                isPresented = false
            }
            .padding(.bottom)
        }
        .frame(width: 400)
        .padding()
    }
}
#endif
