//
//  ConnectingView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 23/12/2025.
//

import SwiftUI


struct FirstRunView: View {
    
    var body: some View {
        ContentUnavailableView{
            Label("Welcome.\nAdd a server to get started", systemImage: "figure.wave")
        }
        BasicSettings()
        TailscaleToggle()
        Button("Add your first Server"){
            
        }
        .padding(.top)
        .buttonStyle(.bordered)
        Spacer()
    }
    
}
// tailscale icon square.grid.3x3.topleft.filled
// ssh icon externaldrive.connected.to.line.below
// transmission externaldrive.badge.icloud
