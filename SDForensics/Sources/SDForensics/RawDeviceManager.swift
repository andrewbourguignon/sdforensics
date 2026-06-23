import Foundation

public class RawDeviceManager {
    private var fileDescriptor: Int32 = -1
    private var targetPath: String = ""
    public private(set) var isMock: Bool = false
    public private(set) var sectorSize: UInt32 = 512
    public private(set) var totalSectors: UInt64 = 0
    
    public init() {}
    
    /// Prepares raw access to either a virtual mock file or a physical device path.
    public func openDevice(path: String, writeAccess: Bool = false, forcePhysical: Bool = false) -> Result<Void, Error> {
        self.targetPath = path
        
        // Step 1: Detect if this is a virtual mock image file rather than a physical block device
        let isBlockDevice = path.hasPrefix("/dev/")
        self.isMock = !isBlockDevice
        
        if isMock {
            print("[Module 1] RawDeviceManager configured in VIRTUAL FILE MOCK MODE.")
            return openMockFile(path: path, writeAccess: writeAccess)
        } else {
            // Safety Check: Only require forcePhysical for WRITE operations.
            // Read-only audits are non-destructive and should work without the toggle.
            if writeAccess {
                guard forcePhysical else {
                    return .failure(DeviceError.safetyViolation("Write access to physical disks requires explicit confirmation. Enable the 'Force Physical' toggle."))
                }
            }
            
            // Check for root privilege
            guard getuid() == 0 else {
                return .failure(DeviceError.privilegeEscalationRequired)
            }
            
            return openPhysicalDevice(path: path, writeAccess: writeAccess)
        }
    }
    
    /// Opens a local file representing a virtual SD card block structure.
    private func openMockFile(path: String, writeAccess: Bool) -> Result<Void, Error> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return .failure(DeviceError.mockFileNotFound("Mock disk image does not exist at: \(path)"))
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            if let size = attributes[.size] as? UInt64 {
                self.totalSectors = size / UInt64(self.sectorSize)
            }
        } catch {
            return .failure(DeviceError.deviceAttributesFailed(error.localizedDescription))
        }
        
        // Open file using POSIX file descriptors
        let flags = writeAccess ? (O_RDWR) : (O_RDONLY)
        let fd = open(path, flags)
        guard fd != -1 else {
            return .failure(DeviceError.openFailed(errno: errno))
        }
        
        self.fileDescriptor = fd
        return .success(())
    }
    
    /// Safely opens a physical BSD disk device. Unmounts only for write access.
    private func openPhysicalDevice(path: String, writeAccess: Bool) -> Result<Void, Error> {
        // Build both device path variants
        let charPath: String  // /dev/rdiskX — raw character device (faster, bypasses buffer cache)
        let blockPath: String // /dev/diskX  — block device (more permissive on modern macOS)
        
        if path.hasPrefix("/dev/rdisk") {
            charPath = path
            blockPath = path.replacingOccurrences(of: "/dev/rdisk", with: "/dev/disk")
        } else if path.hasPrefix("/dev/disk") {
            charPath = path.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk")
            blockPath = path
        } else {
            charPath = path
            blockPath = path
        }
        
        // Extract disk identifier (e.g. "4" from /dev/rdisk4s1)
        let diskIdentifier = charPath.replacingOccurrences(of: "/dev/rdisk", with: "")
            .split(separator: "s")[0]
        
        // Only unmount for write operations — reads work fine on mounted volumes
        // and force-unmounting can trigger kernel device lockouts on macOS Tahoe.
        if writeAccess {
            print("[Module 1] Attempting to unmount external volume: disk\(diskIdentifier)")
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            task.arguments = ["unmountDisk", "force", "disk\(diskIdentifier)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("[Module 1] diskutil output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                return .failure(DeviceError.unmountFailed("Failed to spawn diskutil: \(error.localizedDescription)"))
            }
            
            guard task.terminationStatus == 0 else {
                return .failure(DeviceError.unmountFailed("diskutil could not unmount the card. Check if it is currently in use."))
            }
        }
        
        // Open the device descriptor.
        // Strategy: try character device first (faster DMA), fall back to block device
        // if macOS denies access (common on Tahoe for raw character devices).
        let writeFlags = O_RDWR | O_NDELAY
        let readFlags  = O_RDONLY
        let flags = writeAccess ? writeFlags : readFlags
        
        var fd = open(charPath, flags)
        var usedPath = charPath
        
        if fd == -1 {
            let firstErrno = errno
            print("[Module 1] Character device open failed (\(charPath), errno \(firstErrno)). Trying block device...")
            fd = open(blockPath, flags)
            usedPath = blockPath
            
            if fd == -1 {
                let secondErrno = errno
                print("[Module 1] Block device open also failed (\(blockPath), errno \(secondErrno)).")
                // Errno 1 (EPERM) from root = macOS Full Disk Access restriction
                if firstErrno == 1 || secondErrno == 1 {
                    return .failure(DeviceError.fullDiskAccessRequired)
                }
                return .failure(DeviceError.openFailed(errno: firstErrno))
            }
        }
        
        print("[Module 1] Opened device via \(usedPath) (uid=\(getuid()))")
        
        // Apply F_NOCACHE to bypass Unified Buffer Cache (UBC) for forensic accuracy
        if fcntl(fd, F_NOCACHE, 1) == -1 {
            print("[Module 1] Warning: F_NOCACHE could not be applied. Buffered values may occur.")
        }
        
        self.fileDescriptor = fd
        
        // Determine physical device size via IOCTL
        var sectorCount: UInt64 = 0
        // DKIOCGETBLOCKCOUNT code is 0x40086419 (defined in Darwin /usr/include/sys/disk.h)
        let getBlockCount = ioctl(fd, 0x40086419, &sectorCount)
        if getBlockCount != -1 {
            self.totalSectors = sectorCount
        } else {
            // Fallback estimation using lseek to end
            let size = lseek(fd, 0, SEEK_END)
            if size != -1 {
                self.totalSectors = UInt64(size) / UInt64(self.sectorSize)
            }
        }
        
        print("[Module 1] Physical device successfully opened. Found \(self.totalSectors) sectors.")
        return .success(())
    }
    
    /// Reads arbitrary block ranges directly from device file descriptor.
    public func readSectors(startSector: UInt64, sectorCount: UInt32) -> Result<Data, Error> {
        guard fileDescriptor != -1 else {
            return .failure(DeviceError.deviceNotOpen)
        }
        
        let offset = off_t(startSector * UInt64(self.sectorSize))
        let totalBytes = Int(sectorCount * self.sectorSize)
        var buffer = [UInt8](repeating: 0, count: totalBytes)
        
        // Shift file pointer
        guard lseek(fileDescriptor, offset, SEEK_SET) != -1 else {
            return .failure(DeviceError.seekFailed(errno: errno))
        }
        
        // Perform direct system read
        let bytesRead = read(fileDescriptor, &buffer, totalBytes)
        guard bytesRead == totalBytes else {
            let err = errno
            return .failure(DeviceError.readFailed(bytesRead: bytesRead, expected: totalBytes, errno: err))
        }
        
        return .success(Data(buffer))
    }
    
    /// Writes raw sectors to target.
    public func writeSectors(startSector: UInt64, data: Data) -> Result<Void, Error> {
        guard fileDescriptor != -1 else {
            return .failure(DeviceError.deviceNotOpen)
        }
        
        let offset = off_t(startSector * UInt64(self.sectorSize))
        let totalBytes = data.count
        
        guard lseek(fileDescriptor, offset, SEEK_SET) != -1 else {
            return .failure(DeviceError.seekFailed(errno: errno))
        }
        
        let bytesWritten = data.withUnsafeBytes { rawBuffer in
            write(fileDescriptor, rawBuffer.baseAddress, totalBytes)
        }
        
        guard bytesWritten == totalBytes else {
            let err = errno
            return .failure(DeviceError.writeFailed(bytesWritten: bytesWritten, expected: totalBytes, errno: err))
        }
        
        return .success(())
    }
    
    /// Gracefully closes connection.
    public func closeDevice() {
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
            print("[Module 1] Device closed.")
        }
    }
    
    deinit {
        closeDevice()
    }
}

