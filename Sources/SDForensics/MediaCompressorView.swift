import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct ImageFileEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let originalSizeBytes: Int64
    var compressedSizeBytes: Int64?
    var status: String = "Pending" // "Pending", "Compressing", "Compressed", "Skipped", "Failed"
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: originalSizeBytes, countStyle: .file)
    }
    
    var compressedSizeFormatted: String {
        guard let size = compressedSizeBytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct FileProgressBar: View {
    let status: String
    @State private var indeterminateOffset: CGFloat = -100.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 4)
                
                // Active Fill
                if status == "Compressed" {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.macAccent)
                        .frame(width: geo.size.width, height: 4)
                } else if status == "Compressing" {
                    // Indeterminate animated fill or pulsating fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.macAccent)
                        .frame(width: geo.size.width * 0.3, height: 4)
                        .offset(x: indeterminateOffset)
                        .onAppear {
                            withAnimation(Animation.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                indeterminateOffset = geo.size.width - (geo.size.width * 0.3)
                            }
                        }
                } else if status == "Skipped" {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: geo.size.width, height: 4)
                } else if status == "Failed" {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.7))
                        .frame(width: geo.size.width, height: 4)
                }
            }
        }
        .frame(height: 4)
    }
}

struct MediaCompressorView: View {
    @ObservedObject var stateManager: AppStateManager
    
    @State private var targetFolderPath: String = ""
    @State private var foundImages: [ImageFileEntry] = []
    @State private var isScanning = false
    @State private var isCompressing = false
    @State private var compressionProgress = 0.0
    @State private var compressionQuality = 1.0 // Default to 100%
    @State private var resizeDimension: ResizeLimit = .original
    @State private var totalBytesSaved: Int64 = 0
    @State private var compressionStatus = ""
    @State private var isTargeted = false
    
    enum ResizeLimit: String, CaseIterable, Identifiable {
        case original = "Original Resolution"
        case mp24 = "24 MP (6000px max)"
        case mp12 = "12 MP (4000px max)"
        case mp8 = "8 MP (3264px max)"
        case mp4 = "4 MP (2400px max)"
        
        var id: String { self.rawValue }
        
        var maxPixelSize: CGFloat? {
            switch self {
            case .original: return nil
            case .mp24: return 6000
            case .mp12: return 4000
            case .mp8: return 3264
            case .mp4: return 2400
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media Compressor & Space Saver")
                        .font(.title)
                        .bold()
                    Text("Drag images here to instantly optimize and shrink file sizes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Photo actuations count badge
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack.fill")
                        .foregroundColor(.macAccent)
                    Text("Total Compressed: \(stateManager.totalPhotosCompressed)")
                        .bold()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.macAccent.opacity(0.15))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.macAccent.opacity(0.25), lineWidth: 1)
                )
            }
            
