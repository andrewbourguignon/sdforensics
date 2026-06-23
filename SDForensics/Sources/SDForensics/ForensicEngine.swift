import Foundation

/// Analyzes raw sector streams to compile digital forensics usage statistics and fatigue metrics.
public class ForensicEngine {
    private let deviceManager: RawDeviceManager
    
    public init(deviceManager: RawDeviceManager) {
        self.deviceManager = deviceManager
    }
    
    /// Executes a complete forensic scan of the raw device.
    public func executeAudit() -> ForensicAuditResult {
        print("[Module 2] Initiating deep forensic block scan...")
        
        var badSectorsCount: UInt64 = 0
        var totalSectorsScanned: UInt64 = 0
        var estimatedWriteCount: UInt64 = 0
        var foundSignature: SDForensicsSignature? = nil
        var latencySum: Double = 0
        var maxLatency: Double = 0
        var latencySamplesCount = 0
        
        var detectedFilesystems = [String]()
        var timelines = [TimelineEvent]()
        
        let targetSectors = min(deviceManager.totalSectors, 100000) // Scan up to first 100,000 sectors (50MB) for efficiency/metadata
        let step: UInt64 = 1 // Read sequential sectors
        
        // Read signature block from its known sector (Sector 34)
        if let sigData = try? deviceManager.readSectors(startSector: SDForensicsSignature.signatureBlockSector, sectorCount: 1).get() {
            if let sig = SDForensicsSignature.deserialize(from: sigData) {
                foundSignature = sig
                print("[Module 2] Found SD Forensics custom marker: \(sig.deviceName) (Owner: \(sig.ownerID))")
            }
        }
        
        // Scan metadata sectors
        for sector in stride(from: 0, to: targetSectors, by: Int(step)) {
            let start = DispatchTime.now()
            let readResult = deviceManager.readSectors(startSector: UInt64(sector), sectorCount: 1)
            let end = DispatchTime.now()
            
            let latencyNano = end.uptimeNanoseconds - start.uptimeNanoseconds
            let latencyMicro = Double(latencyNano) / 1000.0
            
            totalSectorsScanned += 1
            
            switch readResult {
            case .success(let data):
                latencySum += latencyMicro
                latencySamplesCount += 1
                if latencyMicro > maxLatency {
                    maxLatency = latencyMicro
                }
                
                // Parse sector for filesystem headers or patterns
                if sector == 0 {
                    if let fs = detectFilesystemHeader(data: data) {
                        detectedFilesystems.append(fs)
                    }
                }
                
                // Estimate activity counts based on deleted directory entry marks or FAT changes
                let (writes, parsedEvents) = auditDirectoriesAndAllocation(data: data, sectorOffset: UInt64(sector))
                estimatedWriteCount += writes
                timelines.append(contentsOf: parsedEvents)
                
            case .failure:
                badSectorsCount += 1
                print("[Module 2] Write/Read failure flagged at sector \(sector)")
            }
        }
        
        let avgLatency = latencySamplesCount > 0 ? (latencySum / Double(latencySamplesCount)) : 50.0
        
        // If an embedded signature was written previously, inject its wear history
        if let sig = foundSignature {
            estimatedWriteCount += sig.previousWearCycleCount
        }
        
        // Calculate SFI index
        let sfi = SFICalculator.calculate(
            badBlocks: badSectorsCount,
            totalBlocks: max(1, deviceManager.totalSectors),
            estimatedWriteCycles: estimatedWriteCount,
            maxLatencyMicro: maxLatency,
            baselineLatencyMicro: avgLatency
        )
        
        let health = SFICalculator.classify(sfi: sfi)
        
        // Sort timelines chronologically
        let sortedTimeline = timelines.sorted(by: { $0.timestamp < $1.timestamp })
        
        return ForensicAuditResult(
            scannedSectors: totalSectorsScanned,
            totalSectors: deviceManager.totalSectors,
            badSectors: badSectorsCount,
            estimatedWriteCycles: estimatedWriteCount,
            averageReadLatencyMicro: avgLatency,
            maxReadLatencyMicro: maxLatency,
            detectedFilesystems: detectedFilesystems,
            customSignature: foundSignature,
            timeline: Array(sortedTimeline.prefix(50)), // cap representation to top 50 chronological markers
            fatigueIndex: sfi,
            healthStatus: health
        )
    }
    
