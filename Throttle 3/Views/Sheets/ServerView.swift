//
//  ServerView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData
import KeychainAccess

struct ServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var server: Servers
    let keychain = Keychain(service: "com.srgim.throttle3")
    
    @State private var password: String = ""
    @State private var sshKey: String = ""
    
    var body: some View {
        Form {
            Section("Transmission Settings") {
                TextField("Server Name", text: $server.name)
                TextField("URL", text: $server.url)
                    .textContentType(.URL)
                #if os(iOS)
                    .autocapitalization(.none)
                #endif
                TextField("Username", text: $server.user)
                    .textContentType(.username)
#if os(iOS)
    .autocapitalization(.none)
#endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            
            Section("Tunnel") {
                Toggle("Use Tailscale", isOn: $server.useTailscale)
                Toggle("Use SSH", isOn: $server.sshOn)
                
                if server.sshOn {
                    TextField("SSH Host", text: $server.sshHost)
#if os(iOS)
    .autocapitalization(.none)
#endif
                    TextField("SSH User", text: $server.sshUser)
                        .textContentType(.username)
#if os(iOS)
    .autocapitalization(.none)
#endif
                    Toggle("Use SSH Key", isOn: $server.sshUsesKey)
                    
                    if server.sshUsesKey {
                        TextEditor(text: $sshKey)
                            .frame(minHeight: 100)
                            .font(.system(.body, design: .monospaced))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            
            Section("File Transfer") {
                TextField("SFTP Base Path", text: $server.sftpBase)
#if os(iOS)
    .autocapitalization(.none)
#endif
            }
            
        }
        .navigationTitle("Server Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSecrets()
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadSecrets()
        }
    }
    
    private func loadSecrets() {
        password = keychain["\(server.id.uuidString)-password"] ?? ""
        sshKey = keychain["\(server.id.uuidString)-sshkey"] ?? ""
    }
    
    private func saveSecrets() {
        if !password.isEmpty {
            keychain["\(server.id.uuidString)-password"] = password
        }
        if !sshKey.isEmpty {
            keychain["\(server.id.uuidString)-sshkey"] = sshKey
        }
        try? modelContext.save()
    }
}
