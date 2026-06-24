import SwiftUI
import UniformTypeIdentifiers

struct FormatMarkView: View {
    @ObservedObject var stateManager: AppStateManager
    @State private var forcePhysical = false
    @State private var showWarningSheet = false
    
    // Custom Preset Creation State
    @State private var showCreateSheet = false
    @State private var newPresetName = ""
    @State private var newPresetFolders = ""
    @State private var newPresetIconPath: String? = nil
    
    // Custom Preset Rename State
    @State private var showRenameSheet = false
    @State private var renameName = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prepare & Personalize Card")
                        .font(.title)
                        .bold()
                    Text("Configure folder presets, custom image branding, and safety erase settings for your SD card.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let disk = stateManager.selectedDisk {
                    HStack(alignment: .top, spacing: 24) {
                        // Left: Form Inputs and Selection Controls
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Formatting & Setup Options")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            // Form Input Card
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Card Label Metadata")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Device Label:")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.subheadline)
                                        TextField("e.g. CAM_A_CARD_04", text: $stateManager.customName)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                    
                                    HStack {
                                        Text("Owner/Org ID:")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.subheadline)
                                        TextField("e.g. RED_TEAM_PROD", text: $stateManager.ownerID)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                    
                                    HStack {
                                        Text("Wear Offset:")
                                            .frame(width: 100, alignment: .leading)
                                            .font(.subheadline)
                                        TextField("Historical wear cycle offset", text: $stateManager.preloadedCycles)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(10)
                            
                            // Wipe level segmented picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Formatting Wipe Level")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                Picker("Wipe Level", selection: $stateManager.wipeLevel) {
                                    ForEach(WipeLevel.allCases) { level in
                                        Text(level.rawValue).tag(level)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            // Camera Directory Presets Picker & CRUD Actions
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Camera Directory Layout Preset")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 8) {
                                    Picker("Directory Preset", selection: $stateManager.selectedPreset) {
                                        ForEach(stateManager.cameraPresets) { preset in
                                            Text(preset.name).tag(preset)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: .infinity)
                                    
                                    // New Custom Preset
                                    Button(action: {
                                        newPresetName = ""
                                        newPresetFolders = ""
                                        newPresetIconPath = nil
                                        showCreateSheet = true
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.macAccent)
                                            .font(.title3)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help("Create Custom Preset")
                                    
                                    // Rename Custom Preset (only for non-built-in items)
                                    if isSelectedPresetCustom() {
                                        Button(action: {
                                            renameName = stateManager.selectedPreset.name
                                            showRenameSheet = true
                                        }) {
                                            Image(systemName: "pencil.circle.fill")
                                                .foregroundColor(.macAccent)
                                                .font(.title3)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Rename Selected Preset")
                                        
                                        // Delete Custom Preset
                                        Button(action: {
                                            stateManager.deleteCustomPreset(id: stateManager.selectedPreset.id)
                                        }) {
                                            Image(systemName: "trash.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.title3)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Delete Selected Preset")
                                    }
                                }
                                
                                // Show selected preset directory list summary
                                if !stateManager.selectedPreset.directories.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Folder list to provision:")
                                            .font(.caption2)
                                            .bold()
                                            .foregroundColor(.secondary)
                                        ForEach(stateManager.selectedPreset.directories, id: \.self) { folder in
                                            Text(" 📁 \(folder)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if let icon = stateManager.selectedPreset.iconPath {
                                            HStack(spacing: 4) {
                                                Image(systemName: "photo.fill")
                                                    .font(.system(size: 9))
                                                Text("Default Finder Icon: \(URL(fileURLWithPath: icon).lastPathComponent)")
                                                    .font(.system(size: 9))
                                            }
                                            .foregroundColor(.macAccent)
                                            .padding(.top, 2)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                                    .cornerRadius(6)
                                }
                            }
                            
                            // Custom Reference Image selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom Reference / Preset Image")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    if let imgPath = stateManager.customPresetImagePath {
                                        Image(systemName: "photo.fill")
                                            .foregroundColor(.macAccent)
                                        Text(URL(fileURLWithPath: imgPath).lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Button(action: { stateManager.customPresetImagePath = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    } else {
                                        Text("No image selected")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Button(action: {
                                            let panel = NSOpenPanel()
                                            panel.allowedContentTypes = [.image]
                                            panel.allowsMultipleSelection = false
                                            panel.canChooseDirectories = false
                                            panel.canChooseFiles = true
                                            panel.title = "Select Custom Preset Image"
                                            if panel.runModal() == .OK, let url = panel.url {
                                                stateManager.customPresetImagePath = url.path
                                            }
                                        }) {
                                            Text("Browse...")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                            }
                            
                            // Safety physical write override
                            if !disk.isMock {
                                Toggle("Enforce Physical Sector Writes (requires password)", isOn: $forcePhysical)
                                    .toggleStyle(.switch)
                                    .font(.subheadline)
                            }
                            
                            // Destructive Action Trigger
                            Button(action: {
                                if disk.isMock {
                                    stateManager.startFormatting(forcePhysical: false)
                                } else {
                                    showWarningSheet = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: "exclamationmark.shield.fill")
                                    Text(disk.isMock ? "Format & Mark Virtual Disk" : "Erase & Embed Custom Stamp")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.macAccent)
                            .disabled(stateManager.isFormatting)
                            
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Right: Interactive SD Card canvas + Progress Checklist
                        VStack(spacing: 24) {
                            Text("Live Stamping Canvas")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            SDCardCanvas(
                                cardLabel: stateManager.customName,
                                ownerID: stateManager.ownerID,
                                cycles: stateManager.preloadedCycles,
                                isFormatting: stateManager.isFormatting,
                                capacity: disk.sizeString
                            )
                            
                            // Step progress checklist
                            if stateManager.isFormatting || !stateManager.formatSteps.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Formatting Pipeline")
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(stateManager.formatSteps) { step in
                                        HStack(spacing: 12) {
                                            stepIcon(for: step.status)
                                            Text(step.name)
                                                .font(.subheadline)
                                                .foregroundColor(stepColor(for: step.status))
                                            Spacer()
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                        .frame(width: 280)
                    }
                } else {
                    Text("Select a target block device on the Dashboard tab.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(30)
                }
            }
            .padding(30)
        }
        .alert(isPresented: $showWarningSheet) {
            Alert(
                title: Text("WARNING: IRREVERSIBLE FORMATTING ACTION"),
                message: Text("Executing raw writes will permanently erase and overwrite all partition metadata tables at target '\(stateManager.selectedDisk?.path ?? "")'. Ensure you have backed up any critical video files before confirming."),
                primaryButton: .destructive(Text("Proceed with formatting")) {
                    stateManager.startFormatting(forcePhysical: forcePhysical)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
        // Sheet: Create Custom Preset
        .sheet(isPresented: $showCreateSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create Custom Camera Preset")
                    .font(.headline)
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Name:")
                            .frame(width: 80, alignment: .leading)
                        TextField("e.g. My Sony Setup", text: $newPresetName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Folders:")
                            .frame(width: 80, alignment: .leading)
                        TextField("e.g. DCIM/SHOT_A, DCIM/SHOT_B", text: $newPresetFolders)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Text("Enter relative folder paths separated by commas.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    HStack {
                        Text("Finder Icon:")
                            .frame(width: 80, alignment: .leading)
                        
                        HStack {
                            if let icon = newPresetIconPath {
                                Image(systemName: "photo.fill")
                                    .foregroundColor(.macAccent)
                                Text(URL(fileURLWithPath: icon).lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { newPresetIconPath = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                Text("Optional Preset Icon File")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    let panel = NSOpenPanel()
                                    panel.allowedContentTypes = [.image]
                                    panel.allowsMultipleSelection = false
                                    panel.canChooseDirectories = false
                                    panel.canChooseFiles = true
                                    panel.title = "Select Preset Icon File"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        newPresetIconPath = url.path
                                    }
                                }) {
                                    Text("Browse...")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showCreateSheet = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Create") {
                        let dirsList = newPresetFolders
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        stateManager.addCustomPreset(name: newPresetName, directories: dirsList, iconPath: newPresetIconPath)
                        showCreateSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.macAccent)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
        // Sheet: Rename Selected Preset
        .sheet(isPresented: $showRenameSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Preset")
                    .font(.headline)
                
                TextField("New Name", text: $renameName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showRenameSheet = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save") {
                        stateManager.renamePreset(id: stateManager.selectedPreset.id, newName: renameName)
                        showRenameSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.macAccent)
                    .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }
    
    // Helpers
    private func isSelectedPresetCustom() -> Bool {
        let selected = stateManager.selectedPreset
        return !CameraPreset.builtIns.contains(where: { $0.id == selected.id }) && selected.id != CameraPreset.none.id
    }
    
    // Status Icon Helper
    @ViewBuilder
    private func stepIcon(for status: FormatStep.StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 14, height: 14)
        case .active:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.macAccent)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        }
    }
    
    private func stepColor(for status: FormatStep.StepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .active: return .macAccent
        case .completed: return .primary
        case .failed: return .red
        }
    }
}

// Custom interactive SD Card canvas
struct SDCardCanvas: View {
    let cardLabel: String
    let ownerID: String
    let cycles: String
    let isFormatting: Bool
    let capacity: String
    
    var body: some View {
        ZStack {
            // Card Shape
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 200, height: 260)
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isFormatting ?
                            LinearGradient(colors: [.macAccent, .purple, .macAccent], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color.secondary.opacity(0.3), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: isFormatting ? 3 : 1
                        )
                )
                .animation(isFormatting ? Animation.linear(duration: 2.0).repeatForever(autoreverses: true) : .default, value: isFormatting)
            
            // Gold Pins at the top
            VStack {
                HStack(spacing: 8) {
                    ForEach(0..<9) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.7, blue: 0.2), Color(red: 0.95, green: 0.8, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 8, height: 35)
                    }
                }
                .padding(.top, 10)
                Spacer()
            }
            .frame(width: 200, height: 260)
            
            // Lock notch on left side
            HStack {
                VStack {
                    Spacer()
                        .frame(height: 50)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.yellow) // Lock slider in locked/unlocked position
                        .frame(width: 6, height: 16)
                    Spacer()
                }
                Spacer()
            }
            .frame(width: 206, height: 260)
            
            // Label Text Overlay
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                    .frame(height: 35)
                
                // SDXC & Speed markers
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SDXC")
                            .font(.system(.title3, design: .default))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("I  U3  V30  Class 10")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(capacity.isEmpty ? "256 GB" : capacity)
                        .font(.system(.title2, design: .rounded))
                        .bold()
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                
                // Write sticker area
                VStack(alignment: .leading, spacing: 6) {
                    Text("LABEL: \(cardLabel.isEmpty ? "CAM_A_CARD_01" : cardLabel)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                    
                    Text("OWNER: \(ownerID.isEmpty ? "STUDIO_PROD" : ownerID)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.8))
                    
                    Text("CYCLES: \(cycles.isEmpty ? "0" : cycles)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white)
                .cornerRadius(6)
                .padding(.horizontal, 12)
                
                Spacer()
                
                // Bottom Brand stamp
                Text("SD FORENSICS SECURE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)
            }
            .frame(width: 200, height: 260)
            
            // Sector writing visual effect
            if isFormatting {
                ZStack {
                    Color.black.opacity(0.55)
                        .cornerRadius(16)
                    
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("STAMPING MEDIA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(2)
                    }
                }
                .frame(width: 200, height: 260)
            }
        }
    }
}

