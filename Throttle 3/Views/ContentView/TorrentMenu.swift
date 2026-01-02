//
//  TorrentMenu.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 1/1/2026.
//
import SwiftUI
import Transmission
import KeychainAccess
import Combine

struct torrentMenu: View {
    let torrentID: Set<Int>
    let stopped: Bool
    let single: Bool
    let server: Servers
    
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showRenameAlert = false
    @State private var newTorrentName = ""
    @State private var torrentName = ""
    private let keychain = Keychain(service: "com.srgim.throttle3")
    @ObservedObject private var tunnelManager = TunnelManager.shared
    @EnvironmentObject var store: Store
    
    var body: some View {
        
            if single {
                Button {
                    // Files - not implemented yet
                } label: {
                    Label("Files", image:"custom.folder.badge.arrow.down")
                        .symbolRenderingMode(.monochrome)
                }
            }
            Button {
                performAction(.verify)
            } label: {
                Label("Verify", image: "custom.folder.badge.magnifyingglass")
                    .symbolRenderingMode(.monochrome)
            }
            
            if (stopped == true || single == false) {
                Button {
                    performAction(.start)
                } label: {
                    Label("Start", systemImage: "play")
                        .symbolRenderingMode(.monochrome)
                }
            }
            
            if (stopped == false || single == false) {
                
                Button {
                    performAction(.reannounce)
                } label: {
                    Label("Announce", systemImage: "megaphone")
                        .symbolRenderingMode(.monochrome)
                }
                
                Button {
                    performAction(.stop)
                } label: {
                    Label("Stop", systemImage: "stop")
                        .symbolRenderingMode(.monochrome)
                }
            }
             Button {
                    // Move - not implemented yet
                } label: {
                    Label("Move", systemImage: "arrow.forward.folder")
                        .symbolRenderingMode(.monochrome)
                }
            if single {
                Button {
                    promptForRename()
                } label: {
                    Label("Rename", systemImage: "dots.and.line.vertical.and.cursorarrow.rectangle")
                        .symbolRenderingMode(.monochrome)
                }
                .alert("Rename Torrent", isPresented: $showRenameAlert) {
                    TextField("New Name", text: $newTorrentName)
                    Button("Cancel", role: .cancel) {
                        newTorrentName = ""
                    }
                    Button("Rename") {
                        performRename()
                    }
                    .disabled(newTorrentName.isEmpty)
                } message: {
                    Text("Enter a new name for '\(torrentName)'")
                }
            }
            if single {
                Button {
                    // Delete - not implemented yet
                } label: {
                    Label("Delete", systemImage: "trash")
                        .symbolRenderingMode(.monochrome)
                }
            }
            
        } 
    
    // MARK: - Actions
    
    enum TorrentAction {
        case start, stop, verify, reannounce
        
        var methodName: String {
            switch self {
            case .start: return "start"
            case .stop: return "stop"
            case .verify: return "verify"
            case .reannounce: return "reannounce"
            }
        }
    }
    
    private func performAction(_ action: TorrentAction) {
        Task {
            await executeTorrentAction(action)
        }
    }
    
