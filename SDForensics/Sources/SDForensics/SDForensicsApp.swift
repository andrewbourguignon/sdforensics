import Cocoa
import SwiftUI

@main
struct AppLauncher {
    static let delegate = AppDelegate() // Retain App Delegate strongly to prevent deallocation crash
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count > 1 {
            // Route to CLI parser
            runCLIMode(arguments: arguments)
        } else {
            // Self-escalate to root if not already privileged.
            // This fires osascript (native macOS password dialog) to relaunch
            // the same binary as root, then the non-root process exits immediately
            // BEFORE creating any GUI — so only one dock icon ever appears.
            if getuid() != 0 {
                let binaryPath = ProcessInfo.processInfo.arguments[0]
                let escaped = binaryPath.replacingOccurrences(of: "'", with: "'\\''")
                let script = "do shell script \"'" + escaped + "'\" with administrator privileges"
                
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                // Detach stdout/stderr so osascript doesn't inherit terminal noise
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                } catch {
                    // If escalation fails (user cancelled), just exit silently
                }
                exit(0)
            }
            
            // We are root — start the standard macOS AppKit GUI runtime
            let app = NSApplication.shared
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build view and host inside a standard AppKit window frame
        let contentView = MainView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.setFrameAutosaveName("SDForensicsMainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.title = "SD Forensics"
        
        // Bring window to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
