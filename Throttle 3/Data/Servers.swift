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
    var url: String = ""
    var sshHost: String = ""
    var user: String = ""
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
    var sftpBase: String = ""
    var useTailscale: Bool = false
    
    init(name: String = "", id: UUID = UUID(), url: String = "", user: String = "", sshOn: Bool = false, sshHost: String = "", sshUser: String = "", sshUsesKey: Bool = false, sftpBase: String = "", useTailscale: Bool = false) {
        self.name = name
        self.id = id
        self.url = url
        self.user = user
        self.sshHost = sshHost
        self.sshOn = sshOn
        self.sshUser = sshUser
        self.sshUsesKey = sshUsesKey
        self.sftpBase = sftpBase
        self.useTailscale = useTailscale
    }
}
