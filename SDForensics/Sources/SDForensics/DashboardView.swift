import SwiftUI

struct DashboardView: View {
    @ObservedObject var stateManager: AppStateManager
    
    // Grid configuration for bento cards
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SD Forensics Dashboard")
                        .font(.title)
                        .bold()
                    Text("Identify, monitor, and manage your connected media cards.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: { stateManager.refreshDisks() }) {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            
            // Device Selector Bar
            HStack(spacing: 16) {
                Image(systemName: "opticaldisc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                if stateManager.connectedDisks.isEmpty {
                    Text("No devices connected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Active Device", selection: $stateManager.selectedDisk) {
                        ForEach(stateManager.connectedDisks) { disk in
                            Text("\(disk.name) (\(disk.sizeString) - \(disk.path))")
                                .tag(disk as DiskInfo?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 350)
                }
                
                Spacer()
                
                if let disk = stateManager.selectedDisk {
                    HStack(spacing: 8) {
                        if disk.isMock {
                            Text("Virtual Device")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(6)
                        } else {
                            Text("Physical Card")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(10)
            
            if stateManager.connectedDisks.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No connected SD cards or external devices found.")
                        .font(.title3)
                        .bold()
                    Text("Connect a reader, or use the Simulator tab to run virtual audits.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(12)
            } else if let disk = stateManager.selectedDisk {
                // Determine active card identity
                let identity = getIdentity(for: disk)
                
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Bento Grid of Identity
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hardware Identity")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if let id = identity {
                            LazyVGrid(columns: columns, spacing: 16) {
                                BentoCard(title: "CARD MODEL", icon: "sdcard.fill", iconColor: .blue) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(id.cardType)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        Text("Product: \(id.productName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                BentoCard(title: "ORIGIN & AGE", icon: "calendar.badge.clock", iconColor: .purple) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(id.manufacturingDate)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Text("MFR ID: \(id.manufacturerID) | Rev: \(id.revision)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                BentoCard(title: "SERIAL NUMBER", icon: "number", iconColor: .orange) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(id.serialNumber)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        Text("Spec Version: \(id.specVersion)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                BentoCard(title: "INTERFACE SPEED", icon: "bolt.fill", iconColor: .yellow) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(id.readerLinkSpeed)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Text("Link Width: \(id.readerLinkWidth)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                BentoCard(title: "MOUNT POINT", icon: "folder.fill", iconColor: .green) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(id.volumeName.isEmpty ? "Untitled" : id.volumeName)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Text(id.mountPoint.isEmpty ? "Not mounted" : id.mountPoint)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                BentoCard(title: "HARDWARE HEALTH", icon: "heart.text.square.fill", iconColor: .red) {
                                    HStack(spacing: 8) {
                                        Image(systemName: id.smartStatus.contains("Verified") ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                            .foregroundColor(id.smartStatus.contains("Verified") ? .green : .orange)
                                            .font(.title2)
                                        VStack(alignment: .leading) {
                                            Text(id.smartStatus)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(id.smartStatus.contains("Verified") ? .green : .orange)
                                            Text("S.M.A.R.T. Status")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 16) {
                                ProgressView()
                                Text("Loading Card Hardware Details...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                            .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Right Column: Storage Ring & Quick Tools
                    VStack(alignment: .center, spacing: 24) {
                        Text("Storage Overview")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if let id = identity {
                            let capacity = id.capacityBytes
                            let free = id.freeSpaceBytes
                            let used = capacity > free ? capacity - free : 0
                            let usedFraction = capacity > 0 ? Double(used) / Double(capacity) : 0.0
                            let usedPercentage = Int(usedFraction * 100)
                            
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 16)
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(usedFraction))
                                    .stroke(
                                        LinearGradient(colors: [.accentColor, .blue], startPoint: .top, endPoint: .bottom),
                                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                
                                VStack(spacing: 4) {
                                    Text("\(usedPercentage)%")
                                        .font(.system(size: 32, weight: .bold))
                                    Text("Used")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 150, height: 150)
                            .padding(.vertical, 10)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                StorageRow(label: "Total Capacity", value: id.capacity, color: .secondary)
                                StorageRow(label: "Used Space", value: formatBytes(used), color: .accentColor)
                                StorageRow(label: "Free Space", value: id.freeSpace, color: .green)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                            .cornerRadius(10)
                            
                        } else {
                            ProgressView()
                                .frame(height: 250)
                        }
                        
                        Spacer()
                        
                        // Safe Eject Button
                        VStack(spacing: 8) {
                            Button(action: { stateManager.ejectDisk() }) {
                                HStack {
                                    Image(systemName: "eject.fill")
                                    Text("Safely Eject Card")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(disk.isMock)
                            
                            if !stateManager.ejectMessage.isEmpty {
                                Text(stateManager.ejectMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)
                    }
                    .frame(width: 250)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .padding(30)
    }
    
    // Helpers
    private func getIdentity(for disk: DiskInfo) -> CardIdentity? {
        if disk.isMock {
            return CardIdentity(
                cardType: "Virtual SDXC Simulator Card",
                productName: "MOCK-SD-256",
                manufacturerID: "0x99",
                serialNumber: "0xM0CK1234",
                manufacturingDate: "2026-01",
                specVersion: "4.0",
                revision: "1.0",
                capacity: "256.0 GB",
                capacityBytes: 256 * 1024 * 1024 * 1024,
                smartStatus: "Verified (Simulated)",
                partitionMap: "GPT",
                filesystem: "ExFAT",
                volumeName: "MOCK_CARD",
                mountPoint: "/Volumes/MOCK_CARD",
                freeSpace: "240.0 GB",
                freeSpaceBytes: 240 * 1024 * 1024 * 1024,
                usedSpaceBytes: 16 * 1024 * 1024 * 1024,
                readerLinkSpeed: "10.0 GT/s",
                readerLinkWidth: "x2",
                bsdName: "diskX",
                isRemovable: true
            )
        }
        return stateManager.cardIdentity
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// Bento card item component
struct BentoCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(title: String, icon: String, iconColor: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.subheadline)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// Storage detail row component
struct StorageRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
    }
}
