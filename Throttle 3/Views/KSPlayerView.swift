//
//  KSPlayerView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 03/01/2026.
//

#if os(iOS)
import SwiftUI
import KSPlayer

/// SwiftUI wrapper for KSPlayer video player
struct KSPlayerView: UIViewRepresentable {
    let url: URL
    var onBack: (() -> Void)?
    
    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let playerView = IOSVideoPlayerView()
        
        // Configure back button behavior
        playerView.backBlock = {
            if UIApplication.shared.statusBarOrientation.isLandscape {
                playerView.updateUI(isLandscape: false)
            } else {
                context.coordinator.onBack?()
            }
        }
        
        return playerView
    }
    
    func updateUIView(_ playerView: IOSVideoPlayerView, context: Context) {
        // Create a KSPlayerResource with the URL
        let resource = KSPlayerResource(url: url, options: KSOptions())
        playerView.set(resource: resource)
        playerView.play()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onBack: onBack)
    }
    
    class Coordinator {
        var onBack: (() -> Void)?
        
        init(onBack: (() -> Void)?) {
            self.onBack = onBack
        }
    }
    
    static func dismantleUIView(_ playerView: IOSVideoPlayerView, coordinator: Coordinator) {
        playerView.resetPlayer()
    }
}

/// Full-screen video player view with dismiss functionality
struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        KSPlayerView(url: url) {
            dismiss()
        }
        .ignoresSafeArea()
    }
}

#endif
