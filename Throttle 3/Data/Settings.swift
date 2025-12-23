//
//  Settings.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import Foundation
import SwiftData

@Model
final class Settings {
    var id: UUID = UUID()
    var deleteTorrents: Bool = false
    var refreshRate: Int = 30
    
    init(id: UUID = UUID(), deleteTorrents: Bool = false, refreshRate: Int = 30) {
        self.id = id
        self.deleteTorrents = deleteTorrents
        self.refreshRate = refreshRate
    }
}
