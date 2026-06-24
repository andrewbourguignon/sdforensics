import SwiftUI

struct SpeedBenchmarkView: View {
    @ObservedObject var stateManager: AppStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed Benchmark")
                        .font(.title)
                        .bold()
                    Text("Measure sequential and random block media transfer rates.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if !stateManager.isBenchmarking {
                    HStack(spacing: 8) {
                        Text("Test Size:")
                            .font(.subheadline)
                            .bold()
                        Picker("Test Size", selection: $stateManager.testSizeMB) {
                            Text("50 MB").tag(50)
                            Text("100 MB").tag(100)
                            Text("250 MB").tag(250)
                            Text("500 MB").tag(500)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 100)
                    }
                    .padding(.trailing, 10)
                    
                    Button(action: { runBenchmark() }) {
                        Label("Run Speed Test", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.macAccent)
                    .disabled(stateManager.selectedDisk == nil)
                }
            }
            
            if stateManager.selectedDisk == nil {
                VStack(spacing: 16) {
                    Image(systemName: "gauge.badge.minus")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No connected device selected.")
                        .font(.title3)
                        .bold()
                    Text("Please connect and select an SD card in the Dashboard.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(12)
            } else if stateManager.isBenchmarking {
                // Testing In-Progress state
                VStack(spacing: 24) {
                    ProgressView(value: stateManager.benchmarkProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 400)
                    
                    Text("Testing sequential read/write rates...")
                        .font(.headline)
                    
                    Text(String(format: "Progress: %.0f%%", stateManager.benchmarkProgress * 100))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Simple loading layout
                    HStack(spacing: 40) {
                        TestingGauge(title: "Read Speed")
                        TestingGauge(title: "Write Speed")
                    }
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.1))
                .cornerRadius(12)
            } else if let result = getResult() {
                // Results State
                ScrollView {
                    VStack(spacing: 24) {
                        // Summary Badge Card
                        HStack(spacing: 24) {
                            GradeBadge(grade: result.grade)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("MEDIA PERFORMANCE CLASS")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                Text(result.speedClass)
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.macAccent)
                                Text("Suitable for 4K video recording, burst photography, and high-speed data log ingest.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(20)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        
                        // Triple Gauges
                        HStack(spacing: 20) {
                            SpeedMetricGauge(
                                title: "Sequential Read",
                                speed: result.sequentialReadMBps,
                                maxSpeed: 120.0,
                                unit: "MB/s",
                                color: .blue
                            )
                            
                            SpeedMetricGauge(
                                title: "Sequential Write",
                                speed: result.sequentialWriteMBps,
                                maxSpeed: 120.0,
                                unit: "MB/s",
                                color: .green
                            )
                            
                            SpeedMetricGauge(
                                title: "Random Read 4K",
                                speed: result.randomRead4KMBps,
                                maxSpeed: 15.0,
                                unit: "MB/s",
                                color: .orange
                            )
                        }
                        
                        // Graphs Row
                        HStack(spacing: 20) {
                            // Read Throughput Chart
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sequential Read Throughput (MB/s)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                LineChart(samples: result.readSamples, color: .blue)
                                    .frame(height: 140)
                                    .padding(.top, 10)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                            .cornerRadius(12)
                            
                            // Write Throughput Chart
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sequential Write Throughput (MB/s)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                LineChart(samples: result.writeSamples, color: .green)
                                    .frame(height: 140)
                                    .padding(.top, 10)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                            .cornerRadius(12)
                        }
                    }
                }
            } else {
                // Initial State
                VStack(spacing: 20) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 64))
                        .foregroundColor(.macAccent)
                    Text("Ready to run benchmark.")
                        .font(.title3)
                        .bold()
                    Text("Click 'Run Speed Test' to perform active transfer test operations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    Button(action: { runBenchmark() }) {
                        Label("Run Speed Test", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                .cornerRadius(12)
            }
            
            // History Section (Visible when not actively benchmarking)
            if !stateManager.isBenchmarking && !stateManager.benchmarkHistory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Benchmark History Logs")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear History", action: { stateManager.clearBenchmarkHistory() })
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(stateManager.benchmarkHistory) { record in
                                HStack(spacing: 12) {
                                    Text(record.grade)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(gradeColor(for: record.grade))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.deviceName)
                                            .font(.subheadline)
                                            .bold()
                                        Text("\(record.speedClass) • Test Size: \(record.testSizeMB) MB")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Read: \(String(format: "%.1f", record.sequentialReadMBps)) MB/s")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.blue)
                                        Text("Write: \(String(format: "%.1f", record.sequentialWriteMBps)) MB/s")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.green)
                                    }
                                    
