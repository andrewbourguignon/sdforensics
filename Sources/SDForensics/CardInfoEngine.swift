import Foundation
import ImageIO

// MARK: - Card Identity Model
public struct CardIdentity {
    public let cardType: String          // "SDXC Card (Class 10)"
    public let productName: String       // "PHMTG2c"
    public let manufacturerID: String    // "0x27"
    public let serialNumber: String      // "0x11186a6"
    public let manufacturingDate: String // "2025-05"
    public let specVersion: String       // "3.0"
    public let revision: String          // "5.0"
    public let capacity: String          // "252.48 GB"
    public let capacityBytes: UInt64
    public let smartStatus: String       // "Verified"
    public let partitionMap: String      // "MBR"
    public let filesystem: String        // "ExFAT"
    public let volumeName: String        // "Untitled"
    public let mountPoint: String        // "/Volumes/Untitled"
    public let freeSpace: String         // "20.54 GB"
    public let freeSpaceBytes: UInt64
    public let usedSpaceBytes: UInt64
    public let readerLinkSpeed: String   // "5.0 GT/s"
    public let readerLinkWidth: String   // "x1"
    public let bsdName: String           // "disk4"
    public let isRemovable: Bool
}

// MARK: - Storage Analysis Models
public struct RawImageEntry: Identifiable, Hashable {
    public let id = UUID()
    public let filename: String
    public let path: String
    public let sizeBytes: UInt64
    public var cameraModel: String
    public var shutterCount: Int? // nil if unsupported
    public let dateTaken: Date?
    
    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

public struct StorageAnalysis {
    public let totalFiles: Int
    public let totalSizeBytes: UInt64
    public let freeSpaceBytes: UInt64
    public let capacityBytes: UInt64
    public let fileTypeBreakdown: [FileTypeGroup]
    public let largestFiles: [FileEntry]
    public let cameraStructure: CameraStructure?
    public let clipEntries: [ClipEntry]
    public let recordingDates: [Date]
    public let rawImages: [RawImageEntry]
}

public struct FileTypeGroup: Identifiable {
    public let id = UUID()
    public let extension_: String
    public let count: Int
    public let totalSizeBytes: UInt64
    
    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
    }
}

public struct FileEntry: Identifiable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeBytes: UInt64
    public let modifiedDate: Date?
    
    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

public struct ClipEntry: Identifiable {
    public let id = UUID()
    public let filename: String
    public let path: String
    public let sizeBytes: UInt64
    public let duration: Double         // seconds
    public let resolution: String       // "3840×2160"
    public let codec: String            // "H.264"
    public let creationDate: Date?
    public let audioChannels: Int
    
    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
    
    public var durationFormatted: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

public enum CameraStructure: String {
    case sonyXAVC = "Sony XAVC-S (M4ROOT)"
    case canonEOS = "Canon EOS (DCIM)"
    case genericDCIM = "DCIM Standard"
    case unknown = "Unknown"
}

// MARK: - Speed Benchmark Models
public struct BenchmarkResult {
    public let sequentialReadMBps: Double
    public let sequentialWriteMBps: Double
    public let randomRead4KMBps: Double
    public let speedClass: String        // "UHS-I U3 / V30"
    public let grade: String             // "A", "B", "C"
    public let readSamples: [Double]     // MB/s over time for chart
    public let writeSamples: [Double]
}

// MARK: - Card Info Engine
public class CardInfoEngine {
    
    /// Queries system_profiler for hardware-level card identity data.
    public static func loadCardIdentity(bsdName: String) -> CardIdentity? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPCardReaderDataType", "-json"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[CardInfoEngine] Failed to run system_profiler: \(error)")
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let readers = json["SPCardReaderDataType"] as? [[String: Any]],
              let reader = readers.first else {
            print("[CardInfoEngine] Failed to parse system_profiler JSON")
            return nil
        }
        
