import AppKit

// The harness compiles production Permissions/FolderAccessRequest directly.
// Its own bundle ID and fixtures keep it separate from the user's AirFliq data.
@MainActor enum Toast {
    static func show(_ title: String, subtitle: String) { NSLog("QA: %@ — %@", title, subtitle) }
}

@MainActor final class FolderAccessSandboxDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var label: NSTextField!
    private var callbacks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 180),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AirFliq Folder Access Verification"
        label = NSTextField(wrappingLabelWithString: "Checking real sandbox folder access…")
        label.frame = NSRect(x: 24, y: 30, width: 532, height: 120)
        window.contentView?.addSubview(label)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let base = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "QAFixtures") as! String)
        let files = [base.appendingPathComponent("Alpha/first.txt"), base.appendingPathComponent("Beta/second.txt")]
        let cancelledFile = base.appendingPathComponent("Gamma/cancel.txt")
        if UserDefaults.standard.bool(forKey: "qa.accessPassed") {
            Permissions.requestAccess(to: files, attachedTo: window) { [self] granted in
                let readable = files.allSatisfy { (try? String(contentsOf: $0, encoding: .utf8)) != nil }
                label.stringValue = granted && readable
                    ? "PASS: saved folder access restored after restart. Both files readable without another permission dialog."
                    : "FAIL: access was not restored after restart."
            }
            return
        }
        guard files.allSatisfy({ !FileManager.default.isReadableFile(atPath: $0.path) }) else {
            label.stringValue = "FAIL: fixture files were already readable before authorization."
            return
        }
        label.stringValue = "Confirmed: both fixture folders are blocked by the sandbox. Waiting for explicit authorization."
        Permissions.requestAccess(to: files, attachedTo: window) { [self] granted in
            callbacks += 1
            guard granted, files.allSatisfy({ (try? String(contentsOf: $0, encoding: .utf8)) != nil }) else {
                label.stringValue = "FAIL: first request did not resume with access to both files."
                return
            }
            label.stringValue = "Both folders authorized. Checking queued request, then cancellation."
        }
        Permissions.requestAccess(to: files, attachedTo: window) { [self] granted in
            callbacks += 1
            guard granted, callbacks == 2, Permissions.selectedFolderCount == 2 else {
                label.stringValue = "FAIL: queued request or bookmark preservation."
                return
            }
            Permissions.requestAccess(to: [cancelledFile], attachedTo: window) { [self] allowed in
                guard !allowed, Permissions.selectedFolderCount == 2 else {
                    label.stringValue = "FAIL: cancellation changed saved folder access."
                    return
                }
                UserDefaults.standard.set(true, forKey: "qa.accessPassed")
                label.stringValue = "PASS: two folders authorized and saved; both pending sends resumed once; queued request reused access; cancellation preserved existing folders. Restart this test to verify persistence."
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FolderAccessSandboxApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FolderAccessSandboxDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