    private func executeTorrentAction(_ action: TorrentAction) async {
        // Ensure tunnel exists and get local port
        guard let port = await tunnelManager.ensureTunnel(for: server) else {
            print("❌ Failed to establish tunnel for torrent action")
            return
        }
        
        // Build Transmission URL using the tunnel port
        let scheme = "http"
        let host = "127.0.0.1"
        let urlString = "\(scheme)://\(host):\(port)\(server.rpcPath)"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        print("🎬 Performing \(action.methodName) on \(torrentID.count) torrent(s)")
        
        // Create Transmission client
        let client = Transmission(baseURL: url, username: server.user, password: password)
        
        // Create request based on action
        let request: Request<Void> = {
            let ids = Array(torrentID) as [Any]
            switch action {
            case .start:
                return .start(ids: ids)
            case .stop:
                return .stop(ids: ids)
            case .verify:
                return .verify(ids: ids)
            case .reannounce:
                return .reannounce(ids: ids)
            }
        }()
        
        // Execute request using Combine
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            var hasResumed = false
            var keepAlive: Set<AnyCancellable> = []
            
            // Set a timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if !hasResumed {
                    hasResumed = true
                    cancellable?.cancel()
                    print("⚠️ \(action.methodName) request timed out after 30 seconds")
                    continuation.resume()
                }
            }
            
            cancellable = client.request(request)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if !hasResumed {
                            hasResumed = true
                            switch completion {
                            case .finished:
                                print("✅ \(action.methodName) completed successfully for \(torrentID.count) torrent(s)")
                                store.successIndicator = true
                            case .failure(let error):
                                print("❌ \(action.methodName) failed: \(error)")
                            }
    
    // MARK: - Rename Action
    
    private func promptForRename() {
        // Get torrent name from store
        if let torrent = store.torrents.first(where: { $0.id == torrentID.first }) {
            torrentName = torrent.name ?? "torrent"
            newTorrentName = torrentName
            showRenameAlert = true
        }
    }
    
    private func performRename() {
        guard !newTorrentName.isEmpty, let torrentId = torrentID.first else { return }
        
        Task {
            await executeRename(torrentId: torrentId, oldName: torrentName, newName: newTorrentName)
        }
    }
    
    private func executeRename(torrentId: Int, oldName: String, newName: String) async {
        // Ensure tunnel exists and get local port
        guard let port = await tunnelManager.ensureTunnel(for: server) else {
            print("❌ Failed to establish tunnel for rename action")
            return
        }
        
        // Build Transmission URL using the tunnel port
        let scheme = "http"
        let host = "127.0.0.1"
        let urlString = "\(scheme)://\(host):\(port)\(server.rpcPath)"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return
        }
        
        // Get password from keychain
        let password = keychain["\(server.id.uuidString)-password"] ?? ""
        
        print("🎬 Renaming torrent \(torrentId) from '\(oldName)' to '\(newName)'")
        
        // Create Transmission client
        let client = Transmission(baseURL: url, username: server.user, password: password)
        
        // Create custom rename request
        // Method: torrent-rename-path
        // Args: ids (array with single torrent), path (old name), name (new name)
        let request = Request<RenameResponse>(
            method: "torrent-rename-path",
            args: [
                "ids": [torrentId],
                "path": oldName,
                "name": newName
            ],
            transform: { response in
                guard let arguments = response["arguments"] as? [String: Any],
                      let resultPath = arguments["path"] as? String,
                      let resultName = arguments["name"] as? String,
                      let resultId = arguments["id"] as? Int
                else {
                    return .failure(.unexpectedResponse)
                }
                
                return .success(RenameResponse(path: resultPath, name: resultName, id: resultId))
            }
        )
        
        // Execute request using Combine
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            var hasResumed = false
            var keepAlive: Set<AnyCancellable> = []
            
            // Set a timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if !hasResumed {
                    hasResumed = true
                    cancellable?.cancel()
                    print("⚠️ Rename request timed out after 30 seconds")
                    continuation.resume()
                }
            }
            
            cancellable = client.request(request)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if !hasResumed {
                            hasResumed = true
                            switch completion {
                            case .finished:
                                break // Success message handled in receiveValue
                            case .failure(let error):
                                print("❌ Rename failed: \(error)")
                            }
                            continuation.resume()
                        }
                    },
                    receiveValue: { response in
                        print("✅ Successfully renamed to '\(response.name)'")
                    }
                )
            
            if let cancellable = cancellable {
                // Keep the cancellable alive until the request completes
                keepAlive.insert(cancellable)
            }
        }
    }
}

// MARK: - Supporting Types

struct RenameResponse {
    let path: String
    let name: String
    let id: Int                           continuation.resume()
                        }
                    },
                    receiveValue: { _ in
                        // Void response, nothing to process
                    }
                )
            
            if let cancellable = cancellable {
                // Keep the cancellable alive until the request completes
                keepAlive.insert(cancellable)
            }
        }
    }
}
