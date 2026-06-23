import Foundation
import Combine

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
    @Published var directoryPreset: CameraDirectoryPreset = .none
    @Published var formatSteps: [FormatStep] = []
    
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
    
    public init() {
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
        let targetPreset = self.directoryPreset
        
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
                    directoryPreset: targetPreset,
                    mountPoint: targetMountPoint,
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
        
        self.isBenchmarking = true
        self.benchmarkProgress = 0.0
        self.benchmarkResult = nil
        let mountPoint = identity.mountPoint
        
        // Progress updater
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.benchmarkProgress < 0.9 {
                self.benchmarkProgress += 0.02
            } else {
                timer.invalidate()
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardInfoEngine.runBenchmark(mountPoint: mountPoint)
            DispatchQueue.main.async {
                progressTimer.invalidate()
                self.benchmarkProgress = 1.0
                self.benchmarkResult = result
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
