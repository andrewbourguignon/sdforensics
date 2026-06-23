import SwiftUI

struct MainView: View {
    @StateObject private var stateManager = AppStateManager()
    @State private var currentTab: SidebarTab = .dashboard
    
    enum SidebarTab {
        case dashboard
        case storage
        case speed
        case audit
        case format
        case simulator
    }
    
    var body: some View {
        NavigationView {
            // Sidebar Navigation
            List {
                Section(header: Text("SD Forensics").font(.headline).foregroundColor(.secondary)) {
                    Button(action: { currentTab = .dashboard }) {
                        Label("Dashboard", systemImage: "macmini")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .dashboard))
                    
                    Button(action: { currentTab = .storage }) {
                        Label("Storage Analysis", systemImage: "chart.pie.fill")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .storage))
                    
                    Button(action: { currentTab = .speed }) {
                        Label("Speed Benchmark", systemImage: "gauge")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .speed))
                    
                    Button(action: { currentTab = .audit }) {
                        Label("Forensic Audit", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .audit))
                    
                    Button(action: { currentTab = .format }) {
                        Label("Format & Mark", systemImage: "lock.shield")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .format))
                    
                    Button(action: { currentTab = .simulator }) {
                        Label("Simulator", systemImage: "cpu")
                    }
                    .buttonStyle(SidebarButtonStyle(isSelected: currentTab == .simulator))
                }
                
                Section(header: Text("Target Device").font(.caption).foregroundColor(.secondary)) {
                    if let selected = stateManager.selectedDisk {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.name)
                                .font(.subheadline)
                                .bold()
                            Text(selected.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if selected.isMock {
                                Text("MOCK DRIVE ACTIVE")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No disk selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
            
            // Detail / Tab Views
            Group {
                switch currentTab {
                case .dashboard:
                    DashboardView(stateManager: stateManager)
                case .storage:
                    StorageAnalysisView(stateManager: stateManager)
                case .speed:
                    SpeedBenchmarkView(stateManager: stateManager)
                case .audit:
                    AuditReportView(stateManager: stateManager)
                case .format:
                    FormatMarkView(stateManager: stateManager)
                case .simulator:
                    VirtualSimulatorView(stateManager: stateManager)
                }
            }
            .frame(minWidth: 600, idealWidth: 680)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 550)
        .preferredColorScheme(.dark)
    }
}

// Custom Premium Sidebar Style Button
struct SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
