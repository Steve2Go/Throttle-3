//
//  ConnectingView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI


struct ConnectingView: View {
    var icon: String = "ellipsis"
    var service = ""
    
    var body: some View {
        
        HStack {
            Image(systemName: icon)
                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.5)))
            Text("Connecting" + service + "...")
        }
    }
    
}
// tailscale icon square.grid.3x3.topleft.filled
// ssh icon externaldrive.connected.to.line.below
// transmission externaldrive.badge.icloud
