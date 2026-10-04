import AppKit
import ClipOCRCore
import Foundation

// Test a supplied image without capturing the screen or touching the clipboard.
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--recognize-image" {
    let image = URL(fileURLWithPath: CommandLine.arguments[2])
    Task {
        do {
            let started = Date()
            let text = try await TextRecognizer().recognize(imageAt: image)
            let data = try JSONSerialization.data(withJSONObject: [
                "text": text, "seconds": Date().timeIntervalSince(started)
            ], options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