            // Preferences / Settings Bar (Horizontal layout)
            HStack(spacing: 24) {
                // Quality slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Compression Quality:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(Int(compressionQuality * 100))%")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.macAccent)
                    }
                    Slider(value: $compressionQuality, in: 0.3...1.0, step: 0.05)
                        .accentColor(.macAccent)
                        .frame(width: 220)
                }
                
                // Resolution scaling
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolution Scaling:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Picker("Resize Limit", selection: $resizeDimension) {
                        ForEach(ResizeLimit.allCases) { limit in
                            Text(limit.rawValue).tag(limit)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 180)
                }
                
                // Select Folder (manual override)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual Import:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Button(action: selectFolder) {
                        Label("Choose Folder...", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanning || isCompressing)
                }
                
                Spacer()
                
                // Reclaimed space summary
                if totalBytesSaved > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Reclaimed Space")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: totalBytesSaved, countStyle: .file))
                            .font(.title3)
                            .bold()
                            .foregroundColor(.macAccent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.macAccent.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
            .cornerRadius(12)
            
            // Giant Drag & Drop Workspace
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 48))
                    .foregroundColor(isTargeted ? .macAccent : .secondary.opacity(0.7))
                    .scaleEffect(isTargeted ? 1.05 : 1.0)
                    .animation(.spring(), value: isTargeted)
                
                Text(isTargeted ? "Drop Files to Compress!" : "Drag & Drop Folders or Images Here")
                    .font(.title3)
                    .bold()
                    .foregroundColor(isTargeted ? .macAccent : .primary)
                
                Text("Supports JPEGs, PNGs, and HEICs. Optimization begins instantly upon drop.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isTargeted ? Color.macAccent : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(isTargeted ? Color.macAccent.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.15))
            )
            .onDrop(of: [.fileURL, .item], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            
            // History Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Compression Session Log")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if isCompressing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text(compressionStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if foundImages.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No images processed in this session.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Drag files or folders above to begin.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.1))
                    .cornerRadius(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(foundImages) { entry in
                                VStack(spacing: 8) {
                                    HStack(spacing: 16) {
                                        // Status Icon
                                        statusIcon(for: entry.status)
                                            .font(.title3)
                                        
                                        // Name & Path
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.bold)
                                                .lineLimit(1)
                                            Text(entry.path)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        // Size mapping
                                        HStack(spacing: 12) {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("Original")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(entry.sizeFormatted)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                            
                                            if let comp = entry.compressedSizeBytes {
                                                Image(systemName: "arrow.right")
                                                    .foregroundColor(.secondary)
                                                    .font(.caption)
                                                
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Compressed")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(ByteCountFormatter.string(fromByteCount: comp, countStyle: .file))
                                                        .font(.subheadline)
                                                        .bold()
                                                        .foregroundColor(.macAccent)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Row Progress Bar
                                    FileProgressBar(status: entry.status)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(30)
        .onDrop(of: [.fileURL, .item], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "Compressing":
            return Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.macAccent)
        case "Compressed":
            return Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.macAccent)
        case "Skipped":
            return Image(systemName: "arrow.right.circle")
                .foregroundColor(.orange)
        case "Failed":
            return Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        default:
            return Image(systemName: "ellipsis.circle")
                .foregroundColor(.secondary)
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.targetFolderPath = url.path
                self.processDroppedURLs([url])
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urlsToProcess = [URL]()
        let lock = NSLock()
        
        for provider in providers {
            group.enter()
            
            // Check if we can load URL object directly
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        lock.lock()
                        urlsToProcess.append(url)
                        lock.unlock()
                        group.leave()
                    } else {
                        // Fallback to loading item as public.file-url
                        _ = provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                            if let url = item as? URL {
                                lock.lock()
                                urlsToProcess.append(url)
                                lock.unlock()
                            } else if let data = item as? Data,
                                      let urlString = String(data: data, encoding: .utf8),
                                      let url = URL(string: urlString) {
                                lock.lock()
                                urlsToProcess.append(url)
                                lock.unlock()
                            }
                            group.leave()
                        }
                    }
                }
            } else {
                // No URL object ability, try public.file-url directly
                _ = provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    if let url = item as? URL {
                        lock.lock()
                        urlsToProcess.append(url)
                        lock.unlock()
                    } else if let data = item as? Data,
                              let urlString = String(data: data, encoding: .utf8),
                              let url = URL(string: urlString) {
                        lock.lock()
                        urlsToProcess.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            self.processDroppedURLs(urlsToProcess)
        }
        
        return true
    }
    
    private func processDroppedURLs(_ urls: [URL]) {
        var filesToCompress = [ImageFileEntry]()
        let fm = FileManager.default
        let supportedExts = ["JPG", "JPEG", "PNG", "HEIC", "TIFF"]
        
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles])
                    while let fileURL = enumerator?.nextObject() as? URL {
                        let ext = fileURL.pathExtension.uppercased()
                        if supportedExts.contains(ext) {
                            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                               let isSubDir = resourceValues.isDirectory, !isSubDir,
                               let sizeBytes = resourceValues.fileSize {
                                let entry = ImageFileEntry(name: fileURL.lastPathComponent, path: fileURL.path, originalSizeBytes: Int64(sizeBytes))
                                filesToCompress.append(entry)
                            }
                        }
                    }
                } else {
                    let ext = url.pathExtension.uppercased()
                    if supportedExts.contains(ext) {
                        if let attrs = try? fm.attributesOfItem(atPath: url.path),
                           let sizeBytes = attrs[.size] as? Int64 {
                            let entry = ImageFileEntry(name: url.lastPathComponent, path: url.path, originalSizeBytes: sizeBytes)
                            filesToCompress.append(entry)
                        }
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.foundImages.append(contentsOf: filesToCompress.sorted { $0.originalSizeBytes > $1.originalSizeBytes })
            self.startBatchCompression()
        }
    }
    
    // Batch compression
    private func startBatchCompression() {
        let pendingIndices = foundImages.indices.filter { foundImages[$0].status == "Pending" }
        guard !pendingIndices.isEmpty else { return }
        
        isCompressing = true
        compressionProgress = 0.0
        
        let targetImages = foundImages
        let quality = compressionQuality
        let maxDim = resizeDimension.maxPixelSize
        
        DispatchQueue.global(qos: .userInitiated).async {
            var savedSum: Int64 = self.totalBytesSaved
            
            for idx in pendingIndices {
                let entry = targetImages[idx]
                
                DispatchQueue.main.async {
                    self.foundImages[idx].status = "Compressing"
                    self.compressionStatus = "Optimizing \(entry.name) (\(idx+1)/\(targetImages.count))..."
                    self.compressionProgress = Double(idx) / Double(targetImages.count)
                }
                
                let result = compressImageInPlace(atPath: entry.path, quality: quality, maxDimension: maxDim)
                
                DispatchQueue.main.async {
                    switch result {
                    case .success(let saved):
                        if saved > 0 {
                            savedSum += saved
                            self.foundImages[idx].status = "Compressed"
                            self.foundImages[idx].compressedSizeBytes = entry.originalSizeBytes - saved
                            self.totalBytesSaved = savedSum
                            stateManager.incrementPhotosCompressedCount()
                        } else {
                            self.foundImages[idx].status = "Skipped" // already fully optimal
                        }
                    case .failure(let error):
                        print("Failed to compress \(entry.name): \(error.localizedDescription)")
                        self.foundImages[idx].status = "Failed"
                    }
                }
                
                // Throttle slightly to keep UI responsive
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            DispatchQueue.main.async {
                self.isCompressing = false
                self.compressionStatus = "Finished batch compression!"
                self.compressionProgress = 1.0
                stateManager.refreshDisks() // reload storage sizes
            }
        }
    }
    
    // Core Graphics Image Compression Engine
    private func compressImageInPlace(atPath path: String, quality: Double, maxDimension: CGFloat?) -> Result<Int64, Error> {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let originalSize = attrs[.size] as? Int64 else {
            return .failure(NSError(domain: "MediaCompressor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read file size"]))
        }
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .failure(NSError(domain: "MediaCompressor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image source"]))
        }
        
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32
        
        let options: [CFString: Any]
        if let maxDim = maxDimension {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDim,
                kCGImageSourceShouldCache: false
            ]
        } else {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false
            ]
        }
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .failure(NSError(domain: "MediaCompressor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create thumbnail"]))
        }
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return .failure(NSError(domain: "MediaCompressor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"]))
        }
        
        var destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        if let orient = orientation {
            destOptions[kCGImagePropertyOrientation] = orient
        }
        
        CGImageDestinationAddImage(destination, cgImage, destOptions as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            return .failure(NSError(domain: "MediaCompressor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"]))
        }
        
        guard let tempAttrs = try? fm.attributesOfItem(atPath: tempURL.path),
              let newSize = tempAttrs[.size] as? Int64 else {
            try? fm.removeItem(at: tempURL)
            return .failure(NSError(domain: "MediaCompressor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to read compressed file size"]))
        }
        
        if newSize >= originalSize {
            try? fm.removeItem(at: tempURL)
            return .success(0)
        }
        
        do {
            try fm.removeItem(at: url)
            try fm.moveItem(at: tempURL, to: url)
            return .success(originalSize - newSize)
        } catch {
            try? fm.removeItem(at: tempURL)
            return .failure(error)
        }
    }
}
