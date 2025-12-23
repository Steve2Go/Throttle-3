//
//  ConnectingView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI


struct ConnectingView: View {
    var icon: String = "ellipsis"
    
    var body: some View {
        ContentUnavailableView{
            Label("Connecting", systemImage: icon)
                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 0.0)))
        }
    }
    
}
// tailscale icon square.grid.3x3.topleft.filled
// ssh icon externaldrive.connected.to.line.below
// transmission externaldrive.badge.icloud
