import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

public class AppStateManager: ObservableObject {
    @Published var connectedDisks: [DiskInfo] = []
    @Published var selectedDisk: DiskInfo? = nil {
        didSet {
            self.statusMessage = ""
            self.isSuccess = false
            self.lastAuditResult = nil
            self.cardIdentity = nil
            self.storageAnalysis = nil
            self.benchmarkResult = nil
            // Auto-load card identity when a disk is selected
            if let disk = selectedDisk, !disk.isMock {
                loadCardIdentity(for: disk)
            }
        }
    }
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var lastAuditResult: ForensicAuditResult? = nil
    
    // Formatting Fields
    @Published var customName = "CAM_A_CARD_01"
    @Published var ownerID = "STUDIO_PROD"
    @Published var preloadedCycles = "0"
    @Published var isFormatting = false
    @Published var statusMessage = ""
    @Published var isSuccess = false
    @Published var wipeLevel: WipeLevel = .quick
    @Published var selectedPreset: CameraPreset = .none
    @Published var cameraPresets: [CameraPreset] = []
    @Published var formatSteps: [FormatStep] = []
    @Published var customPresetImagePath: String? = nil
    
    // Simulation
    @Published var isMockMode = false
    @Published var mockFilePath = ""
    
    // Card Identity & Analysis (v2)
    @Published var cardIdentity: CardIdentity? = nil
    @Published var storageAnalysis: StorageAnalysis? = nil
    @Published var isAnalyzingStorage = false
    @Published var benchmarkResult: BenchmarkResult? = nil
    @Published var isBenchmarking = false
    @Published var benchmarkProgress: Double = 0.0
    @Published var ejectMessage = ""
    
    @Published var testSizeMB: Int = 100
    @Published var benchmarkHistory: [BenchmarkRecord] = []
    @Published var totalPhotosCompressed: Int = 0
    
    // Carver States
    @Published var isCarving = false
    @Published var carvingProgress: Double = 0.0
    @Published var carvedFiles: [CarvedFileRecord] = []
    @Published var carvingStatusMessage = ""
    
    public init() {
        self.loadPresets()
        self.loadBenchmarkHistory()
        self.loadPhotosCompressedCount()
        
        // Run initial disk refresh asynchronously on a background queue
        // to prevent AttributeGraph nested runloop crash during layout setup.
        DispatchQueue.global(qos: .userInitiated).async {
            self.refreshDisks()
        }
    }
    