                                    Text(dateFormatter.string(from: record.date))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .padding(30)
    }
    
    // Helpers
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()
    
    private func gradeColor(for grade: String) -> Color {
        switch grade {
        case "A+", "A": return .green
        case "B": return .blue
        case "C": return .yellow
        case "D": return .orange
        default: return .red
        }
    }
    
    private func runBenchmark() {
        if stateManager.selectedDisk?.isMock == true {
            // Mock Benchmark loading flow
            stateManager.isBenchmarking = true
            stateManager.benchmarkProgress = 0.0
            
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
                stateManager.benchmarkProgress += 0.05
                if stateManager.benchmarkProgress >= 1.0 {
                    timer.invalidate()
                    stateManager.isBenchmarking = false
                    
                    let result = mockResult
                    stateManager.benchmarkResult = result
                    
                    // Create mock record
                    let record = BenchmarkRecord(
                        id: UUID(),
                        date: Date(),
                        deviceName: stateManager.selectedDisk?.name ?? "Mock Disk",
                        testSizeMB: stateManager.testSizeMB,
                        sequentialReadMBps: result.sequentialReadMBps,
                        sequentialWriteMBps: result.sequentialWriteMBps,
                        randomRead4KMBps: result.randomRead4KMBps,
                        speedClass: result.speedClass,
                        grade: result.grade,
                        readSamples: result.readSamples,
                        writeSamples: result.writeSamples
                    )
                    stateManager.benchmarkHistory.insert(record, at: 0)
                    stateManager.saveBenchmarkHistory()
                }
            }
        } else {
            stateManager.runBenchmark()
        }
    }
    
    private func getResult() -> BenchmarkResult? {
        if stateManager.selectedDisk?.isMock == true {
            return stateManager.benchmarkResult
        }
        return stateManager.benchmarkResult
    }
    
    private var mockResult: BenchmarkResult {
        BenchmarkResult(
            sequentialReadMBps: 94.2,
            sequentialWriteMBps: 35.8,
            randomRead4KMBps: 4.8,
            speedClass: "V30 / UHS-I U3",
            grade: "B",
            readSamples: [85.0, 92.1, 95.3, 91.8, 93.9, 94.8, 93.2, 94.2],
            writeSamples: [28.0, 32.1, 35.3, 31.8, 33.9, 34.8, 33.2, 35.8]
        )
    }
}

// Speed Metric Gauge Component
struct SpeedMetricGauge: View {
    let title: String
    let speed: Double
    let maxSpeed: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            let progress = min(1.0, max(0.0, speed / maxSpeed))
            
            ZStack {
                // Semi-circle gauge backing
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(135))
                
                // Color fill
                Circle()
                    .trim(from: 0.0, to: 0.75 * CGFloat(progress))
                    .stroke(
                        LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", speed))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .bold()
                }
            }
            .frame(width: 130, height: 130)
            .padding(.bottom, 10)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

// Testing gauge component
struct TestingGauge: View {
    let title: String
    
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.1), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                
                ProgressView()
            }
            .frame(width: 100, height: 100)
        }
    }
}

// Grade badge component
struct GradeBadge: View {
    let grade: String
    
    var body: some View {
        Text(grade)
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 80, height: 80)
            .background(
                LinearGradient(colors: [gradeColor, gradeColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
            .shadow(color: gradeColor.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    private var gradeColor: Color {
        switch grade {
        case "A+", "A": return .green
        case "B": return .blue
        case "C": return .yellow
        case "D": return .orange
        default: return .red
        }
    }
}

// Mini Line Chart Component
struct LineChart: View {
    let samples: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            if samples.isEmpty {
                Text("Collecting samples...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxVal = samples.max() ?? 1.0
                let minVal = 0.0
                let range = maxVal - minVal
                
                ZStack {
                    // Grid lines
                    VStack {
                        Divider()
                        Spacer()
                        Divider()
                        Spacer()
                        Divider()
                    }
                    
                    Path { path in
                        for idx in 0..<samples.count {
                            let x = CGFloat(idx) / CGFloat(samples.count - 1) * geo.size.width
                            let fraction = CGFloat((samples[idx] - minVal) / (range > 0 ? range : 1.0))
                            let y = geo.size.height - fraction * geo.size.height
                            
                            if idx == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}
