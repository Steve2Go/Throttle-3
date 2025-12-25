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
    @State private var sshPassword: String = ""
    
    init(server: Servers? = nil) {
        if let server = server {
            self.server = server
        } else {
            // Create a new server
            self.server = Servers()
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
                        TextEditor(text: $sshKey)
                            .frame(minHeight: 100)
                            .font(.system(.body, design: .monospaced))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
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
                   
                }
                
                if server.sshOn {
                    Toggle("Tunnel Web Over SSH", isOn: $server.tunnelWebOverSSH)
                    Toggle("Serve Files", isOn: $server.serveFilesOverTunnels)

                    
                    
                }
            }
            // #if os(macOS)
            // .padding(.bottom, 20)
            // #endif
            
//            if server.serveFilesOverTunnels {
//                Section("File Transfer") {
//                    Toggle("Tunnel Files Over SSH", isOn: $server.tunnelFilesOverSSH)
//                    Text("File transfer must be secured by Tailscale / SSH")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                    
////                                        TextField("Download Folder Base Path", text: $server.sftpBase)
////                    #if os(iOS)
////                        .autocapitalization(.none)
////                    #endif
//
////                    TextField("Files Port(optional)", text: $server.tunnelPort)
////#if os(iOS)
////    .autocapitalization(.none)
////
////                        .keyboardType(.numberPad)
////#endif
////                    TextField("Port", text: $server.reverseProxyPort)
////#if os(iOS)
////    .autocapitalization(.none)
////
////                        .keyboardType(.numberPad)
////#endif
////                    
//
//                }
//            }
//        }
//        .navigationTitle("Server Settings")
//            #if os(iOS)
//        .navigationBarTitleDisplayMode(.inline)
//            #endif
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
    
    private func saveSecrets() {
        if !password.isEmpty {
            keychain["\(server.id.uuidString)-password"] = password
        }
        if !sshKey.isEmpty {
            keychain["\(server.id.uuidString)-sshkey"] = sshKey
        }
        if !sshPassword.isEmpty {
            keychain["\(server.id.uuidString)-sshpassword"] = sshPassword
        }
        try? modelContext.save()
    }
}
