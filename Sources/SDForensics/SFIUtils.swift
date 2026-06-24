import Foundation

/// Custom Signature Schema layout mapping to raw disk blocks (512 bytes).
public struct SDForensicsSignature {
    public static let magicBytes: UInt64 = 0x5344464F52454E53 // "SDFORENS" in Big Endian ASCII
    public static let signatureBlockSector: UInt64 = 34 // GPT reserve or slack space sector
    
    public var magic: UInt64
    public var schemaVersion: UInt16
    public var deviceName: String // Char[16]
    public var ownerID: String // Char[16]
    public var initializationTimestamp: UInt64
    public var previousWearCycleCount: UInt64
    public var iconMetadata: [UInt64] // UInt64[8]
    
    public init(deviceName: String, ownerID: String, previousCycleCount: UInt64 = 0) {
        self.magic = Self.magicBytes
        self.schemaVersion = 1
        self.deviceName = deviceName
        self.ownerID = ownerID
        self.initializationTimestamp = UInt64(Date().timeIntervalSince1970)
        self.previousWearCycleCount = previousCycleCount
        self.iconMetadata = Array(repeating: 0, count: 8)
    }
    
    /// Safely loads unaligned types from raw data.
    public static func loadUnaligned<T: FixedWidthInteger>(from data: Data, offset: Int, type: T.Type) -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return 0 }
        var value: T = 0
        let subdata = data.subdata(in: offset..<(offset + size))
        _ = withUnsafeMutablePointer(to: &value) { valPtr in
            subdata.withUnsafeBytes { srcPtr in
                memcpy(valPtr, srcPtr.baseAddress!, size)
            }
        }
        return value
    }

    /// Deserializes a 512-byte raw block of data into an SDForensicsSignature struct.
    public static func deserialize(from data: Data) -> SDForensicsSignature? {
        guard data.count >= 512 else { return nil }
        
        // Extract magic
        let magicVal = loadUnaligned(from: data, offset: 0, type: UInt64.self).bigEndian
        guard magicVal == magicBytes else { return nil }
        
        // Extract version
        let version = loadUnaligned(from: data, offset: 8, type: UInt16.self).bigEndian
        
        // Extract device name (16 bytes ASCII, zero padded)
        let nameData = data.subdata(in: 10..<26)
        let name = String(data: nameData.filter { $0 != 0 }, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Extract owner ID (16 bytes ASCII, zero padded)
        let ownerData = data.subdata(in: 26..<42)
        let owner = String(data: ownerData.filter { $0 != 0 }, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Extract timestamp
        let ts = loadUnaligned(from: data, offset: 42, type: UInt64.self).bigEndian
        
        // Extract previous wear cycles
        let cycles = loadUnaligned(from: data, offset: 50, type: UInt64.self).bigEndian
        
        var sig = SDForensicsSignature(deviceName: name, ownerID: owner, previousCycleCount: cycles)
        sig.magic = magicVal
        sig.schemaVersion = version
        sig.initializationTimestamp = ts
        
        // Extract icon vector offsets
        var iconOffsets = [UInt64]()
        for i in 0..<8 {
            let offset = 58 + (i * 8)
            let val = loadUnaligned(from: data, offset: offset, type: UInt64.self).bigEndian
            iconOffsets.append(val)
        }
        sig.iconMetadata = iconOffsets
        
        return sig
    }
    
    /// Serializes the struct into a 512-byte block of raw binary data.
    public func serialize() -> Data {
        var data = Data(repeating: 0, count: 512)
        
        // Write Magic (Big Endian)
        var bigMagic = magic.bigEndian
        withUnsafePointer(to: &bigMagic) { ptr in
            data.replaceSubrange(0..<8, with: ptr, count: 8)
        }
        
        // Write Schema Version
        var bigVersion = schemaVersion.bigEndian
        withUnsafePointer(to: &bigVersion) { ptr in
            data.replaceSubrange(8..<10, with: ptr, count: 2)
        }
        
        // Write Device Name (16 bytes)
        var nameBytes = Array(repeating: UInt8(0), count: 16)
        let asciiName = deviceName.prefix(16).compactMap { $0.asciiValue }
        for (index, byte) in asciiName.enumerated() {
            nameBytes[index] = byte
        }
        data.replaceSubrange(10..<26, with: nameBytes)
        
        // Write Owner ID (16 bytes)
        var ownerBytes = Array(repeating: UInt8(0), count: 16)
        let asciiOwner = ownerID.prefix(16).compactMap { $0.asciiValue }
        for (index, byte) in asciiOwner.enumerated() {
            ownerBytes[index] = byte
        }
        data.replaceSubrange(26..<42, with: ownerBytes)
        
        // Write Initialization Timestamp
        var bigTS = initializationTimestamp.bigEndian
        withUnsafePointer(to: &bigTS) { ptr in
            data.replaceSubrange(42..<50, with: ptr, count: 8)
        }
        
        // Write Wear Cycles
        var bigCycles = previousWearCycleCount.bigEndian
        withUnsafePointer(to: &bigCycles) { ptr in
            data.replaceSubrange(50..<58, with: ptr, count: 8)
        }
        
        // Write Icon Metadata Vector
        for i in 0..<8 {
            let offset = 58 + (i * 8)
            var val = (i < iconMetadata.count ? iconMetadata[i] : 0).bigEndian
            withUnsafePointer(to: &val) { ptr in
                data.replaceSubrange(offset..<(offset + 8), with: ptr, count: 8)
            }
        }
        
        // Write structural Boot Signature 0x55AA at offset 510
        let bootSig: UInt16 = 0x55AA
        var bigBootSig = bootSig.bigEndian
        withUnsafePointer(to: &bigBootSig) { ptr in
            data.replaceSubrange(510..<512, with: ptr, count: 2)
        }
        
        return data
    }
}

/// Structured health output categories for SD cards.
public enum SFIHealthClass {
    case healthy
    case warning
    case critical
    
    public var label: String {
        switch self {
        case .healthy: return "🟢 HEALTHY (Optimal for camera capture)"
        case .warning: return "🟡 WARNING (NAND wear detected - use with caution)"
        case .critical: return "🔴 CRITICAL (Severe fatigue - do not use for media production!)"
        }
    }
}

/// SFI (SD Fatigue Index) calculator.
public struct SFICalculator {
    /// Evaluates the fatigue index using the weighted architectural formula.
    public static func calculate(
        badBlocks: UInt64,
        totalBlocks: UInt64,
        estimatedWriteCycles: UInt64,
        maxLatencyMicro: Double,
        baselineLatencyMicro: Double,
        nandCycleTarget: UInt64 = 3000
    ) -> Double {
        guard totalBlocks > 0 else { return 0.0 }
        guard baselineLatencyMicro > 0 else { return 0.0 }
        
        // Weight 1: Bad block ratio (40% weight)
        let badBlockRatio = Double(badBlocks) / Double(totalBlocks)
        let w_badBlock = badBlockRatio * 0.40
        
        // Weight 2: Wear leveling cycles (40% weight)
        let wearRatio = Double(estimatedWriteCycles) / Double(nandCycleTarget)
        let w_wear = min(wearRatio, 1.0) * 0.40
        
        // Weight 3: Write latency degradation (20% weight)
        let latencyDeviation = max(0.0, (maxLatencyMicro - baselineLatencyMicro) / baselineLatencyMicro)
        let w_latency = min(latencyDeviation, 2.0) * 0.10 // Caps latency impact to 20% max index
        
        let rawSFI = w_badBlock + w_wear + w_latency
        return min(max(rawSFI, 0.0), 1.0)
    }
    
    /// Classifies an SFI score into health levels.
    public static func classify(sfi: Double) -> SFIHealthClass {
        if sfi < 0.15 {
            return .healthy
        } else if sfi < 0.40 {
            return .warning
        } else {
            return .critical
        }
    }
}

/// Visual print helpers for CLI
public struct CLIPrinter {
    public static func printHeader(_ text: String) {
        print("\n=== \(text.uppercased()) ===")
    }
    
    public static func printMetric(label: String, value: String, indent: Int = 2) {
        let prefix = String(repeating: " ", count: indent)
        print("\(prefix)• \(label.padding(toLength: 30, withPad: " ", startingAt: 0)): \(value)")
    }
}