    /// Detects common embedded filesystem identifiers in Boot sectors.
    private func detectFilesystemHeader(data: Data) -> String? {
        guard data.count >= 512 else { return nil }
        
        // Check exFAT magic: "EXFAT   " at offset 3
        let exfatMagic = String(data: data.subdata(in: 3..<11), encoding: .ascii) ?? ""
        if exfatMagic == "EXFAT   " {
            return "exFAT Filesystem Boot Record"
        }
        
        // Check FAT32 magic: "FAT32   " at offset 82
        if data.count >= 90 {
            let fat32Magic = String(data: data.subdata(in: 82..<90), encoding: .ascii) ?? ""
            if fat32Magic == "FAT32   " {
                return "FAT32 Volume Boot Record"
            }
        }
        
        // Check MBR partition indicator
        let bootIndicator = SDForensicsSignature.loadUnaligned(from: data, offset: 510, type: UInt16.self).bigEndian
        if bootIndicator == 0x55AA {
            return "MBR / Partition Table Header"
        }
        
        return nil
    }
    
    /// Inspects sector structure for directory listings, deletion markers, and timestamps.
    private func auditDirectoriesAndAllocation(data: Data, sectorOffset: UInt64) -> (writes: UInt64, timeline: [TimelineEvent]) {
        var estimatedWrites: UInt64 = 0
        var events = [TimelineEvent]()
        
        // Directory entry scans (typically looking for exFAT / FAT directory sequences)
        // exFAT directories start with 0x85 (File directory entry), followed by 0xC0 (Stream extension)
        // FAT directories contain deletion markers (0xE5) at the start of the 32-byte record.
        var offset = 0
        while offset <= data.count - 32 {
            let recordType = data[offset]
            
            // Deleted directory identifier for FAT12/16/32
            if recordType == 0xE5 {
                estimatedWrites += 1
            }
            
            // exFAT File Directory entry parsing
            if recordType == 0x85 {
                // Secondary file entry has modification times at offsets offset + 8, offset + 14, offset + 20
                // Let's decode DOS packed timestamp fields.
                // exFAT Stream Extension entry is at offset + 32
                if offset + 64 <= data.count {
                    let creationTimeRaw = SDForensicsSignature.loadUnaligned(from: data, offset: offset + 8, type: UInt32.self).bigEndian
                    let modTimeRaw = SDForensicsSignature.loadUnaligned(from: data, offset: offset + 14, type: UInt32.self).bigEndian
                    
                    if let cDate = parseDOSDateTime(packed: creationTimeRaw) {
                        events.append(TimelineEvent(timestamp: cDate, type: "File Created", description: "Found entry at sector \(sectorOffset), offset \(offset)"))
                    }
                    if let mDate = parseDOSDateTime(packed: modTimeRaw) {
                        events.append(TimelineEvent(timestamp: mDate, type: "File Modified", description: "Found entry at sector \(sectorOffset), offset \(offset)"))
                    }
                    
                    // Increment estimated writes since adding files updates directory blocks
                    estimatedWrites += 1
                }
            }
            
            offset += 32
        }
        
        return (estimatedWrites, events)
    }
    
    /// Decodes a 32-bit DOS packed Date and Time structure.
    private func parseDOSDateTime(packed: UInt32) -> Date? {
        guard packed > 0 else { return nil }
        
        // Low 16 bits = Time (Hour: 5, Min: 6, Sec: 5)
        // High 16 bits = Date (Year offset from 1980: 7, Month: 4, Day: 5)
        let datePart = UInt16((packed >> 16) & 0xFFFF)
        let timePart = UInt16(packed & 0xFFFF)
        
        let seconds = Int((timePart & 0x001F) * 2)
        let minutes = Int((timePart >> 5) & 0x003F)
        let hours = Int((timePart >> 11) & 0x001F)
        
        let day = Int(datePart & 0x001F)
        let month = Int((datePart >> 5) & 0x000F)
        let year = Int((datePart >> 9) & 0x007F) + 1980
        
        guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else { return nil }
        guard hours < 24 && minutes < 60 && seconds < 60 else { return nil }
        
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hours
        comps.minute = minutes
        comps.second = seconds
        comps.timeZone = TimeZone.current
        
        return Calendar.current.date(from: comps)
    }
}

/// Structured response container for SD card forensic statistics.
public struct ForensicAuditResult {
    public let scannedSectors: UInt64
    public let totalSectors: UInt64
    public let badSectors: UInt64
    public let estimatedWriteCycles: UInt64
    public let averageReadLatencyMicro: Double
    public let maxReadLatencyMicro: Double
    public let detectedFilesystems: [String]
    public let customSignature: SDForensicsSignature?
    public let timeline: [TimelineEvent]
    public let fatigueIndex: Double
    public let healthStatus: SFIHealthClass
}

/// Event tracker for MACB timeline graphs.
public struct TimelineEvent {
    public let timestamp: Date
    public let type: String
    public let description: String
    
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        let format = "yyyy-MM-dd HH:mm:ss"
        df.dateFormat = format
        return df
    }()
    
    public var timestampString: String {
        return Self.formatter.string(from: timestamp)
    }
}
