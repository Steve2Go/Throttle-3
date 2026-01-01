//
//  TorrentMenu.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 1/1/2026.
//
import SwiftUI
import Transmission

struct torrentMenu: View {
    let torrentID: Int
    let stopped: Bool
    var body: some View {
        Menu {
            Button {
                
            } label: {
                Label("Files", image:"custom.folder.badge.arrow.down")
                    .symbolRenderingMode(.monochrome)
            }
            Button {
                
            } label: {
                Label("Verify", image: "custom.folder.badge.magnifyingglass")
                    .symbolRenderingMode(.monochrome)
            }
            
            if stopped {
                Button {
                    
                } label: {
                    Label("Start", systemImage: "play")
                        .symbolRenderingMode(.monochrome)
                }
            } else {
                
                Button {
                    
                } label: {
                    Label("Announce", systemImage: "megaphone")
                        .symbolRenderingMode(.monochrome)
                }
                
                Button {
                    
                } label: {
                    Label("Stop", systemImage: "stop")
                        .symbolRenderingMode(.monochrome)
                }
            }
            Button {
                
            } label: {
                Label("Rename", systemImage: "dots.and.line.vertical.and.cursorarrow.rectangle")
                    .symbolRenderingMode(.monochrome)
            }
            Button {
                
            } label: {
                Label("Delete", systemImage: "trash")
                    .symbolRenderingMode(.monochrome)
            }
            
        } label: {

            Image(systemName: "ellipsis.circle")
                
        }
        .foregroundStyle(.primary)
        
    }
    
}
