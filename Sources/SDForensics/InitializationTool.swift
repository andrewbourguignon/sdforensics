import Foundation
#if os(macOS)
import AppKit
#endif

public enum WipeLevel: String, CaseIterable, Identifiable {
    case quick = "Quick Wipe"
    case secure = "Secure Zero-Fill"
    case forensic = "Forensic Overwrite"
    
    public var id: String { self.rawValue }
}

public struct CameraPreset: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var directories: [String]
    public var iconPath: String?

    public init(id: UUID = UUID(), name: String, directories: [String], iconPath: String? = nil) {
        self.id = id
        self.name = name
        self.directories = directories
        self.iconPath = iconPath
    }
}

extension CameraPreset {
    public static let none = CameraPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "None (Raw Data Block Stamping only)", directories: [], iconPath: nil)
    
    public static let builtIns: [CameraPreset] = [
        CameraPreset(name: "Sony XAVC-S (M4ROOT/CLIP)", directories: [
            "PRIVATE/M4ROOT/CLIP",
            "PRIVATE/M4ROOT/SUB",
            "PRIVATE/M4ROOT/GENERAL",
            "PRIVATE/M4ROOT/THMBNL"
        ]),
        CameraPreset(name: "Canon EOS Standard (DCIM/100CANON)", directories: [
            "DCIM/100CANON"
        ]),
        CameraPreset(name: "RED Digital Cinema (DCIM/RED)", directories: [
            "DCIM/RED"
        ]),
        CameraPreset(name: "ARRI Alexa Standard (ARRI)", directories: [
            "ARRI/CLIP",
            "ARRI/MISC"
        ]),
        CameraPreset(name: "Blackmagic Design (DCIM/BMD)", directories: [
            "DCIM/BMD"
        ]),
        CameraPreset(name: "Panasonic LUMIX (PRIVATE/AVCHD)", directories: [
            "PRIVATE/AVCHD",
            "PRIVATE/PANA_GRP"
        ]),
        CameraPreset(name: "GoPro HERO Standard (DCIM/100GOPRO)", directories: [
            "DCIM/100GOPRO"
        ]),
        CameraPreset(name: "Generic Camera DCIM (DCIM)", directories: [
            "DCIM"
        ])
    ]
}

public class InitializationTool {
    private let deviceManager: RawDeviceManager
    
    public init(deviceManager: RawDeviceManager) {
        self.deviceManager = deviceManager
    }
    