    /// Queries connected external block devices via diskutil and maps local mock files.
    public func refreshDisks() {
        var disks = [DiskInfo]()
        
        // Add active mock file if configured
        if !mockFilePath.isEmpty {
            let mockURL = URL(fileURLWithPath: mockFilePath)
            let name = mockURL.lastPathComponent
            disks.append(DiskInfo(name: name, path: mockFilePath, sizeString: "10 MB", filesystem: "Virtual Raw Mock File", isMock: true))
        }
        
        // Command execution to fetch all physical disks
        let listTask = Process()
        listTask.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        listTask.arguments = ["list", "physical"]
        
        let listPipe = Pipe()
        listTask.standardOutput = listPipe
        
        do {
            try listTask.run()
            listTask.waitUntilExit()
            
            let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
            if let listOutput = String(data: listData, encoding: .utf8) {
                // Find all /dev/diskX lines representing whole physical disks
                let lines = listOutput.components(separatedBy: .newlines)
                for line in lines {
                    if line.hasPrefix("/dev/disk") && line.contains("physical") {
                        // Extract target name (e.g. /dev/disk4)
                        let parts = line.split(separator: " ")
                        guard let bsdPath = parts.first else { continue }
                        let path = String(bsdPath)
                        let diskID = path.replacingOccurrences(of: "/dev/", with: "")
                        
                        // Exclude disk0 (the primary built-in Mac SSD) to ensure absolute safety
                        if diskID == "disk0" { continue }
                        
                        // Run diskutil info <diskID> to check for Removable status
                        let infoTask = Process()
                        infoTask.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                        infoTask.arguments = ["info", diskID]
                        let infoPipe = Pipe()
                        infoTask.standardOutput = infoPipe
                        
                        try infoTask.run()
                        infoTask.waitUntilExit()
                        
                        let infoData = infoPipe.fileHandleForReading.readDataToEndOfFile()
                        if let infoOutput = String(data: infoData, encoding: .utf8) {
                            let infoLines = infoOutput.components(separatedBy: .newlines)
                            var isRemovable = false
                            var mediaName = "Physical Disk \(diskID)"
                            var sizeString = "Unknown Size"
                            
                            for infoLine in infoLines {
                                if infoLine.contains("Removable Media:") && infoLine.contains("Removable") {
                                    isRemovable = true
                                }
                                if infoLine.contains("Protocol:") && (infoLine.contains("Secure Digital") || infoLine.contains("USB")) {
                                    isRemovable = true
                                }
                                if infoLine.contains("Device / Media Name:") {
                                    mediaName = infoLine.replacingOccurrences(of: "Device / Media Name:", with: "")
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                if infoLine.contains("Disk Size:") {
                                    // Parse disk size e.g. "Disk Size:                 252.5 GB (252480323584 Bytes)"
                                    if let sizePart = infoLine.split(separator: ":").last {
                                        sizeString = sizePart.components(separatedBy: "(").first?
                                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Size"
                                    }
                                }
                            }
                            
                            // Include in list if it's removable or Secure Digital/USB
                            if isRemovable {
                                disks.append(DiskInfo(
                                    name: mediaName,
                                    path: path,
                                    sizeString: sizeString,
                                    filesystem: "Removable SD/USB Media",
                                    isMock: false
                                ))
                            }
                        }
                    }
                }
            }
        } catch {
            print("Failed to query disks: \(error.localizedDescription)")
        }
        
        DispatchQueue.main.async {
            self.connectedDisks = disks
            if disks.count > 0 && self.selectedDisk == nil {
                self.selectedDisk = disks.first
            }
        }
    }
    
    /// Executes Forensic scanning sequence on a background queue.
    public func startAudit(forcePhysical: Bool) {
        guard let disk = selectedDisk else {
            self.statusMessage = "Error: No target disk selected."
            self.isSuccess = false
            return
        }
        
        self.isScanning = true
        self.scanProgress = 0.0
        self.isSuccess = false
        self.statusMessage = "Opening block device descriptor..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = RawDeviceManager()
            let openResult = manager.openDevice(path: disk.path, writeAccess: false, forcePhysical: forcePhysical)
            
            switch openResult {
            case .success:
                DispatchQueue.main.async {
                    self.statusMessage = "Analyzing allocation tables and sector wear structures..."
                    self.scanProgress = 0.5
                }
                
                let engine = ForensicEngine(deviceManager: manager)
                let auditResult = engine.executeAudit()
                
                manager.closeDevice()
                
                DispatchQueue.main.async {
                    self.lastAuditResult = auditResult
                    self.isSuccess = true
                    self.isScanning = false
                    self.scanProgress = 1.0
                    self.statusMessage = "Audit completed successfully."
                }
                
            case .failure(let error):
                manager.closeDevice()
                DispatchQueue.main.async {
                    self.isSuccess = false
                    self.isScanning = false
                    self.scanProgress = 0.0
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Runs formatting and metadata embedding sequences.
    public func startFormatting(forcePhysical: Bool) {
        guard let disk = selectedDisk else {
            self.statusMessage = "Error: No target disk selected."
            return
        }
        
        self.isFormatting = true
        self.isSuccess = false
        self.statusMessage = "Initializing device unmount request..."
        
        self.formatSteps = [
            FormatStep(index: 0, name: "Unmount disk partition tables", status: .pending),
            FormatStep(index: 1, name: "Backup existing partition headers", status: .pending),
            FormatStep(index: 2, name: "Wipe primary allocation sectors", status: .pending),
            FormatStep(index: 3, name: "Inject forensics wear metadata stamp", status: .pending),
            FormatStep(index: 4, name: "Reconstruct Protective MBR/GPT layouts", status: .pending),
            FormatStep(index: 5, name: "Provision camera system directory templates", status: .pending)
        ]
        
        let targetCycles = UInt64(preloadedCycles) ?? 0
        let targetWipeLevel = self.wipeLevel
        let targetDirectories = self.selectedPreset.directories
        let targetIconPath = self.customPresetImagePath ?? self.selectedPreset.iconPath
        
        var mountPoint = ""
        if disk.isMock {
            mountPoint = disk.path.replacingOccurrences(of: ".img", with: "_mounted")
        } else if let identity = self.cardIdentity, identity.bsdName == disk.path.replacingOccurrences(of: "/dev/", with: "") {
            mountPoint = identity.mountPoint
        }
        
        let targetMountPoint = mountPoint
        
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = RawDeviceManager()
            let openResult = manager.openDevice(path: disk.path, writeAccess: true, forcePhysical: forcePhysical)
            
            switch openResult {
            case .success:
                let tool = InitializationTool(deviceManager: manager)
                let formatResult = tool.initializeCard(
                    deviceName: self.customName,
                    ownerID: self.ownerID,
                    previousCycles: targetCycles,
                    wipeLevel: targetWipeLevel,
                    directories: targetDirectories,
                    mountPoint: targetMountPoint,
                    customImagePath: targetIconPath,
                    onStepProgress: { stepIdx, message in
                        DispatchQueue.main.async {
                            self.statusMessage = message
                            for i in 0..<stepIdx {
                                if self.formatSteps[i].status == .pending || self.formatSteps[i].status == .active {
                                    self.formatSteps[i].status = .completed
                                }
                            }
                            if stepIdx < self.formatSteps.count {
                                self.formatSteps[stepIdx].status = .active
                            }
                        }
                    }
                )
                
                manager.closeDevice()
                
                DispatchQueue.main.async {
                    self.isFormatting = false
                    switch formatResult {
                    case .success:
                        for i in 0..<self.formatSteps.count {
                            self.formatSteps[i].status = .completed
                        }
                        self.isSuccess = true
                        self.statusMessage = "Formatting completed. Card '\(self.customName)' has been marked."
                        self.refreshDisks()
                    case .failure(let error):
                        if let activeIndex = self.formatSteps.firstIndex(where: { $0.status == .active }) {
                            self.formatSteps[activeIndex].status = .failed(error.localizedDescription)
                        }
                        self.isSuccess = false
                        self.statusMessage = "Formatting error: \(error.localizedDescription)"
                    }
                }
                
            case .failure(let error):
                manager.closeDevice()
                DispatchQueue.main.async {
                    self.formatSteps[0].status = .failed(error.localizedDescription)
                    self.isFormatting = false
                    self.isSuccess = false
                    self.statusMessage = "Open failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    public func loadCardIdentity(for disk: DiskInfo) {
        guard !disk.isMock else { return }
        let bsdName = disk.path.replacingOccurrences(of: "/dev/", with: "")
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let identity = CardInfoEngine.loadCardIdentity(bsdName: bsdName) {
                DispatchQueue.main.async {
                    self.cardIdentity = identity
                    self.analyzeStorage()
                }
            }
        }
    }
    
    public func analyzeStorage() {
        guard let identity = self.cardIdentity, !identity.mountPoint.isEmpty else { return }
        
        self.isAnalyzingStorage = true
        let mountPoint = identity.mountPoint
        let capacity = identity.capacityBytes
        let freeSpace = identity.freeSpaceBytes
        
        DispatchQueue.global(qos: .userInitiated).async {
            let analysis = CardInfoEngine.analyzeStorage(mountPoint: mountPoint, capacityBytes: capacity, freeSpaceBytes: freeSpace)
            DispatchQueue.main.async {
                self.storageAnalysis = analysis
                self.isAnalyzingStorage = false
            }
        }
    }
    
    public func runBenchmark() {
        guard let identity = self.cardIdentity, !identity.mountPoint.isEmpty else { return }
        guard let disk = selectedDisk else { return }
        
        self.isBenchmarking = true
        self.benchmarkProgress = 0.0
        self.benchmarkResult = nil
        let mountPoint = identity.mountPoint
        let size = self.testSizeMB
        
        // Progress updater
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.benchmarkProgress < 0.9 {
                self.benchmarkProgress += 0.02
            } else {
                timer.invalidate()
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardInfoEngine.runBenchmark(mountPoint: mountPoint, testSizeMB: size)
            
            let record = BenchmarkRecord(
                id: UUID(),
                date: Date(),
                deviceName: disk.name,
                testSizeMB: size,
                sequentialReadMBps: result.sequentialReadMBps,
                sequentialWriteMBps: result.sequentialWriteMBps,
                randomRead4KMBps: result.randomRead4KMBps,
                speedClass: result.speedClass,
                grade: result.grade,
                readSamples: result.readSamples,
                writeSamples: result.writeSamples
            )
            
            DispatchQueue.main.async {
                progressTimer.invalidate()
                self.benchmarkProgress = 1.0
                self.benchmarkResult = result
                self.benchmarkHistory.insert(record, at: 0) // Prepend newest
                self.saveBenchmarkHistory()
                self.isBenchmarking = false
            }
        }
    }
    
    public func ejectDisk() {
        guard let disk = selectedDisk else { return }
        self.ejectMessage = "Ejecting..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardInfoEngine.ejectDisk(diskIdentifier: disk.path)
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    self.ejectMessage = "Successfully ejected: \(output)"
                    self.selectedDisk = nil
                    self.refreshDisks()
                case .failure(let error):
                    self.ejectMessage = "Eject failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Presets CRUD Management
    public func loadPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "SDForensicsCustomPresets"),
           let decoded = try? JSONDecoder().decode([CameraPreset].self, from: data) {
            self.cameraPresets = [CameraPreset.none] + CameraPreset.builtIns + decoded
        } else {
            self.cameraPresets = [CameraPreset.none] + CameraPreset.builtIns
        }
        self.selectedPreset = self.cameraPresets.first ?? .none
    }
    
    public func saveCustomPresets() {
        let customOnly = self.cameraPresets.filter { preset in
            !CameraPreset.builtIns.contains(where: { $0.id == preset.id }) && preset.id != CameraPreset.none.id
        }
        if let encoded = try? JSONEncoder().encode(customOnly) {
            UserDefaults.standard.set(encoded, forKey: "SDForensicsCustomPresets")
        }
    }
    
    public func addCustomPreset(name: String, directories: [String], iconPath: String?) {
        let newPreset = CameraPreset(name: name, directories: directories, iconPath: iconPath)
        self.cameraPresets.append(newPreset)
        self.saveCustomPresets()
        self.selectedPreset = newPreset
    }
    
    public func deleteCustomPreset(id: UUID) {
        self.cameraPresets.removeAll { $0.id == id }
        self.saveCustomPresets()
        if self.selectedPreset.id == id {
            self.selectedPreset = self.cameraPresets.first ?? .none
        }
    }
    
    public func renamePreset(id: UUID, newName: String) {
        if let idx = self.cameraPresets.firstIndex(where: { $0.id == id }) {
            var updated = self.cameraPresets[idx]
            updated.name = newName
            self.cameraPresets[idx] = updated
            self.saveCustomPresets()
            if self.selectedPreset.id == id {
                self.selectedPreset = updated
            }
        }
    }
    
    // MARK: - Benchmark History CRUD
    public func loadBenchmarkHistory() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "SDForensicsBenchmarkHistory"),
           let decoded = try? JSONDecoder().decode([BenchmarkRecord].self, from: data) {
            self.benchmarkHistory = decoded
        } else {
            self.benchmarkHistory = []
        }
    }
    
    public func saveBenchmarkHistory() {
        if let encoded = try? JSONEncoder().encode(self.benchmarkHistory) {
            UserDefaults.standard.set(encoded, forKey: "SDForensicsBenchmarkHistory")
        }
    }
    
    public func clearBenchmarkHistory() {
        self.benchmarkHistory = []
        self.saveBenchmarkHistory()
    }
    
    // MARK: - Deleted File Carver Methods
    public func startFileCarving(forcePhysical: Bool) {
        guard let disk = selectedDisk else {
            self.carvingStatusMessage = "Error: No target disk selected."
            return
        }
        
        self.isCarving = true
        self.carvingProgress = 0.0
        self.carvingStatusMessage = "Opening block device descriptor..."
        self.carvedFiles = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = RawDeviceManager()
            let openResult = manager.openDevice(path: disk.path, writeAccess: false, forcePhysical: forcePhysical)
            
            switch openResult {
            case .success:
                let totalSectors = min(manager.totalSectors, 40000) // Scan first 40k sectors (approx 20MB)
                var currentSector: UInt64 = 0
                var filesFound = [CarvedFileRecord]()
                
                while currentSector < totalSectors && self.isCarving {
                    let progress = Double(currentSector) / Double(totalSectors)
                    DispatchQueue.main.async {
                        self.carvingProgress = progress
                        self.carvingStatusMessage = "Scanning sector \(currentSector)/\(totalSectors)... Recovered \(filesFound.count) files."
                    }
                    
                    if case .success(let data) = manager.readSectors(startSector: currentSector, sectorCount: 1) {
                        var foundType: String? = nil
                        var ext = ""
                        
                        // Check header signatures
                        if data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
                            foundType = "JPEG Image"
                            ext = "jpg"
                        } else if data.count >= 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
                            foundType = "PNG Image"
                            ext = "png"
                        } else if data.count >= 8 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
                            foundType = "MP4 Video"
                            ext = "mp4"
                        }
                        
                        if let type = foundType {
                            let start = currentSector
                            var fileData = Data(data)
                            let maxCarveSectors: UInt64 = 10000 // Limit to ~5MB
                            
                            var carveOffset: UInt64 = 1
                            while carveOffset < maxCarveSectors && (currentSector + carveOffset) < totalSectors {
                                if case .success(let nextData) = manager.readSectors(startSector: currentSector + carveOffset, sectorCount: 1) {
                                    fileData.append(nextData)
                                    
                                    if type == "JPEG Image" {
                                        if nextData.range(of: Data([0xFF, 0xD9])) != nil {
                                            break
                                        }
                                    } else if type == "PNG Image" {
                                        if nextData.range(of: Data([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])) != nil {
                                            break
                                        }
                                    } else if type == "MP4 Video" {
                                        // Stop if we hit another header signature
                                        if nextData.count >= 3 && nextData[0] == 0xFF && nextData[1] == 0xD8 && nextData[2] == 0xFF {
                                            break
                                        }
                                        if nextData.count >= 4 && nextData[0] == 0x89 && nextData[1] == 0x50 && nextData[2] == 0x4E && nextData[3] == 0x47 {
                                            break
                                        }
                                        if nextData.count >= 8 && nextData[4] == 0x66 && nextData[5] == 0x74 && nextData[6] == 0x79 && nextData[7] == 0x70 {
                                            break
                                        }
                                        // Moov box detection
                                        if nextData.range(of: Data([0x6D, 0x6F, 0x6F, 0x76])) != nil {
                                            // read a small cushion of sectors
                                            for extra in 1...10 {
                                                if case .success(let extraData) = manager.readSectors(startSector: currentSector + carveOffset + UInt64(extra), sectorCount: 1) {
                                                    fileData.append(extraData)
                                                }
                                            }
                                            break
                                        }
                                    }
                                } else {
                                    break
                                }
                                carveOffset += 1
                            }
                            
                            let record = CarvedFileRecord(
                                type: type,
                                extension: ext,
                                startSector: start,
                                sizeBytes: fileData.count,
                                data: fileData
                            )
                            filesFound.append(record)
                            currentSector += carveOffset
                        }
                    }
                    currentSector += 1
                }
                
                manager.closeDevice()
                DispatchQueue.main.async {
                    self.carvedFiles = filesFound
                    self.isCarving = false
                    self.carvingProgress = 1.0
                    self.carvingStatusMessage = "Carving complete. Recovered \(filesFound.count) files."
                }
                
            case .failure(let error):
                manager.closeDevice()
                DispatchQueue.main.async {
                    self.isCarving = false
                    self.carvingStatusMessage = "Failed to open block device: \(error.localizedDescription)"
                }
            }
        }
    }
    
    public func stopFileCarving() {
        self.isCarving = false
        self.carvingStatusMessage = "Carving cancelled by user."
    }
    
    public func exportCarvedFile(_ record: CarvedFileRecord) {
        let savePanel = NSSavePanel()
        
        #if os(macOS)
        let saveURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.directoryURL = saveURL
        savePanel.nameFieldStringValue = "recovered_sector_\(record.startSector).\(record.extension)"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try record.data.write(to: url)
                    print("[Carver] Successfully exported carved file to: \(url.path)")
                } catch {
                    print("[Carver] Error exporting carved file: \(error.localizedDescription)")
                }
            }
        }
        #endif
    }
    
    // MARK: - Photos Compressed Counter CRUD
    public func loadPhotosCompressedCount() {
        self.totalPhotosCompressed = UserDefaults.standard.integer(forKey: "SDForensicsTotalPhotosCompressed")
    }
    
    public func incrementPhotosCompressedCount(by amount: Int = 1) {
        let defaults = UserDefaults.standard
        let current = defaults.integer(forKey: "SDForensicsTotalPhotosCompressed")
        let updated = current + amount
        defaults.set(updated, forKey: "SDForensicsTotalPhotosCompressed")
        DispatchQueue.main.async {
            self.totalPhotosCompressed = updated
        }
    }
}

public struct CarvedFileRecord: Identifiable, Hashable {
    public let id = UUID()
    public let type: String
    public let `extension`: String
    public let startSector: UInt64
    public let sizeBytes: Int
    public let data: Data
    
    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

public struct DiskInfo: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let sizeString: String
    public let filesystem: String
    public let isMock: Bool
}

public struct FormatStep: Identifiable, Hashable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public var status: StepStatus
    
    public enum StepStatus: Hashable {
        case pending
        case active
        case completed
        case failed(String)
    }
}
