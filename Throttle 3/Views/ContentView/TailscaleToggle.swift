//
//  TailscaleToggle.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI

struct TailscaleToggle: View {
    @StateObject private var manager = TailscaleManager.shared
    @AppStorage("TailscaleAuth") var tailscaleAuth: String?
    
    var body: some View {
        List {
            Section("Tailscale") {
                Toggle("Connect Over Tailscale", isOn: Binding(
                    get: { manager.isConnected || manager.isConnecting },
                    set: { enabled in
                        Task {
                            if enabled {
                                await manager.connect()
                            } else {
                                await manager.disconnect()
                            }
                        }
                    }
                ))
                .disabled(manager.isConnecting)
                
                if manager.isConnecting {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .foregroundStyle(.secondary)
                    }
                } else if manager.isConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected")
                    }
                } else if let error = manager.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
