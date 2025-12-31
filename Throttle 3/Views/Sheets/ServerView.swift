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
    @State private var showingDeleteAlert = false
    //var tailscaleManager = TailscaleManager.shared
    
    init(server: Servers? = nil) {
        if let server = server {
            self.server = server
            self.isNewServer = false
        } else {
            // Create a new server
            self.server = Servers()
            self.isNewServer = true
            self.server.sshOn = true
            self.server.tunnelWebOverSSH = true
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
                    TextField("RPC Path", text: $server.rpcPath)
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif
                    Text("Default: /transmission/rpc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Tunnel Over Tailscale", isOn: $server.useTailscale)
//                    .onChange(of: server.useTailscale) { oldValue, newValue in
//                        Task {
//                            await tailscaleManager.disconnect()
//                        }
//                    }
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
            Section("SSH Control Connection") {
                // Text("Used to secure connection / serve files")
                //     .font(.caption)
                //     .foregroundStyle(.secondary)
                 if server.sshOn {
                    
                    TextField("SSH User", text: $server.sshUser)
                        .textContentType(.username)
                        .onChange(of: server.sshUser) { oldValue, newValue in
                            if oldValue != newValue {
                                server.ffmpegInstalled = false
                            }
                        }
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
//                     TextField("SSH Host", text: $server.sshHost)
 #if os(iOS)
//     .autocapitalization(.none)
 #endif
//                      Text("If different to Server Host")
//                          .font(.caption)
//                          .foregroundStyle(.secondary)
                     TextField("SSH Port", text: $server.sshPort)
 #if os(iOS)
     .autocapitalization(.none)
     .keyboardType(.numberPad)
 #endif
                   
                }
                
                if server.sshOn {
                    // Toggle("Tunnel Web Over SSH", isOn: $server.tunnelWebOverSSH)
                    //     .onChange(of: server.tunnelWebOverSSH) { oldValue, newValue in
                    //         if !newValue && !server.usesSSL {
                    //             server.usesSSL = true
                    //         }
                    //     }
                }
            }
            
            if !isNewServer {
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Server")
                            Spacer()
                        }
                    }
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
        .alert("Delete Server?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteServer()
            }
        } message: {
            Text("This will permanently delete \(server.name) and all its settings.")
        }
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
            server.sshOn = true
            server.tunnelWebOverSSH = true
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
    
    private func deleteServer() {
        // Delete credentials from keychain
        keychain["\(server.id.uuidString)-password"] = nil
        keychain["\(server.id.uuidString)-sshkey"] = nil
        keychain["\(server.id.uuidString)-sshpassword"] = nil
        
        // Delete server from context
        modelContext.delete(server)
        
        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete server: \(error)")
        }
        
        dismiss()
    }
}
