//
//  Servers.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftData

@Model
final class Servers {
    var name : String = ""
    var id: UUID = UUID()
    var serverAddress: String = ""
    var serverPort: String = ""
    var usesSSL: Bool = true
    var url: String = ""
    var sshHost: String = ""
    var user: String = ""
    var rpcPath: String = "/transmission/rpc"
    var sshAddress: String? {
        if sshOn && !sshHost.isEmpty {
            return "\(sshUser)@\(url)"
        } else {
            return nil
        }
    }
    
    var isLocal: Bool {
        let localInstanceID = UserDefaults.standard.string(forKey: "instance") ?? ""
        return localInstanceID == id.uuidString
    }
    var sshOn: Bool = false
    var sshUser: String = ""
    var sshUsesKey: Bool = false
    var sshPort: String = "22"
    var tunnelWebOverSSH: Bool = false
    var tunnelFilesOverSSH: Bool = false
    var tunnelPort: String = ""
    var reverseProxyPort: String = ""
    var sftpBase: String = ""
    var useTailscale: Bool = false
    var serveFilesOverTunnels: Bool = false
    
    init(name: String = "", id: UUID = UUID(), serverAddress: String = "", serverPort: String = "", usesSSL: Bool = false, url: String = "", user: String = "", rpcPath: String = "/transmission/rpc", sshOn: Bool = false, sshHost: String = "", sshUser: String = "", sshUsesKey: Bool = false, sshPort: String = "22", tunnelWebOverSSH: Bool = false, tunnelFilesOverSSH: Bool = false, tunnelPort: String = "", reverseProxyPort: String = "", sftpBase: String = "", useTailscale: Bool = false, serveFilesOverTunnels: Bool = false) {
        self.name = name
        self.id = id
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.usesSSL = usesSSL
        self.url = url
        self.user = user
        self.rpcPath = rpcPath
        self.sshHost = sshHost.isEmpty ? serverAddress : sshHost
        self.sshOn = sshOn
        self.sshUser = sshUser
        self.sshUsesKey = sshUsesKey
        self.sshPort = sshPort
        self.tunnelWebOverSSH = tunnelWebOverSSH
        self.tunnelFilesOverSSH = tunnelFilesOverSSH
        self.tunnelPort = tunnelPort
        self.reverseProxyPort = reverseProxyPort
        self.sftpBase = sftpBase
        self.useTailscale = useTailscale
        self.serveFilesOverTunnels = serveFilesOverTunnels
    }
}
