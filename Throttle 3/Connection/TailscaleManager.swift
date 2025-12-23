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
