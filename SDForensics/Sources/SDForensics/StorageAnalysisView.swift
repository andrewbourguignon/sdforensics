import SwiftUI

struct StorageAnalysisView: View {
    @ObservedObject var stateManager: AppStateManager
    @State private var searchText = ""
    @State private var sortAscending = false
    @State private var sortByFilename = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Analysis")
                        .font(.title)
                        .bold()
                    Text("Deep-dive file structures, camera directory profiles, and media clips.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: { stateManager.analyzeStorage() }) {
                    Label("Re-Scan Volume", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(stateManager.selectedDisk == nil || stateManager.selectedDisk?.isMock == true)
            }
            
            if stateManager.selectedDisk == nil {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No connected device selected.")
                        .font(.title3)
                        .bold()
                    Text("Please connect and select an SD card in the Dashboard.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(12)
            } else if stateManager.isAnalyzingStorage {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing filesystem structure...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let analysis = getAnalysis()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Summary Bento Row
                        HStack(spacing: 16) {
                            SummaryMetricCard(
                                title: "TOTAL FILES",
                                value: "\(analysis.totalFiles)",
                                subtitle: "Index files + media files",
                                icon: "doc.text.fill",
                                color: .blue
                            )
                            
                            SummaryMetricCard(
                                title: "TOTAL MEDIA SIZE",
                                value: formatBytes(analysis.totalSizeBytes),
                                subtitle: "Occupied byte-count",
                                icon: "folder.fill",
                                color: .green
                            )
                            
                            SummaryMetricCard(
                                title: "CAMERA PROFILE",
                                value: analysis.cameraStructure?.rawValue ?? "Generic / Data",
                                subtitle: "Directory marker format",
                                icon: "camera.fill",
                                color: .purple
                            )
                        }
                        
                        HStack(alignment: .top, spacing: 20) {
                            // Left: File Type Breakdown Chart
                            VStack(alignment: .leading, spacing: 16) {
                                Text("File Type Breakdown")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                FileTypeBreakdownView(
                                    breakdown: analysis.fileTypeBreakdown,
                                    totalBytes: analysis.totalSizeBytes
                                )
                            }
                            .padding(20)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(12)
                            
                            // Right: Top 10 Largest Files
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Largest Files (Top 10)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                LargestFilesView(files: analysis.largestFiles)
                            }
                            .padding(20)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(12)
                        }
                        
                        // Media Clip Explorer Panel
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Media Clip Explorer (\(analysis.clipEntries.count) Clips)")
                                    .font(.headline)
                                
                                Spacer()
                                
                                // Search bar
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                    TextField("Search by filename...", text: $searchText)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .frame(width: 180)
                                    if !searchText.isEmpty {
                                        Button(action: { searchText = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                
                                // Sorting Toggle
                                Button(action: {
                                    if sortByFilename {
                                        sortAscending.toggle()
                                    } else {
                                        sortByFilename = true
                                        sortAscending = false
                                    }
                                }) {
                                    HStack {
                                        Text("Name")
                                        Image(systemName: sortByFilename ? (sortAscending ? "chevron.up" : "chevron.down") : "line.3.horizontal")
                                    }
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: {
                                    if !sortByFilename {
                                        sortAscending.toggle()
                                    } else {
                                        sortByFilename = false
                                        sortAscending = true
                                    }
                                }) {
                                    HStack {
                                        Text("Size")
                                        Image(systemName: !sortByFilename ? (sortAscending ? "chevron.up" : "chevron.down") : "line.3.horizontal")
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if filteredClips(analysis.clipEntries).isEmpty {
                                Text("No clips match the filter.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            } else {
                                ClipGridList(clips: filteredClips(analysis.clipEntries))
                            }
                        }
                        .padding(20)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(30)
    }
    
    // Helpers
    private func getAnalysis() -> StorageAnalysis {
        if stateManager.selectedDisk?.isMock == true {
            return mockAnalysis
        }
        return stateManager.storageAnalysis ?? emptyAnalysis
    }
    
    private func filteredClips(_ clips: [ClipEntry]) -> [ClipEntry] {
        var result = clips
        if !searchText.isEmpty {
            result = clips.filter { $0.filename.localizedCaseInsensitiveContains(searchText) }
        }
        
        result.sort { a, b in
            if sortByFilename {
                return sortAscending ? a.filename < b.filename : a.filename > b.filename
            } else {
                return sortAscending ? a.sizeBytes < b.sizeBytes : a.sizeBytes > b.sizeBytes
            }
        }
        return result
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    
    private var emptyAnalysis: StorageAnalysis {
        StorageAnalysis(
            totalFiles: 0,
            totalSizeBytes: 0,
            freeSpaceBytes: 0,
            capacityBytes: 0,
            fileTypeBreakdown: [],
            largestFiles: [],
            cameraStructure: .unknown,
            clipEntries: [],
            recordingDates: []
        )
    }
    
    private var mockAnalysis: StorageAnalysis {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let baseDate = formatter.date(from: "2026-06-20 10:00") ?? Date()
        
        var clips = [ClipEntry]()
        for i in 1...210 {
            let number = String(format: "%04d", i + 2400)
            let duration = Double.random(in: 15...420) // 15s to 7m
            let size = UInt64(duration * 9_500_000 * Double.random(in: 0.95...1.05)) // ~9.5MB/s for Sony XAVC-S 4K 100Mbps
            let date = baseDate.addingTimeInterval(Double(i) * 3600 * 2)
            clips.append(ClipEntry(
                filename: "C\(number).MP4",
                path: "/Volumes/MOCK_CARD/PRIVATE/M4ROOT/CLIP/C\(number).MP4",
                sizeBytes: size,
                duration: duration,
                resolution: "3840×2160",
                codec: "H.264",
                creationDate: date,
                audioChannels: 2
            ))
        }
        
        let totalSize = clips.reduce(0) { $0 + $1.sizeBytes }
        
        let fileTypes = [
            FileTypeGroup(extension_: "MP4", count: 210, totalSizeBytes: totalSize),
            FileTypeGroup(extension_: "XML", count: 210, totalSizeBytes: 210 * 3072),
            FileTypeGroup(extension_: "BIN", count: 4, totalSizeBytes: 4 * 1024 * 1024)
        ]
        
        let largest = clips.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(10).map {
            FileEntry(name: $0.filename, path: $0.path, sizeBytes: $0.sizeBytes, modifiedDate: $0.creationDate)
        }
        
        return StorageAnalysis(
            totalFiles: 424,
            totalSizeBytes: totalSize,
            freeSpaceBytes: 24_000_000_000,
            capacityBytes: 256_000_000_000,
            fileTypeBreakdown: fileTypes,
            largestFiles: largest,
            cameraStructure: .sonyXAVC,
            clipEntries: clips,
            recordingDates: clips.compactMap { $0.creationDate }
        )
    }
}

// Summary metric card
struct SummaryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2)
                    .bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// File type breakdown bar chart
struct FileTypeBreakdownView: View {
    let breakdown: [FileTypeGroup]
    let totalBytes: UInt64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if breakdown.isEmpty {
                Text("No data to display")
                    .foregroundColor(.secondary)
            } else {
                ForEach(breakdown) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.extension_)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(group.count) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(group.totalSizeFormatted)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(totalBytes > 0 ? Double(group.totalSizeBytes) / Double(totalBytes) : 0.0), height: 8),
                                    alignment: .leading
                                )
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }
}

// Top 10 largest files list
struct LargestFilesView: View {
    let files: [FileEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if files.isEmpty {
                Text("No files analyzed")
                    .foregroundColor(.secondary)
            } else {
                ForEach(files) { file in
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.secondary)
                        Text(file.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(file.sizeFormatted)
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    Divider()
                }
            }
        }
    }
}

// Clip Grid List view
struct ClipGridList: View {
    let clips: [ClipEntry]
    
    var body: some View {
        VStack(spacing: 0) {
            // Column Headers
            HStack(spacing: 12) {
                Text("Filename")
                    .fontWeight(.bold)
                    .frame(width: 140, alignment: .leading)
                Text("Duration")
                    .fontWeight(.bold)
                    .frame(width: 90, alignment: .leading)
                Text("Resolution")
                    .fontWeight(.bold)
                    .frame(width: 100, alignment: .leading)
                Text("Codec")
                    .fontWeight(.bold)
                    .frame(width: 80, alignment: .leading)
                Text("Size")
                    .fontWeight(.bold)
                    .frame(width: 100, alignment: .leading)
                Text("Recording Date")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, 10)
            
            Divider()
                .padding(.bottom, 8)
            
            // Scrollable Rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(clips) { clip in
                        HStack(spacing: 12) {
                            Text(clip.filename)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .frame(width: 140, alignment: .leading)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.purple)
                                Text(clip.durationFormatted)
                            }
                            .frame(width: 90, alignment: .leading)
                            
                            Text(clip.resolution)
                                .frame(width: 100, alignment: .leading)
                            
                            Text(clip.codec)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            
                            Text(clip.sizeFormatted)
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .leading)
                            
                            Text(formatDate(clip.creationDate))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 8)
                        
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 350)
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let d = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: d)
    }
}
