import SwiftUI

struct VirtualSimulatorView: View {
    @ObservedObject var stateManager: AppStateManager
    @State private var fileName = "test_sd_mock.img"
    @State private var folderPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var isCreating = false
    @State private var showMessage = false
    @State private var logText = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Virtual Drive Simulator")
                        .font(.title)
                        .bold()
                    Text("Create and load local disk image files to safely verify forensic scans and formatting logic.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Form Configuration
                VStack(alignment: .leading, spacing: 16) {
                    Text("Create Virtual Card Image (10 MB)")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Output Folder:")
                                .frame(width: 100, alignment: .leading)
                            TextField("Folder Path", text: $folderPath)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Text("File Name:")
                                .frame(width: 100, alignment: .leading)
                            TextField("Filename", text: $fileName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    Button(action: createMockFile) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Text("Create & Mount Virtual Card")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(isCreating)
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(12)
                
                // Active configuration details
                if showMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Virtual image mounted successfully!")
                                .bold()
                        }
                        Text(logText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(30)
        }
    }
    
    private func createMockFile() {
        isCreating = true
        showMessage = false
        
        let path = "\(folderPath)/\(fileName)"
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Write 10MB file seeded with forensic signatures
            let sizeBytes = 10 * 1024 * 1024
            var zeroData = Data(repeating: 0, count: sizeBytes)
            
            // Seed some mock JPEG at Sector 500 (offset 256,000 bytes)
            let jpegOffset = 500 * 512
            let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
            let jpegFooter = Data([0xFF, 0xD9])
            zeroData.replaceSubrange(jpegOffset..<(jpegOffset + jpegHeader.count), with: jpegHeader)
            zeroData.replaceSubrange((jpegOffset + 2000)..<(jpegOffset + 2000 + jpegFooter.count), with: jpegFooter)
            
            // Seed some mock PNG at Sector 1500 (offset 768,000 bytes)
            let pngOffset = 1500 * 512
            let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let pngFooter = Data([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
            zeroData.replaceSubrange(pngOffset..<(pngOffset + pngHeader.count), with: pngHeader)
            zeroData.replaceSubrange((pngOffset + 4000)..<(pngOffset + 4000 + pngFooter.count), with: pngFooter)
            
            // Seed some mock MP4 at Sector 3000 (offset 1,536,000 bytes)
            let mp4Offset = 3000 * 512
            let mp4Header = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32])
            let mp4Moov = Data([0x6D, 0x6F, 0x6F, 0x76])
            zeroData.replaceSubrange(mp4Offset..<(mp4Offset + mp4Header.count), with: mp4Header)
            zeroData.replaceSubrange((mp4Offset + 6000)..<(mp4Offset + 6000 + mp4Moov.count), with: mp4Moov)
            
            do {
                try zeroData.write(to: URL(fileURLWithPath: path))
                
                DispatchQueue.main.async {
                    self.isCreating = false
                    self.logText = "Created raw block file at: \(path)\nReady for read/write sweeps."
                    self.showMessage = true
                    
                    // Update state manager target mock and refresh
                    stateManager.mockFilePath = path
                    stateManager.refreshDisks()
                    
                    // Select this mock disk automatically
                    if let mockDisk = stateManager.connectedDisks.first(where: { $0.path == path }) {
                        stateManager.selectedDisk = mockDisk
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCreating = false
                    self.logText = "Failed to write mock image: \(error.localizedDescription)"
                    self.showMessage = true
                }
            }
        }
    }
}
