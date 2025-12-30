//
//  ShortTerm.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine


class Store: NSObject, ObservableObject {
    @AppStorage("instance") var instance : String = ""
    @Published var TailscaleState: Bool = false
    @Published var sshState: Bool = false
    @Published var currentServerID: UUID?
    @Published var sharedUrl: String?
    @Published var didLoad: Bool = false
    @Published var showTailscaleSheet: Bool = false
    @Published var showAddServer: Bool = false
}
