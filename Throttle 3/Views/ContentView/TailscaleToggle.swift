//
//  TailscaleToggle.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI

struct TailscaleToggle: View {
    @ObservedObject private var manager = TailscaleManager.shared
    @AppStorage("TailscaleEnabled") private var tailscaleEnabled = false
    
    #if os(iOS)
    var label: String = "Connect Over Tailscale"
    #else
    var label: String = "Managed Tailscale Connection"
    #endif
    var body: some View {
        List {
            Section("Tailscale") {
                Toggle(label, isOn: Binding(
                    get: { tailscaleEnabled },
                    set: { enabled in
                        tailscaleEnabled = enabled
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
        #if os(iOS)
        .onOpenURL { url in
            // Handle Tailscale auth callback
            if url.scheme == "throttle" {
                print("✓ Received auth callback URL")
            }
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $manager.showDownloadSheet) {
            TailscaleDownloadSheet(isPresented: $manager.showDownloadSheet)
        }
        .onAppear {
            manager.startStatusMonitoring()
        }
        .onDisappear {
            manager.stopStatusMonitoring()
        }
        #endif
    }
}
