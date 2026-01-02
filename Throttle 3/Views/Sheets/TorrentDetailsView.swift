//
//  TorrentDetailsView.swift
//  Throttle 3
//
//  Created by Stephen Grigg on 30/12/2025.
//

import SwiftUI
import Transmission

struct TorrentDetailsView: View {
    let torrent: Torrent
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameSection
                    statusSection
                    Divider()
                    linksSection
                    Divider()
                    transferAndSizeSection
                    Divider()
                    peersAndDateSection
                    trackersSection
                    hashSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Torrent Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction ) {
                    Menu {
                        torrentMenu(torrentID: Set([torrent.id!]), stopped: torrent.status?.rawValue == 0 ? true : false, single: true)
                    } label: {
                        #if os(iOS)
                        Image(systemName: "ellipsis.circle")
                        #else
                        Text("Torrent Actions")
                        #endif
                    }
                }
            }
        }
    }
    
    // MARK: - Section Views
    
    private var nameSection: some View {
        Section {
            Text(torrent.name ?? "Unknown Torrent")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
    }
    
    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Status")
                
                HStack(spacing: 20) {
                    InfoRow(
                        label: "Status",
                        value: statusText(for: torrent.status?.rawValue),
                        icon: iconForStatus(torrent.status?.rawValue)
                    )
                    
                    Spacer()
                    
                    InfoRow(
                        label: "Progress",
                        value: progressText(torrent.progress),
                        icon: "chart.bar.fill"
                    )
                }
                
                if let progress = torrent.progress {
                    let progressValue: Double = Double(progress)
                    ProgressView(value: progressValue)
                        .tint(progressColor(for: torrent.status?.rawValue))
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var linksSection: some View {
        if let hash = torrent.hash {
            let magnetLink = "magnet:?xt=urn:btih:\(hash)"
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Links")
                    
                    LinkRow(
                        label: "Magnet Link",
                        icon: "link",
                        action: {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(magnetLink, forType: .string)
                            #else
                            UIPasteboard.general.string = magnetLink
                            #endif
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var transferAndSizeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Transfer & Size")
                
                HStack(alignment: .top, spacing: 20) {
                    // Transfer column
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(
                            label: "Downloaded",
                            value: formatBytes(downloadedBytes()),
                            icon: "arrow.down.circle.fill"
                        )
                        
                        InfoRow(
                            label: "Uploaded",
                            value: formatBytes(torrent.uploaded ?? 0),
                            icon: "arrow.up.circle.fill"
                        )
                        
                        InfoRow(
                            label: "Down Speed",
                            value: formatSpeed(torrent.downloadRate ?? 0),
                            icon: "speedometer"
                        )
                        
                        InfoRow(
                            label: "Up Speed",
                            value: formatSpeed(torrent.uploadRate ?? 0),
                            icon: "speedometer"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Size column
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(
                            label: "Total Size",
                            value: formatBytes(torrent.size ?? 0),
                            icon: "internaldrive"
                        )
                        
                        InfoRow(
                            label: "Verified",
                            value: formatBytes(torrent.bytesValid ?? 0),
                            icon: "checkmark.circle"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var peersAndDateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Peers & Info")
                
                HStack(alignment: .top, spacing: 20) {
                    // Peers column
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(
                            label: "Connected",
                            value: "\(torrent.totalPeers ?? 0)",
                            icon: "person.2"
                        )
                        
                        InfoRow(
                            label: "Seeds",
                            value: "\(torrent.seeds ?? 0)",
                            icon: "arrow.down.to.line"
                        )
                        
                        InfoRow(
                            label: "Leeches",
                            value: "\(torrent.peers ?? 0)",
                            icon: "arrow.up.to.line"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Date column
                    VStack(alignment: .leading, spacing: 8) {
                        if let dateAdded = torrent.dateAdded {
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    label: "Added",
                                    value: "",
                                    icon: "plus.app"
                                )
                                
                                InfoRow(
                                    label: "Date",
                                    value: "\(formatDate(dateAdded))",
                                    icon: "clock"
                                )
                                
                                InfoRow(
                                    label: "Time",
                                    value: "\(formatTime(dateAdded))",
                                    icon: "calendar"
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                           
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var trackersSection: some View {
        if let trackers = torrent.trackers, !trackers.isEmpty {
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Trackers (\(trackers.count))")
                    
                    ForEach(Array(trackers.enumerated()), id: \.element.id) { index, tracker in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                
                                Text(tracker.host)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            
                            if index < trackers.count - 1 {
                                Divider()
                                    .padding(.leading, 32)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var hashSection: some View {
        if let hash = torrent.hash {
            Divider()
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Hash")
                    Text(hash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Functions
    
    private func statusText(for status: Int?) -> String {
        switch status {
        case 0: return "Stopped"
        case 1: return "Queued to Verify"
        case 2: return "Verifying"
        case 3: return "Queued to Download"
        case 4: return "Downloading"
        case 5: return "Queued to Seed"
        case 6: return "Seeding"
        default: return "Unknown"
        }
    }
    
    private func iconForStatus(_ status: Int?) -> String {
        switch status {
        case 0: return "xmark.circle"
        case 1, 3, 5: return "clock"
        case 2: return "checkmark.circle.trianglebadge.exclamationmark"
        case 4: return "arrow.down.circle"
        case 6: return "arrow.up.circle"
        default: return "questionmark.circle"
        }
    }
    
    private func progressColor(for status: Int?) -> Color {
        switch status {
        case 0: return .red
        case 2: return .yellow
        case 4: return .blue
        case 6: return .green
        default: return .gray
        }
    }
    
    private func progressText(_ progress: Float?) -> String {
        guard let progress = progress else { return "0%" }
        return String(format: "%.1f%%", Double(progress) * 100)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond == 0 {
            return "0 B/s"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytesPerSecond) + "/s"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func downloadedBytes() -> Int64 {
        let size = torrent.size ?? 0
        let progress = torrent.progress ?? 0
        return Int64(Float(size) * progress)
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct LinkRow: View {
    let label: String
    let icon: String
    var subtitle: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .foregroundStyle(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }
}


