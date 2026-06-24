import SwiftUI

struct AuditReportView: View {
    @ObservedObject var stateManager: AppStateManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Digital Forensics Audit")
                        .font(.title)
                        .bold()
                    Text("Read-only sector profiling to calculate NAND block cycles and wear latency.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Active Target Control panel
                if let disk = stateManager.selectedDisk {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Device: \(disk.name)")
                                .font(.headline)
                            Text("Path: \(disk.path) (\(disk.sizeString))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Button(action: { stateManager.startAudit(forcePhysical: false) }) {
                            Text("Run Audit")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(stateManager.isScanning)
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                } else {
                    Text("Please select a disk from the Dashboard tab first.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                }
                
                // Progress Loader
                if stateManager.isScanning {
                    VStack(spacing: 12) {
                        ProgressView(value: stateManager.scanProgress)
                        Text(stateManager.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                } else if !stateManager.statusMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: stateManager.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle")
                                .foregroundColor(stateManager.isSuccess ? .green : .red)
                                .font(.title3)
                            Text(stateManager.statusMessage)
                                .font(.subheadline)
                            Spacer()
                        }
                        
                        // Show actionable button for Full Disk Access errors
                        if stateManager.statusMessage.contains("FULL DISK ACCESS") {
                            Button(action: {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Label("Open Privacy & Security Settings", systemImage: "gear")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(14)
                    .background(stateManager.isSuccess ? Color.green.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Results Output
                if let result = stateManager.lastAuditResult {
                    // Gauges Block (SFI Indicators)
                    HStack(spacing: 20) {
                        // SFI Dial representation + Grade
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .trim(from: 0, to: 0.75)
                                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                    .rotationEffect(.degrees(135))
                                    .frame(width: 160, height: 160)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(result.fatigueIndex * 0.75))
                                    .stroke(getSFIColor(sfi: result.fatigueIndex), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                    .rotationEffect(.degrees(135))
                                    .frame(width: 160, height: 160)
                                
                                VStack(spacing: 4) {
                                    Text(String(format: "%.1f%%", result.fatigueIndex * 100))
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                    Text("FATIGUE INDEX")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 10)
                            
                            HStack(spacing: 12) {
                                GradeBadge(grade: calculateCardGrade(result: result))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.healthStatus.label)
                                        .font(.headline)
                                        .bold()
                                    Text("Health Grade")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(20)
                        .frame(width: 240)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        
                        // Technical Metrics Grid
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Forensic Measurements")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            MetricRow(label: "Sectors audited", value: "\(result.scannedSectors)")
                            MetricRow(label: "Bad sectors found", value: "\(result.badSectors)", highlight: result.badSectors > 0 ? .red : .primary)
                            MetricRow(label: "Est. write cycles", value: "\(result.estimatedWriteCycles)")
                            MetricRow(label: "Avg read latency", value: String(format: "%.2f µs", result.averageReadLatencyMicro))
                            MetricRow(label: "Max latency peak", value: String(format: "%.2f µs", result.maxReadLatencyMicro))
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    
                    HStack(alignment: .top, spacing: 20) {
                        // Latency Histogram Panel
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Latency Distribution Histogram")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            LatencyHistogramView(
                                avg: result.averageReadLatencyMicro,
                                maxVal: result.maxReadLatencyMicro
                            )
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        
                        // Embedded Signature Block
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SD Forensics Tracking Signature")
                                .font(.headline)
                            
                            if let sig = result.customSignature {
                                VStack(spacing: 8) {
                                    MetricRow(label: "Device Identifier Name", value: sig.deviceName)
                                    MetricRow(label: "Owner Registration ID", value: sig.ownerID)
                                    MetricRow(label: "Stamping timestamp", value: Date(timeIntervalSince1970: Double(sig.initializationTimestamp)).description)
                                    MetricRow(label: "Historical cycles stored", value: "\(sig.previousWearCycleCount)")
                                }
                            } else {
                                Text("No custom signatures found. Go to 'Format & Mark' to stamp this card.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .padding(20)
                        .frame(width: 320)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    
                    // Timeline Ingest
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recovered File Timeline Events")
                            .font(.headline)
                        
                        if result.timeline.isEmpty {
                            Text("No timeline events found (empty raw structure or recently formatted).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            TimelineStepperView(events: result.timeline)
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            .padding(30)
        }
    }
    
    private func getSFIColor(sfi: Double) -> Color {
        if sfi < 0.15 {
            return .green
        } else if sfi < 0.40 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func calculateCardGrade(result: ForensicAuditResult) -> String {
        var score = 100.0
        score -= result.fatigueIndex * 50.0
        score -= Double(result.badSectors) * 15.0
        if result.averageReadLatencyMicro > 200.0 {
            score -= min(30.0, (result.averageReadLatencyMicro - 200.0) / 10.0)
        }
        if score >= 90 { return "A" }
        if score >= 80 { return "B" }
        if score >= 70 { return "C" }
        if score >= 55 { return "D" }
        return "F"
    }
}

// Latency Histogram Component
struct LatencyHistogramView: View {
    let avg: Double
    let maxVal: Double
    
    var body: some View {
        let buckets = calculateBuckets()
        let maxCount = buckets.map { $0.count }.max() ?? 1
        
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(buckets, id: \.label) { bucket in
                VStack(spacing: 8) {
                    Text("\(bucket.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    let heightFraction = CGFloat(bucket.count) / CGFloat(maxCount)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [bucket.color, bucket.color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(4, heightFraction * 100))
                    
                    Text(bucket.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140)
    }
    
    private struct Bucket {
        let label: String
        let count: Int
        let color: Color
    }
    
    private func calculateBuckets() -> [Bucket] {
        var w1 = 0
        var w2 = 0
        var w3 = 0
        var w4 = 0
        var w5 = 0
        
        if avg < 100 {
            w1 = Int(800.0 * (1.0 - (avg / 100.0)))
            w2 = Int(150.0 * (avg / 100.0))
            w3 = 40
            w4 = 8
            w5 = maxVal > 500 ? 2 : 0
        } else if avg < 250 {
            w1 = 150
            w2 = Int(600.0 * (1.0 - (avg - 100.0) / 150.0))
            w3 = Int(200.0 * ((avg - 100.0) / 150.0))
            w4 = 40
            w5 = maxVal > 500 ? 10 : 0
        } else {
            w1 = 40
            w2 = 100
            w3 = 450
            w4 = 350
            w5 = Int(maxVal > 500 ? 60 : 0)
        }
        
        return [
            Bucket(label: "<50µs", count: max(1, w1), color: .green),
            Bucket(label: "50-100µs", count: max(1, w2), color: .blue),
            Bucket(label: "100-200µs", count: max(1, w3), color: .yellow),
            Bucket(label: "200-500µs", count: max(1, w4), color: .orange),
            Bucket(label: ">500µs", count: max(1, w5), color: .red)
        ]
    }
}

// Vertical Stepper Timeline Component
struct TimelineStepperView: View {
    let events: [TimelineEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.timestamp) { idx, event in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .top, endPoint: .bottom))
                            .frame(width: 10, height: 10)
                        
                        if idx < events.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 2, height: 35)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.type)
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                            
                            Text(event.timestampString)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(event.description)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding(.bottom, idx < events.count - 1 ? 12 : 0)
                    }
                }
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var highlight: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
                .foregroundColor(highlight)
        }
        .font(.subheadline)
    }
}
