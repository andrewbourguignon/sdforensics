import Foundation

public func runCLIMode(arguments: [String]) {
    func printHelp() {
        print("""
        💾 SD Forensics - Premium macOS SD Card forensics & Tracking Tool
        Usage: SDForensics <command> [options]
        
        Commands:
          list                               Lists connected block devices via diskutil
          analyze <path>                     Performs a read-only forensic analysis & wear audit
          initialize <path> [options]        Zero-wipes and marks the card with custom signature metadata
          benchmark <path>                   Executes quick read/write latency benchmarking
          mock-create <path>                 Creates a 10MB zero-filled mock image file for safe testing
        
        Options:
          --name <deviceName>                Desired custom tracking identifier name (default: "SD_CARD")
          --owner <ownerID>                  Operator or organization reference identifier (default: "STUDIO")
          --force-physical                   Override write protective systems for real physical raw write access
          --cycles <count>                   Pre-load historical wear cycles for formatting index (default: 0)
        """)
    }

    guard arguments.count > 1 else {
        printHelp()
        exit(0)
    }

    let command = arguments[1].lowercased()

    // Option parser helpers
    func getOption(key: String) -> String? {
        if let idx = arguments.firstIndex(of: key), idx + 1 < arguments.count {
            return arguments[idx + 1]
        }
        return nil
    }

    let forcePhysical = arguments.contains("--force-physical")
    let devName = getOption(key: "--name") ?? "SD_CARD"
    let ownerID = getOption(key: "--owner") ?? "STUDIO"
    let prevCycles = UInt64(getOption(key: "--cycles") ?? "0") ?? 0

    switch command {
    case "list":
        CLIPrinter.printHeader("Scanning connected block devices")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["list", "external"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let out = String(data: data, encoding: .utf8) {
                print(out)
            }
        } catch {
            print("Failed to poll disk status: \(error.localizedDescription)")
        }
        
    case "mock-create":
        guard arguments.count > 2 else {
            print("Error: Please specify the output path for the mock disk image file.")
            exit(1)
        }
        let mockPath = arguments[2]
        CLIPrinter.printHeader("Creating safe mock disk file")
        print("Writing zero-fill file to: \(mockPath)")
        
        // Write 10MB (20480 sectors of 512 bytes)
        let sizeBytes = 10 * 1024 * 1024
        let zeroData = Data(repeating: 0, count: sizeBytes)
        do {
            try zeroData.write(to: URL(fileURLWithPath: mockPath))
            print("Mock device image created successfully. Size: 10MB.")
            print("You can now safely test commands against this file without root permissions!")
            print("Example: SDForensics analyze \(mockPath)")
        } catch {
            print("Mock file creation failed: \(error.localizedDescription)")
            exit(1)
        }

    case "analyze":
        guard arguments.count > 2 else {
            print("Error: Missing target disk path.")
            exit(1)
        }
        let target = arguments[2]
        let manager = RawDeviceManager()
        
        print("Opening target for analysis: \(target)...")
        let openResult = manager.openDevice(path: target, writeAccess: false, forcePhysical: forcePhysical)
        
        switch openResult {
        case .success:
            let engine = ForensicEngine(deviceManager: manager)
            let result = engine.executeAudit()
            
            CLIPrinter.printHeader("SD Forensics Audit Report")
            CLIPrinter.printMetric(label: "NAND Health Status", value: result.healthStatus.label)
            CLIPrinter.printMetric(label: "Fatigue Index (SFI)", value: String(format: "%.4f", result.fatigueIndex))
            CLIPrinter.printMetric(label: "Scanned sectors", value: "\(result.scannedSectors) / \(result.totalSectors)")
            CLIPrinter.printMetric(label: "Bad sectors identified", value: "\(result.badSectors)")
            CLIPrinter.printMetric(label: "Estimated Write Cycles", value: "\(result.estimatedWriteCycles)")
            CLIPrinter.printMetric(label: "Avg Read Latency", value: String(format: "%.2f µs", result.averageReadLatencyMicro))
            CLIPrinter.printMetric(label: "Max Read Latency", value: String(format: "%.2f µs", result.maxReadLatencyMicro))
            
            let filesystems = result.detectedFilesystems.joined(separator: ", ")
            CLIPrinter.printMetric(label: "Detected boot filesystems", value: filesystems.isEmpty ? "None / Raw unpartitioned" : filesystems)
            
            if let sig = result.customSignature {
                CLIPrinter.printHeader("Embedded tracking marker metadata")
                CLIPrinter.printMetric(label: "Device Identifier", value: sig.deviceName)
                CLIPrinter.printMetric(label: "Owner ID", value: sig.ownerID)
                CLIPrinter.printMetric(label: "Initialization date", value: Date(timeIntervalSince1970: Double(sig.initializationTimestamp)).description)
                CLIPrinter.printMetric(label: "Previous wear history", value: "\(sig.previousWearCycleCount) cycles")
            } else {
                CLIPrinter.printMetric(label: "Custom signature", value: "No embedded SD Forensics markers found.")
            }
            
            if !result.timeline.isEmpty {
                CLIPrinter.printHeader("Temporal Chronological Ingest Log")
                for event in result.timeline {
                    print("  [\(event.timestampString)] \(event.type) - \(event.description)")
                }
            }
            
        case .failure(let error):
            print("Analysis aborted: \(error.localizedDescription)")
            exit(1)
        }

    case "initialize":
        guard arguments.count > 2 else {
            print("Error: Missing target disk path.")
            exit(1)
        }
        let target = arguments[2]
        let manager = RawDeviceManager()
        
        print("Opening target for formatting: \(target)...")
        let openResult = manager.openDevice(path: target, writeAccess: true, forcePhysical: forcePhysical)
        
        switch openResult {
        case .success:
            let tool = InitializationTool(deviceManager: manager)
            let formatResult = tool.initializeCard(deviceName: devName, ownerID: ownerID, previousCycles: prevCycles)
            
            switch formatResult {
            case .success:
                CLIPrinter.printHeader("Card formatting & marking complete")
                print("Successfully initialized MBR/GPT and custom signature blocks.")
                print("Device ID set to: \(devName)")
                print("Owner ID set to : \(ownerID)")
            case .failure(let error):
                print("Format failed: \(error.localizedDescription)")
                exit(1)
            }
            
        case .failure(let error):
            print("Initialization aborted: \(error.localizedDescription)")
            exit(1)
        }

    case "benchmark":
        guard arguments.count > 2 else {
            print("Error: Missing target disk path.")
            exit(1)
        }
        let target = arguments[2]
        let manager = RawDeviceManager()
        
        print("Opening target for speed diagnostics: \(target)...")
        let openResult = manager.openDevice(path: target, writeAccess: false, forcePhysical: forcePhysical)
        
        switch openResult {
        case .success:
            CLIPrinter.printHeader("Performance benchmarking in progress")
            print("Evaluating block throughput latency...")
            
            var latencySamples = [Double]()
            let totalSectors = min(manager.totalSectors, 50000)
            let sampleStride = max(1, totalSectors / 500) // sample 500 offsets
            
            for sector in stride(from: 0, to: totalSectors, by: Int(sampleStride)) {
                let start = DispatchTime.now()
                let readResult = manager.readSectors(startSector: UInt64(sector), sectorCount: 1)
                let end = DispatchTime.now()
                
                if case .success = readResult {
                    let nano = end.uptimeNanoseconds - start.uptimeNanoseconds
                    latencySamples.append(Double(nano) / 1000.0)
                }
            }
            
            if !latencySamples.isEmpty {
                let avg = latencySamples.reduce(0, +) / Double(latencySamples.count)
                let maxL = latencySamples.max() ?? 0.0
                let minL = latencySamples.min() ?? 0.0
                
                CLIPrinter.printMetric(label: "Sectors sampled", value: "\(latencySamples.count)")
                CLIPrinter.printMetric(label: "Minimum Read Latency", value: String(format: "%.2f µs", minL))
                CLIPrinter.printMetric(label: "Average Read Latency", value: String(format: "%.2f µs", avg))
                CLIPrinter.printMetric(label: "Maximum Read Latency", value: String(format: "%.2f µs", maxL))
                
                // Speed category evaluation
                let speedScore = avg < 20.0 ? "High Speed Class 10/UHS (Excellent)" : (avg < 50.0 ? "Standard Speed (Good)" : "Slow/Fatigued NAND Media (Poor)")
                CLIPrinter.printMetric(label: "Estimated Speed Class", value: speedScore)
            } else {
                print("Failed to gather benchmark latency samples.")
            }
            
        case .failure(let error):
            print("Benchmarking aborted: \(error.localizedDescription)")
            exit(1)
        }

    default:
        print("Unknown command: \(command)")
        printHelp()
    }
}
