//
//  TailscaleToggle.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI

struct TailscaleToggle: View {
    @AppStorage("TailscaleAuth") var tailscaleAuth: String?
    @State private var isEnabled: Bool = false
    
    var body: some View {
        List {
            Section("Tailscale") {
                Toggle("Connect Over Tailscale", isOn: $isEnabled)
                
                if isEnabled {
                    if let auth = tailscaleAuth, !auth.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected")
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Not Authenticated")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            isEnabled = tailscaleAuth != nil && !tailscaleAuth!.isEmpty
        }
    }
}
