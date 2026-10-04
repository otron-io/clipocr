import AppKit
import ClipOCRCore
import CoreGraphics
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var captureItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var detailItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hotKey: GlobalHotKey?
    private var captureTask: Task<Void, Never>?
    private var quitting = false
    private var lastError: String?
    private var shortcutError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RequestWorkspace.cleanStaleRequests(olderThan: 0)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("text.viewfinder", description: "ClipOCR — Capture Text (⌘⇧6)")
        menu.delegate = self
        menu.autoenablesItems = false
        addItem("ClipOCR · On-device Apple Vision", action: nil).isEnabled = false
        statusLine = addItem("Ready · ⌘⇧6", action: nil)
        statusLine.isEnabled = false
        menu.addItem(.separator())
        captureItem = addItem("Capture Text", action: #selector(captureFromMenu))
        captureItem.keyEquivalent = "6"
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        detailItem = addItem("Show Last Error…", action: #selector(showError))
        detailItem.isHidden = true
        menu.addItem(.separator())
        addItem("Screen Recording Permission…", action: #selector(openPermissions))
        loginItem = addItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        addItem("About ClipOCR…", action: #selector(showAbout))
        menu.addItem(.separator())
        addItem("Quit ClipOCR", action: #selector(quit)).keyEquivalent = "q"
        statusItem.menu = menu
        do {
            hotKey = try GlobalHotKey { [weak self] in
                // Carbon dispatches application hotkey events on the main thread.
                MainActor.assumeIsolated { self?.scheduleCapture() }
            }
        } catch {
            shortcutError = error.localizedDescription
            fail(error.localizedDescription)
        }
        updateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }

    @discardableResult
    private func addItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func setIcon(_ symbol: String, description: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = description
    }

    private func updateMenu() {
        captureItem.isEnabled = captureTask == nil && !quitting
        detailItem.isHidden = lastError == nil
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func captureFromMenu() { scheduleCapture() }

    private func scheduleCapture() {
        guard captureTask == nil, !quitting else { return }
        menu.cancelTracking()
        // Let the status menu close before the screenshot selector appears.
        captureTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                guard let self else { return }
                await self.capture()
            } catch {}
            guard let self else { return }
            self.captureTask = nil
            self.updateMenu()
            if self.quitting { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        updateMenu()
    }

    private func capture() async {
        do {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                fail("Allow ClipOCR in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen ClipOCR. Your clipboard is unchanged.")
                return
            }
            let workspace = try RequestWorkspace()
            defer { workspace.cleanUp() }
            statusLine.title = "Select a region · Escape cancels"
            setIcon("viewfinder", description: "ClipOCR — Selecting…")
            let result = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/usr/sbin/screencapture"),
                arguments: ["-i", "-s", "-x", "-t", "png", workspace.image.path],
                directory: workspace.directory, timeout: 300
            )
            try Task.checkCancellation()
            if !FileManager.default.fileExists(atPath: workspace.image.path) && [0, 1].contains(result.status) {
                ready("Cancelled · Clipboard unchanged")
                return
            }
            guard result.status == 0 else {
                fail("Screenshot capture failed. Check Screen Recording permission and try again; your clipboard is unchanged.")
                return
            }
            statusLine.title = "Recognizing text locally…"
            setIcon("ellipsis.circle", description: "ClipOCR — Recognizing with Apple Vision…")
            let started = Date()
            let text = try await TextRecognizer().recognize(imageAt: workspace.image)
            try Task.checkCancellation()
            let pasteboard = NSPasteboard.general
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else {
                fail("Could not prepare clipboard text. Your clipboard is unchanged.")
                return
            }
            pasteboard.prepareForNewContents(with: [])
            guard pasteboard.writeObjects([item]) else {
                fail("macOS could not write to the clipboard. Please try again.")
                return
            }
            lastError = shortcutError
            statusLine.title = "Copied \(text.count) characters · \(String(format: "%.2f", Date().timeIntervalSince(started)))s"
            setIcon("checkmark.circle", description: "ClipOCR — Text copied. Paste with ⌘V.")
            NSSound(named: "Pop")?.play()
        } catch is CancellationError {
            ready("Cancelled · Clipboard unchanged")
        } catch {
            fail(error.localizedDescription)
        }
        updateMenu()
    }

    private func ready(_ title: String) {
        statusLine.title = title
        setIcon("text.viewfinder", description: "ClipOCR — Capture Text (⌘⇧6)")
    }

    private func fail(_ message: String) {
        lastError = message
        statusLine.title = "Error · See Show Last Error"
        setIcon("exclamationmark.circle", description: "ClipOCR — \(message)")
        updateMenu()
        NSSound(named: "Basso")?.play()
    }

    @objc private func showError() {
        present(title: "ClipOCR", message: lastError ?? "No errors.")
    }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            updateMenu()
        } catch { fail("Could not change Launch at Login: \(error.localizedDescription)") }
    }

    @objc private func showAbout() {
        present(title: "ClipOCR", message: "⌘⇧6 → select text → paste with ⌘V.\n\nText recognition runs entirely on your Mac using Apple Vision. No account, API key, subscription, Apple Intelligence, or internet connection is required. Nothing is uploaded. Temporary captures are deleted after each request.\n\nRequires Screen Recording permission, but not Accessibility permission. Escape cancels; recognition failures leave the clipboard unchanged. Line breaks are preserved where detected; indentation is approximate. Launch at Login is optional.")
    }

    private func present(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let captureTask else { return .terminateNow }
        quitting = true
        captureTask.cancel()
        return .terminateLater
    }
}
