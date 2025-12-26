//
//  ServerView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI
import SwiftData
import KeychainAccess
import UniformTypeIdentifiers

struct ServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @Environment(\.horizontalSizeClass) var sizeClass
    
    @Bindable var server: Servers
    let keychain = Keychain(service: "com.srgim.throttle3")
    let isNewServer: Bool
    
    @State private var password: String = ""
    @State private var sshKey: String = ""
    @State private var sshPassword: String = ""
    @State private var showingKeyFilePicker = false
    
    init(server: Servers? = nil) {
        if let server = server {
            self.server = server
            self.isNewServer = false
        } else {
            // Create a new server
            self.server = Servers()
            self.isNewServer = true
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Transmission") {
                    TextField("Server Name", text: $server.name)
                    TextField("Server Address", text: $server.serverAddress)
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif
                    Text("Local, Real World or Tailscale Server Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Server Port", text: $server.serverPort)
                    #if os(iOS)
                        .autocapitalization(.none)
                    
                        .keyboardType(.numberPad)
#endif
                    Toggle("Uses SSL", isOn: $server.usesSSL)
                TextField("Username", text: $server.user)
                    .textContentType(.username)
#if os(iOS)
    .autocapitalization(.none)
#endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            // #if os(macOS)
            // .padding(.bottom, 20)
            // #endif
            Section("Tunnels & SSH") {
                Toggle("Tunnel Over Tailscale", isOn: $server.useTailscale)
                Toggle("Use SSH", isOn: $server.sshOn)
                Text("Used to secure connection & serve files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                 if server.sshOn {
                    
                    TextField("SSH User", text: $server.sshUser)
                        .textContentType(.username)
#if os(iOS)
    .autocapitalization(.none)
#endif


                    
                    if server.sshUsesKey {
                        Button(action: {
                            showingKeyFilePicker = true
                        }) {
                            HStack {
                                Text(sshKey.isEmpty ? "Select Key" : "Change Key")
                                Spacer()
                                Image(systemName: "doc")
                            }
                        }
                        .fileImporter(
                            isPresented: $showingKeyFilePicker,
                            allowedContentTypes: [.data, .text],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                if let url = urls.first {
                                    loadKeyFile(from: url)
                                }
                            case .failure(let error):
                                print("Error selecting key file: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        SecureField("SSH Password", text: $sshPassword)
                            .textContentType(.password)
                    }
                     Toggle("Use SSH Key", isOn: $server.sshUsesKey)
                     TextField("SSH Host", text: $server.sshHost)
 #if os(iOS)
     .autocapitalization(.none)
 #endif
                      Text("If different to Server Host")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                     TextField("SSH Port", text: $server.sshPort)
 #if os(iOS)
     .autocapitalization(.none)
     .keyboardType(.numberPad)
 #endif
                   
                }
                
                if server.sshOn {
                    Toggle("Tunnel Web Over SSH", isOn: $server.tunnelWebOverSSH)
                    Toggle("Serve Files", isOn: $server.serveFilesOverTunnels)
                }
            }
        }
        .navigationTitle(isNewServer ? "Add Server" : "Edit Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        #if os(macOS)
        .padding()
        #endif
        .onAppear {
            loadSecrets()
        }
        }
    }
    
    private func loadSecrets() {
        password = keychain["\(server.id.uuidString)-password"] ?? ""
        sshKey = keychain["\(server.id.uuidString)-sshkey"] ?? ""
        sshPassword = keychain["\(server.id.uuidString)-sshpassword"] ?? ""
    }
    
    private func loadKeyFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Couldn't access file")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let keyContent = try String(contentsOf: url, encoding: .utf8)
            sshKey = keyContent
        } catch {
            print("Error reading key file: \(error.localizedDescription)")
        }
    }
    
    private func saveSecrets() {
        // Add new server to context if it's new
        if isNewServer {
            modelContext.insert(server)
        }
        
        // Save credentials to keychain
        if !password.isEmpty {
            keychain["\(server.id.uuidString)-password"] = password
        }
        if !sshKey.isEmpty {
            keychain["\(server.id.uuidString)-sshkey"] = sshKey
        }
        if !sshPassword.isEmpty {
            keychain["\(server.id.uuidString)-sshpassword"] = sshPassword
        }
        
        // Save model context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save server: \(error)")
        }
    }
}