    /// Executes the multi-step formatted write and marking sequence.
    public func initializeCard(
        deviceName: String,
        ownerID: String,
        previousCycles: UInt64 = 0,
        wipeLevel: WipeLevel = .quick,
        directories: [String] = [],
        mountPoint: String = "",
        customImagePath: String? = nil,
        onStepProgress: @escaping (Int, String) -> Void = { _, _ in }
    ) -> Result<Void, Error> {
        print("[Module 3] Commencing safe initialization and custom marking process...")
        
        // Step 0: Prepare target disk unmount
        onStepProgress(0, "Preparing device partition unmount...")
        
        // Step 1: Backup current partition structures (MBR at sector 0, GPT headers at sectors 1 to 33)
        onStepProgress(1, "Archiving existing GPT partition tables...")
        let backupResult = performPartitionBackup()
        switch backupResult {
        case .success(let backupPath):
            print("[Module 3] STEP 1: Partition table backup successfully saved to: \(backupPath)")
        case .failure(let error):
            print("[Module 3] Backup failed. Safety protocols reject formatting: \(error.localizedDescription)")
            return .failure(error)
        }
        
        // Step 2: Perform raw data wipe based on wipeLevel
        onStepProgress(2, "Erasing target block allocation tables (\(wipeLevel.rawValue))...")
        print("[Module 3] STEP 2: Performing \(wipeLevel.rawValue)...")
        
        let sectorsToWipe = (wipeLevel == .quick) ? 2 : 100
        var wipeData: Data
        
        if wipeLevel == .forensic {
            // Generate cryptographically secure random bytes
            var randomBytes = [UInt8](repeating: 0, count: Int(deviceManager.sectorSize))
            _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            wipeData = Data(randomBytes)
        } else {
            wipeData = Data(repeating: 0, count: Int(deviceManager.sectorSize))
        }
        
        for sector in 0..<sectorsToWipe {
            let writeResult = deviceManager.writeSectors(startSector: UInt64(sector), data: wipeData)
            if case .failure(let error) = writeResult {
                print("[Module 3] Wipe failed at sector \(sector): \(error.localizedDescription)")
                return .failure(error)
            }
        }
        
        // Also wipe sector 34 (where signature goes) to ensure a clean slate
        let wipeSigResult = deviceManager.writeSectors(startSector: SDForensicsSignature.signatureBlockSector, data: Data(repeating: 0, count: Int(deviceManager.sectorSize)))
        if case .failure(let error) = wipeSigResult {
            print("[Module 3] Signature block wipe failed: \(error.localizedDescription)")
            return .failure(error)
        }
        print("[Module 3] Region wipe completed.")
        
        // Step 3: Embed proprietary custom signature block
        onStepProgress(3, "Injecting wear tracking metadata stamp...")
        print("[Module 3] STEP 3: Constructing and writing custom signature block...")
        let signature = SDForensicsSignature(deviceName: deviceName, ownerID: ownerID, previousCycleCount: previousCycles)
        let serializedSignature = signature.serialize()
        
        let sigWriteResult = deviceManager.writeSectors(
            startSector: SDForensicsSignature.signatureBlockSector,
            data: serializedSignature
        )
        switch sigWriteResult {
        case .success:
            print("[Module 3] Custom tracking marker written to sector \(SDForensicsSignature.signatureBlockSector).")
        case .failure(let error):
            print("[Module 3] Signature block write failed: \(error.localizedDescription)")
            return .failure(error)
        }
        
        // Step 4: Write standard Protective MBR and basic GPT partition structures to the disk
        onStepProgress(4, "Reconstructing Protective MBR/GPT layouts...")
        print("[Module 3] STEP 4: Initializing basic MBR/GPT structures...")
        let initTableResult = writeProtectiveMBRAndGPT()
        switch initTableResult {
        case .success:
            print("[Module 3] Partition layouts successfully written.")
        case .failure(let error):
            print("[Module 3] Partition writing failed: \(error.localizedDescription)")
            return .failure(error)
        }
        
        // Step 5: Create camera directory structures if selected
        if !directories.isEmpty && !mountPoint.isEmpty {
            onStepProgress(5, "Provisioning camera directory templates...")
            print("[Module 3] STEP 5: Provisioning directories: \(directories)")
            
            let fm = FileManager.default
            for dir in directories {
                let fullPath = "\(mountPoint)/\(dir)"
                do {
                    try fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true, attributes: nil)
                    print("[Module 3] Created directory: \(fullPath)")
                } catch {
                    print("[Module 3] Failed to create directory: \(fullPath), error: \(error.localizedDescription)")
                }
            }
        }
        
        // Step 5.5: Copy custom reference image and apply volume Finder icon if provided
        if let imgPath = customImagePath, !imgPath.isEmpty, !mountPoint.isEmpty {
            print("[Module 3] Custom reference image path supplied: \(imgPath)")
            let fm = FileManager.default
            let sourceURL = URL(fileURLWithPath: imgPath)
            let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
            let destURL = URL(fileURLWithPath: "\(mountPoint)/OWNER_CARD.\(ext)")
            
            do {
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourceURL, to: destURL)
                print("[Module 3] Copied reference image to card root: \(destURL.lastPathComponent)")
            } catch {
                print("[Module 3] Warning: Failed to copy reference image: \(error.localizedDescription)")
            }
            