        let linkSpeed = reader["spcardreader_link-speed"] as? String ?? "Unknown"
        let linkWidth = reader["spcardreader_link-width"] as? String ?? "Unknown"
        
        guard let items = reader["_items"] as? [[String: Any]] else { return nil }
        
        // Find the card matching our BSD name
        guard let card = items.first(where: { ($0["bsd_name"] as? String) == bsdName }) else {
            print("[CardInfoEngine] No card found matching BSD name: \(bsdName)")
            return nil
        }
        
        let cardType = card["_name"] as? String ?? "Unknown Card"
        let capacityBytes = card["size_in_bytes"] as? UInt64 ?? 0
        
        // Parse volume info
        var volumeName = "Unknown"
        var mountPoint = ""
        var filesystem = "Unknown"
        var freeSpace = "Unknown"
        var freeSpaceBytes: UInt64 = 0
        
        if let volumes = card["volumes"] as? [[String: Any]], let vol = volumes.first {
            volumeName = vol["_name"] as? String ?? "Unknown"
            mountPoint = vol["mount_point"] as? String ?? ""
            filesystem = vol["file_system"] as? String ?? "Unknown"
            freeSpace = vol["free_space"] as? String ?? "Unknown"
            freeSpaceBytes = vol["free_space_in_bytes"] as? UInt64 ?? 0
        }
        
        let partMap = card["partition_map_type"] as? String ?? "Unknown"
        let partMapDisplay: String
        if partMap.contains("master_boot_record") {
            partMapDisplay = "MBR"
        } else if partMap.contains("guid") {
            partMapDisplay = "GPT"
        } else {
            partMapDisplay = partMap
        }
        
        let usedBytes = capacityBytes > freeSpaceBytes ? capacityBytes - freeSpaceBytes : 0
        