// MARK: - Device Errors
public enum DeviceError: LocalizedError {
    case safetyViolation(String)
    case privilegeEscalationRequired
    case fullDiskAccessRequired
    case mockFileNotFound(String)
    case deviceAttributesFailed(String)
    case openFailed(errno: Int32)
    case unmountFailed(String)
    case deviceNotOpen
    case seekFailed(errno: Int32)
    case readFailed(bytesRead: Int, expected: Int, errno: Int32)
    case writeFailed(bytesWritten: Int, expected: Int, errno: Int32)
    
    public var errorDescription: String? {
        switch self {
        case .safetyViolation(let msg): return "SAFETY ERROR: \(msg)"
        case .privilegeEscalationRequired: return "PERMISSION ERROR: Root privileges (sudo) are required to open raw physical disks. The app must be launched with admin privileges."
        case .fullDiskAccessRequired: return "FULL DISK ACCESS REQUIRED: macOS blocks raw device access until you grant Full Disk Access. Open System Settings → Privacy & Security → Full Disk Access, click '+', and add SDForensics. Then restart the app."
        case .mockFileNotFound(let msg): return "MOCK FILE ERROR: \(msg)"
        case .deviceAttributesFailed(let msg): return "METADATA ERROR: \(msg)"
        case .openFailed(let err): return "POSIX error opening disk (Errno: \(err))"
        case .unmountFailed(let msg): return "DISK DETACH FAILED: \(msg)"
        case .deviceNotOpen: return "I/O ERROR: Device descriptor is not initialized."
        case .seekFailed(let err): return "POSIX seek operation failed (Errno: \(err))"
        case .readFailed(let r, let e, let err): return "POSIX read failed: Read \(r) of \(e) bytes (Errno: \(err))"
        case .writeFailed(let w, let e, let err): return "POSIX write failed: Wrote \(w) of \(e) bytes (Errno: \(err))"
        }
    }
}
