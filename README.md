# SDForensics 🔍

SDForensics is a high-fidelity diagnostic, benchmarking, and forensic utility for SD cards and external media drives on macOS. Built with Swift and SwiftUI, it features a native, premium dashboard designed for filmmakers, drone operators, and hardware engineers.

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2012.0+-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.5+-orange.svg)

---

## 🛠️ Key Features

1. **Bento Card Identity Grid (Dashboard)**
   - Surfaces deep hardware registers via macOS system controllers: **SD Spec Version**, **Product Name**, **Manufacturer ID**, **Serial Number**, **Manufacturing Date**, **S.M.A.R.T. Health Status**, and **Reader Link Speed & Width**.
   - Displays real-time storage breakdowns (Total/Used/Free) with a modern donut chart.

2. **Storage Structure Analysis**
   - Automatically detects professional camera conventions (e.g. **Sony XAVC-S (M4ROOT)**, **Canon EOS (DCIM)**, **RED Digital Cinema**).
   - Dynamic bar chart showing file type distribution by size.
   - Fully searchable and sortable media clip explorer table exposing frame sizes, creation dates, codecs, audio channels, and duration.
   - Highlights top 10 largest files on the card for quick cleanups.

3. **Performance Speed Benchmarks**
   - Performs timed, cache-bypassed (`F_NOCACHE`) sequential and random transfers for raw speed measurements.
   - Circular speed dials + performance grade classification (e.g. `A+`, `A`, `B`, `C`).
   - Real-time line graph plotting transfer rates over time using native SwiftUI paths.

4. **Forensic Wear & Fatigue Audit**
   - Read-only sector sweeps estimating NAND wear cycles and block integrity.
   - Dynamic latency distribution histogram (`<50µs` to `>500µs`) checking media cell health.
   - Interactive vertical stepper tracing recovered partition events.

5. **Metadata Stamping & Formatting**
   - Live SD card interactive canvas updating label, owner ID, and wear offsets.
   - Segmented wipe control: `Quick Wipe` (GPT map only), `Secure Zero-Fill` (zeroes primary sectors), and `Forensic Overwrite` (fills headers with secure random entropy).
   - Pre-creates camera directory trees (Sony, Canon, RED, generic DCIM) automatically.

6. **Virtual Card Simulator**
   - Safe virtual sandboxing environment allowing developers/users to build, mount, and test formatting and sweeps using local image files.

---

## 🚀 Building & Running

### Prerequisites
- macOS 12.0 or newer
- Xcode Command Line Tools (`xcode-select --install`) or Xcode 13.0+

### Compiling and Bundling
SDForensics provides a bundling script (`bundle_app.sh`) that compiles the code and generates a standard macOS `.app` bundle:

1. Clone this repository.
2. Open terminal and navigate to the project directory.
3. Make the script executable:
   ```bash
   chmod +x bundle_app.sh
   ```
4. Run the script:
   ```bash
   ./bundle_app.sh
   ```
5. The completed app bundle **`SDForensics.app`** will be generated in the root of the workspace.

---

## 🔒 Security & Privileges

* **Filesystem Operations**: Reading card identities, storage details, speed benchmarks, and creating directory structures run with standard user privileges (no Full Disk Access required).
* **Forensic Block Auditing**: Interfacing with physical block devices (e.g. `/dev/diskX` / `/dev/rdiskX`) requires **elevated permissions**. The app handles this automatically by requesting native macOS administrator authentication on launch if run outside the command line.
* **Full Disk Access**: Due to macOS Tahoe security policy, raw device reads require **Full Disk Access (FDA)** authorization. If an EPERM error is hit, the application displays a direct settings link to grant authorization.

---

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