        return CardIdentity(
            cardType: cardType,
            productName: card["spcardreader_card_productname"] as? String ?? "Unknown",
            manufacturerID: card["spcardreader_card_manufacturer-id"] as? String ?? "Unknown",
            serialNumber: card["spcardreader_card_serialnumber"] as? String ?? "Unknown",
            manufacturingDate: card["spcardreader_card_manufacturing_date"] as? String ?? "Unknown",
            specVersion: card["spcardreader_card_specversion"] as? String ?? "Unknown",
            revision: card["spcardreader_card_productrevision"] as? String ?? "Unknown",
            capacity: card["size"] as? String ?? "Unknown",
            capacityBytes: capacityBytes,
            smartStatus: card["smart_status"] as? String ?? "Unknown",
            partitionMap: partMapDisplay,
            filesystem: filesystem,
            volumeName: volumeName,
            mountPoint: mountPoint,
            freeSpace: freeSpace,
            freeSpaceBytes: freeSpaceBytes,
            usedSpaceBytes: usedBytes,
            readerLinkSpeed: linkSpeed,
            readerLinkWidth: linkWidth,
            bsdName: bsdName,
            isRemovable: (card["removable_media"] as? String) == "yes"
        )
    }
    
    /// Analyzes storage contents on a mounted volume.
    public static func analyzeStorage(mountPoint: String, capacityBytes: UInt64, freeSpaceBytes: UInt64) -> StorageAnalysis {
        // 1. Gather all files with sizes
        var allFiles = [FileEntry]()
        var typeMap = [String: (count: Int, size: UInt64)]()
        
        let findTask = Process()
        findTask.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        findTask.arguments = [mountPoint, "-type", "f", "-not", "-path", "*/.*"]
        let findPipe = Pipe()
        findTask.standardOutput = findPipe
        findTask.standardError = Pipe()
        
        do {
            try findTask.run()
            findTask.waitUntilExit()
        } catch {
            print("[CardInfoEngine] find failed: \(error)")
        }
        
        let findData = findPipe.fileHandleForReading.readDataToEndOfFile()
        let filePaths = String(data: findData, encoding: .utf8)?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
        
        let fm = FileManager.default
        for path in filePaths {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let ext = url.pathExtension.uppercased()
            
            var sizeBytes: UInt64 = 0
            var modDate: Date? = nil
            if let attrs = try? fm.attributesOfItem(atPath: path) {
                sizeBytes = attrs[.size] as? UInt64 ?? 0
                modDate = attrs[.modificationDate] as? Date
            }
            
            allFiles.append(FileEntry(name: name, path: path, sizeBytes: sizeBytes, modifiedDate: modDate))
            
            let key = ext.isEmpty ? "NO EXT" : ext
            let current = typeMap[key] ?? (count: 0, size: 0)
            typeMap[key] = (count: current.count + 1, size: current.size + sizeBytes)
        }
        
        // Build file type groups sorted by size
        let fileTypeBreakdown = typeMap.map { key, val in
            FileTypeGroup(extension_: key, count: val.count, totalSizeBytes: val.size)
        }.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
        
        // Top 10 largest files
        let largestFiles = allFiles.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(10).map { $0 }
        
        // Detect camera structure
        let cameraStructure = detectCameraStructure(mountPoint: mountPoint)
        
        // Gather clip metadata for video files
        let videoFiles = allFiles.filter { entry in
            let ext = URL(fileURLWithPath: entry.path).pathExtension.uppercased()
            return ["MP4", "MOV", "MXF", "AVI", "MTS"].contains(ext)
        }.sorted { ($0.name) < ($1.name) }
        
        var clipEntries = [ClipEntry]()
        for file in videoFiles {
            let clip = loadClipMetadata(filePath: file.path, sizeBytes: file.sizeBytes)
            clipEntries.append(clip)
        }
        
        // Gather RAW images
        let rawFiles = allFiles.filter { entry in
            let ext = URL(fileURLWithPath: entry.path).pathExtension.uppercased()
            return ["ARW", "NEF", "CR2", "CR3", "RAF", "DNG"].contains(ext)
        }.sorted { ($0.name) < ($1.name) }
        
        var rawImages = [RawImageEntry]()
        for file in rawFiles {
            let entry = loadRawImageMetadata(filePath: file.path, sizeBytes: file.sizeBytes)
            rawImages.append(entry)
        }
        
        // Extract unique recording dates
        let recordingDates = clipEntries.compactMap { $0.creationDate }.sorted()
        
        let totalSize = allFiles.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        
        return StorageAnalysis(
            totalFiles: allFiles.count,
            totalSizeBytes: totalSize,
            freeSpaceBytes: freeSpaceBytes,
            capacityBytes: capacityBytes,
            fileTypeBreakdown: fileTypeBreakdown,
            largestFiles: Array(largestFiles),
            cameraStructure: cameraStructure,
            clipEntries: clipEntries,
            recordingDates: recordingDates,
            rawImages: rawImages
        )
    }
    
    /// Detects camera directory structure type.
    private static func detectCameraStructure(mountPoint: String) -> CameraStructure? {
        let fm = FileManager.default
        if fm.fileExists(atPath: "\(mountPoint)/PRIVATE/M4ROOT") {
            return .sonyXAVC
        } else if fm.fileExists(atPath: "\(mountPoint)/DCIM") {
            // Check for Canon EOS markers
            let dcimContents = (try? fm.contentsOfDirectory(atPath: "\(mountPoint)/DCIM")) ?? []
            let hasCanon = dcimContents.contains { $0.hasPrefix("100CANON") || $0.hasPrefix("100EOS") }
            return hasCanon ? .canonEOS : .genericDCIM
        }
        return nil
    }
    
    /// Extracts video clip metadata using mdls.
    private static func loadClipMetadata(filePath: String, sizeBytes: UInt64) -> ClipEntry {
        let filename = URL(fileURLWithPath: filePath).lastPathComponent
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        task.arguments = [
            "-name", "kMDItemDurationSeconds",
            "-name", "kMDItemPixelWidth",
            "-name", "kMDItemPixelHeight",
            "-name", "kMDItemCodecs",
            "-name", "kMDItemContentCreationDate",
            "-name", "kMDItemAudioChannelCount",
            filePath
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ClipEntry(filename: filename, path: filePath, sizeBytes: sizeBytes,
                           duration: 0, resolution: "Unknown", codec: "Unknown",
                           creationDate: nil, audioChannels: 0)
        }
        
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        var duration: Double = 0
        var width = 0
        var height = 0
        var codec = "Unknown"
        var creationDate: Date? = nil
        var audioChannels = 0
        
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            
            if val == "(null)" { continue }
            
            switch key {
            case "kMDItemDurationSeconds":
                duration = Double(val) ?? 0
            case "kMDItemPixelWidth":
                width = Int(val) ?? 0
            case "kMDItemPixelHeight":
                height = Int(val) ?? 0
            case "kMDItemAudioChannelCount":
                audioChannels = Int(val) ?? 0
            case "kMDItemCodecs":
                // Parse array format: (\n    "H.264",\n    "Linear PCM"\n)
                let codecs = val.replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                codec = codecs.first ?? "Unknown"
            case "kMDItemContentCreationDate":
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                creationDate = df.date(from: val)
            default:
                break
            }
        }
        
        let resolution = width > 0 && height > 0 ? "\(width)×\(height)" : "Unknown"
        
        return ClipEntry(
            filename: filename, path: filePath, sizeBytes: sizeBytes,
            duration: duration, resolution: resolution, codec: codec,
            creationDate: creationDate, audioChannels: audioChannels
        )
    }
    
    /// Runs sequential read benchmark on a mounted volume.
    public static func runBenchmark(mountPoint: String) -> BenchmarkResult {
        var readSamples = [Double]()
        var writeSamples = [Double]()
        
        // Sequential Read: use dd to read from a large file on the card
        let fm = FileManager.default
        let testFiles = (try? fm.contentsOfDirectory(atPath: mountPoint))?.compactMap { name -> String? in
            let path = "\(mountPoint)/\(name)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue { return nil }
            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = attrs?[.size] as? UInt64 ?? 0
            return size > 10_000_000 ? path : nil // Files > 10MB
        } ?? []
        
        // Find a large file for read test (prefer video clips)
        let allFiles = findLargeFiles(mountPoint: mountPoint)
        let readTestFile = allFiles.first ?? testFiles.first
        
        var seqReadMBps: Double = 0
        if let testFile = readTestFile {
            // Read 64MB chunks, measure throughput
            let chunkSize = 64 * 1024 * 1024 // 64MB
            let fd = open(testFile, O_RDONLY)
            if fd != -1 {
                // Set F_NOCACHE for accurate measurement
                fcntl(fd, F_NOCACHE, 1)
                
                var totalBytesRead: UInt64 = 0
                let maxBytes: UInt64 = 256 * 1024 * 1024 // Read up to 256MB
                var buffer = [UInt8](repeating: 0, count: chunkSize)
                
                let startTime = DispatchTime.now()
                while totalBytesRead < maxBytes {
                    let bytesRead = read(fd, &buffer, chunkSize)
                    if bytesRead <= 0 { break }
                    totalBytesRead += UInt64(bytesRead)
                    
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                    if elapsed > 0 {
                        readSamples.append(Double(totalBytesRead) / elapsed / 1_000_000)
                    }
                }
                let totalTime = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                if totalTime > 0 {
                    seqReadMBps = Double(totalBytesRead) / totalTime / 1_000_000
                }
                close(fd)
            }
        }
        
        // Sequential Write: write a temp file
        var seqWriteMBps: Double = 0
        let tempPath = "\(mountPoint)/.sdforensics_benchmark_tmp"
        let writeChunkSize = 16 * 1024 * 1024 // 16MB
        let writeTotal: UInt64 = 128 * 1024 * 1024 // Write 128MB
        let writeBuffer = [UInt8](repeating: 0xAA, count: writeChunkSize)
        
        let wfd = open(tempPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if wfd != -1 {
            fcntl(wfd, F_NOCACHE, 1)
            
            var totalWritten: UInt64 = 0
            let wStart = DispatchTime.now()
            while totalWritten < writeTotal {
                let written = write(wfd, writeBuffer, writeChunkSize)
                if written <= 0 { break }
                totalWritten += UInt64(written)
                
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - wStart.uptimeNanoseconds) / 1_000_000_000
                if elapsed > 0 {
                    writeSamples.append(Double(totalWritten) / elapsed / 1_000_000)
                }
            }
            // Force sync to flush to media
            fsync(wfd)
            let wTime = Double(DispatchTime.now().uptimeNanoseconds - wStart.uptimeNanoseconds) / 1_000_000_000
            if wTime > 0 {
                seqWriteMBps = Double(totalWritten) / wTime / 1_000_000
            }
            close(wfd)
            try? fm.removeItem(atPath: tempPath)
        }
        
        // Random Read 4K: read random 4K blocks from the test file
        var random4KMBps: Double = 0
        if let testFile = readTestFile {
            let rfd = open(testFile, O_RDONLY)
            if rfd != -1 {
                fcntl(rfd, F_NOCACHE, 1)
                let fileSize = lseek(rfd, 0, SEEK_END)
                if fileSize > 4096 {
                    var rBuffer = [UInt8](repeating: 0, count: 4096)
                    let iterations = 1000
                    let rStart = DispatchTime.now()
                    var totalRead: UInt64 = 0
                    for _ in 0..<iterations {
                        let randomOffset = off_t(arc4random_uniform(UInt32(fileSize / 4096))) * 4096
                        lseek(rfd, randomOffset, SEEK_SET)
                        let r = read(rfd, &rBuffer, 4096)
                        if r > 0 { totalRead += UInt64(r) }
                    }
                    let rTime = Double(DispatchTime.now().uptimeNanoseconds - rStart.uptimeNanoseconds) / 1_000_000_000
                    if rTime > 0 {
                        random4KMBps = Double(totalRead) / rTime / 1_000_000
                    }
                }
                close(rfd)
            }
        }
        
        // Determine speed class
        let speedClass = classifySpeed(readMBps: seqReadMBps, writeMBps: seqWriteMBps)
        let grade = gradeSpeed(readMBps: seqReadMBps, writeMBps: seqWriteMBps)
        
        return BenchmarkResult(
            sequentialReadMBps: seqReadMBps,
            sequentialWriteMBps: seqWriteMBps,
            randomRead4KMBps: random4KMBps,
            speedClass: speedClass,
            grade: grade,
            readSamples: readSamples,
            writeSamples: writeSamples
        )
    }
    
    private static func findLargeFiles(mountPoint: String) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        task.arguments = [mountPoint, "-type", "f", "-size", "+50M", "-not", "-path", "*/.*"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
    }
    
    private static func classifySpeed(readMBps: Double, writeMBps: Double) -> String {
        if writeMBps >= 90 { return "V90 / UHS-III" }
        if writeMBps >= 60 { return "V60 / UHS-II" }
        if writeMBps >= 30 { return "V30 / UHS-I U3" }
        if writeMBps >= 10 { return "U1 / Class 10" }
        if writeMBps >= 6 { return "Class 6" }
        if writeMBps >= 4 { return "Class 4" }
        return "Class 2 or below"
    }
    
    private static func gradeSpeed(readMBps: Double, writeMBps: Double) -> String {
        let score = (readMBps + writeMBps) / 2
        if score >= 80 { return "A+" }
        if score >= 60 { return "A" }
        if score >= 40 { return "B" }
        if score >= 20 { return "C" }
        if score >= 10 { return "D" }
        return "F"
    }
    
    /// Ejects a disk safely.
    public static func ejectDisk(diskIdentifier: String) -> Result<String, Error> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["eject", diskIdentifier]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if task.terminationStatus == 0 {
                return .success(output.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                return .failure(DeviceError.unmountFailed(output))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - RAW Shutter Count Checker Implementation
    
    public static func loadRawImageMetadata(filePath: String, sizeBytes: UInt64) -> RawImageEntry {
        let filename = URL(fileURLWithPath: filePath).lastPathComponent
        let url = URL(fileURLWithPath: filePath)
        
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return RawImageEntry(filename: filename, path: filePath, sizeBytes: sizeBytes, cameraModel: "Unknown", shutterCount: nil, dateTaken: nil)
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return RawImageEntry(filename: filename, path: filePath, sizeBytes: sizeBytes, cameraModel: "Unknown", shutterCount: nil, dateTaken: nil)
        }
        
        var cameraModel = "Unknown"
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = tiffDict[kCGImagePropertyTIFFMake] as? String ?? ""
            let model = tiffDict[kCGImagePropertyTIFFModel] as? String ?? ""
            cameraModel = make.isEmpty ? model : "\(make) \(model)"
        }
        
        var dateTaken: Date? = nil
        if let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal] as? String {
                let df = DateFormatter()
                df.dateFormat = "yyyy:MM:dd HH:mm:ss"
                dateTaken = df.date(from: dateString)
            }
        }
        
        var shutterCount: Int? = nil
        let cameraModelLower = cameraModel.lowercased()
        
        if cameraModelLower.contains("nikon") {
            if let nikonDict = properties[kCGImagePropertyMakerNikonDictionary] as? [AnyHashable: Any] {
                if let count = nikonDict[167] as? Int {
                    shutterCount = count
                } else if let count = nikonDict["167"] as? Int {
                    shutterCount = count
                } else if let count = nikonDict["ImageNumber"] as? Int {
                    shutterCount = count
                } else if let count = nikonDict[167] as? String, let countInt = Int(count) {
                    shutterCount = countInt
                } else if let count = nikonDict["167"] as? String, let countInt = Int(count) {
                    shutterCount = countInt
                } else if let count = nikonDict["ImageNumber"] as? String, let countInt = Int(count) {
                    shutterCount = countInt
                }
            }
        } else if cameraModelLower.contains("sony") {
            if let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let makerNoteData = exifDict[kCGImagePropertyExifMakerNote] as? Data {
                shutterCount = parseSonyShutterCount(fromMakerNote: makerNoteData, cameraModel: cameraModel)
            }
        } else if cameraModelLower.contains("fuji") {
            if let fujiDict = properties[kCGImagePropertyMakerFujiDictionary] as? [AnyHashable: Any] {
                if let count = fujiDict["ImageCount"] as? Int {
                    shutterCount = count
                } else if let count = fujiDict[1430] as? Int {
                    shutterCount = count
                } else if let count = fujiDict["1430"] as? Int {
                    shutterCount = count
                } else if let count = fujiDict[1430] as? String, let countInt = Int(count) {
                    shutterCount = countInt
                } else if let count = fujiDict["1430"] as? String, let countInt = Int(count) {
                    shutterCount = countInt
                }
            }
        }
        
        return RawImageEntry(filename: filename, path: filePath, sizeBytes: sizeBytes, cameraModel: cameraModel, shutterCount: shutterCount, dateTaken: dateTaken)
    }
    
    private static func parseSonyShutterCount(fromMakerNote data: Data, cameraModel: String) -> Int? {
        guard data.count > 20 else { return nil }
        
        var startOffset = 0
        if data.count >= 4, data.subdata(in: 0..<4) == Data([0x53, 0x4f, 0x4e, 0x59]) { // "SONY"
            startOffset = 12
        }
        
        guard data.count >= startOffset + 2 else { return nil }
        let entryCount = Int(data.readUInt16(at: startOffset))
        
        var offset = startOffset + 2
        for _ in 0..<entryCount {
            guard data.count >= offset + 12 else { break }
            let tag = data.readUInt16(at: offset)
            if tag == 0x9050 {
                let type = data.readUInt16(at: offset + 2)
                let count = Int(data.readUInt32(at: offset + 4))
                let valOffset = Int(data.readUInt32(at: offset + 8))
                
                let size = count * getTypeSize(type)
                var tagData: Data
                if size <= 4 {
                    tagData = data.subdata(in: (offset + 8)..<(offset + 8 + size))
                } else {
                    guard data.count >= valOffset + size else { break }
                    tagData = data.subdata(in: valOffset..<(valOffset + size))
                }
                
                return decryptSonyShutterCount(fromBlock: tagData, cameraModel: cameraModel)
            }
            offset += 12
        }
        return nil
    }
    
    private static func getTypeSize(_ type: UInt16) -> Int {
        switch type {
        case 1: return 1 // BYTE
        case 2: return 1 // ASCII
        case 3: return 2 // SHORT
        case 4: return 4 // LONG
        case 5: return 8 // RATIONAL
        case 7: return 1 // UNDEFINED
        case 9: return 4 // SLONG
        case 10: return 8 // SRATIONAL
        default: return 1
        }
    }
    
    private static func decryptSonyShutterCount(fromBlock block: Data, cameraModel: String) -> Int? {
        guard block.count >= 60 else { return nil }
        
        var decryptionTable = [UInt8](repeating: 0, count: 256)
        for b in 0..<249 {
            let c = (b * b * b) % 249
            decryptionTable[c] = UInt8(b)
        }
        for b in 249...255 {
            decryptionTable[b] = UInt8(b)
        }
        
        var decryptedBytes = [UInt8](repeating: 0, count: block.count)
        for i in 0..<block.count {
            decryptedBytes[i] = decryptionTable[Int(block[i])]
        }
        
        let modelLower = cameraModel.lowercased()
        var offset = 0x3a
        
        if modelLower.contains("ilce-7rm5") || modelLower.contains("ilce-6700") || modelLower.contains("ilce-7cr") || modelLower.contains("ilce-7cm2") {
            offset = 0x0a
        } else if modelLower.contains("ilce-7m2") || modelLower.contains("ilce-7r2") || modelLower.contains("ilce-7s2") || modelLower.contains("ilce-6000") || modelLower.contains("ilce-6300") || modelLower.contains("ilce-6500") || modelLower.contains("ilce-7r") || modelLower.contains("ilce-7s") || modelLower.contains("ilce-7") {
            offset = 0x32
        }
        
        guard decryptedBytes.count >= offset + 4 else { return nil }
        
        let b0 = Int(decryptedBytes[offset])
        let b1 = Int(decryptedBytes[offset + 1])
        let b2 = Int(decryptedBytes[offset + 2])
        let b3 = Int(decryptedBytes[offset + 3])
        let count = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        
        if count > 0 && count < 2_000_000 {
            return count
        }
        
        let alternatives = [0x3a, 0x32, 0x0a].filter { $0 != offset }
        for altOffset in alternatives {
            if decryptedBytes.count >= altOffset + 4 {
                let ab0 = Int(decryptedBytes[altOffset])
                let ab1 = Int(decryptedBytes[altOffset + 1])
                let ab2 = Int(decryptedBytes[altOffset + 2])
                let ab3 = Int(decryptedBytes[altOffset + 3])
                let altCount = ab0 | (ab1 << 8) | (ab2 << 16) | (ab3 << 24)
                if altCount > 0 && altCount < 2_000_000 {
                    return altCount
                }
            }
        }
        
        return nil
    }
}

// MARK: - Binary Data Reading Extensions
extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}