            #if os(macOS)
            if let image = NSImage(contentsOfFile: imgPath) {
                let success = NSWorkspace.shared.setIcon(image, forFile: mountPoint, options: [])
                print("[Module 3] Applied custom volume Finder icon: \(success ? "Success" : "Failed")")
            }
            #endif
        }
        
        onStepProgress(6, "Formatting and stamping completed successfully.")
        return .success(())
    }
    
    /// Reads critical partition blocks and archives them locally.
    private func performPartitionBackup() -> Result<String, Error> {
        // Read sectors 0 to 34
        let readResult = deviceManager.readSectors(startSector: 0, sectorCount: 35)
        switch readResult {
        case .success(let data):
            let timestamp = Int(Date().timeIntervalSince1970)
            
            // Create backup directory within the user's home folder
            let fileManager = FileManager.default
            let backupDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".sdforensics/backups").path
            
            do {
                if !fileManager.fileExists(atPath: backupDir) {
                    try fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                let backupFile = "\(backupDir)/backup_\(timestamp).bin"
                try data.write(to: URL(fileURLWithPath: backupFile))
                return .success(backupFile)
            } catch {
                return .failure(DeviceError.unmountFailed("Failed to write backup image: \(error.localizedDescription)"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Builds and writes a standard Protective MBR structure to Sector 0, 
    /// followed by basic GPT formatting blocks.
    private func writeProtectiveMBRAndGPT() -> Result<Void, Error> {
        var mbrSector = Data(repeating: 0, count: Int(deviceManager.sectorSize))
        
        mbrSector[446] = 0x00
        mbrSector[447] = 0x00
        mbrSector[448] = 0x02
        mbrSector[449] = 0x00
        mbrSector[450] = 0xEE // Protective GPT code
        
        // Write standard partition sector boundary details (Little Endian bytes)
        var startLBA: UInt32 = 1
        withUnsafePointer(to: &startLBA) { ptr in
            mbrSector.replaceSubrange(454..<458, with: ptr, count: 4)
        }
        
        var totalSizeSectors = UInt32(min(deviceManager.totalSectors - 1, UInt64(UInt32.max)))
        withUnsafePointer(to: &totalSizeSectors) { ptr in
            mbrSector.replaceSubrange(458..<462, with: ptr, count: 4)
        }
        
        // Write standard boot code validation signature
        mbrSector[510] = 0x55
        mbrSector[511] = 0xAA
        
        let mbrWriteResult = deviceManager.writeSectors(startSector: 0, data: mbrSector)
        if case .failure(let error) = mbrWriteResult {
            return .failure(error)
        }
        
        // Write a basic GPT Header at sector 1
        var gptHeader = Data(repeating: 0, count: Int(deviceManager.sectorSize))
        
        // Magic header GUID: "EFI PART" (ASCII)
        let gptMagic = "EFI PART".compactMap { $0.asciiValue }
        gptHeader.replaceSubrange(0..<8, with: gptMagic)
        
        // Revision: 1.0 (0x00010000)
        gptHeader[8] = 0x00
        gptHeader[9] = 0x00
        gptHeader[10] = 0x01
        gptHeader[11] = 0x00
        
        // Header Size: 92 bytes
        var headerSize: UInt32 = 92
        withUnsafePointer(to: &headerSize) { ptr in
            gptHeader.replaceSubrange(12..<16, with: ptr, count: 4)
        }
        
        // Current LBA: 1
        var currentLBA: UInt64 = 1
        withUnsafePointer(to: &currentLBA) { ptr in
            gptHeader.replaceSubrange(24..<32, with: ptr, count: 8)
        }
        
        // Backup LBA: Last sector of disk
        var backupLBA: UInt64 = deviceManager.totalSectors - 1
        withUnsafePointer(to: &backupLBA) { ptr in
            gptHeader.replaceSubrange(32..<40, with: ptr, count: 8)
        }
        
        // First Usable LBA: 34 (leaving space for custom signature in block 34)
        var firstUsable: UInt64 = 35
        withUnsafePointer(to: &firstUsable) { ptr in
            gptHeader.replaceSubrange(40..<48, with: ptr, count: 8)
        }
        
        // Last Usable LBA: totalSectors - 34
        var lastUsable: UInt64 = deviceManager.totalSectors - 35
        withUnsafePointer(to: &lastUsable) { ptr in
            gptHeader.replaceSubrange(48..<56, with: ptr, count: 8)
        }
        
        // Write partition table structures to Sector 1
        let gptWriteResult = deviceManager.writeSectors(startSector: 1, data: gptHeader)
        if case .failure(let error) = gptWriteResult {
            return .failure(error)
        }
        
        return .success(())
    }
}
