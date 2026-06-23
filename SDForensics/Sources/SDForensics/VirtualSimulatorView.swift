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
                    .tint(.orange)
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
            // Write 10MB zero file
            let sizeBytes = 10 * 1024 * 1024
            let zeroData = Data(repeating: 0, count: sizeBytes)
            
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
