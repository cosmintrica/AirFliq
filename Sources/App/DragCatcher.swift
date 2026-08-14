import AppKit

/// Watches for a file drag anywhere on the system and offers a drop target.
///
/// Only mouse events are observed. Global *keyboard* monitoring is what requires
/// the Accessibility permission - mouse monitoring does not, so this costs the
/// user nothing to turn on.
final class DragCatcher {

    static let shared = DragCatcher()

    private static let defaultsKey = "dragToSendEnabled"

    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor: Any?

    private let bubble = DropBubble()
    private var pasteboardBaseline = 0
    private var isDragSession = false
    private var safetyTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?

    private(set) var isEnabled = false

    private init() {
        bubble.onDrop = { urls in AirDrop.send(urls) }
        bubble.onDropCompleted = { [weak self] in self?.endSession(force: true) }
    }

    // MARK: - Lifecycle

    func restoreFromDefaults() {
        setEnabled(UserDefaults.standard.bool(forKey: DragCatcher.defaultsKey))
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DragCatcher.defaultsKey)
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    private func start() {
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            // Snapshot before the drag begins: the drag pasteboard still holds
            // whatever the *previous* drag put there, so its contents alone
            // cannot tell us a new file drag has started.
            self?.pasteboardBaseline = NSPasteboard(name: .drag).changeCount
        }

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag()
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.endSession()
        }
    }

    private func stop() {
        for monitor in [downMonitor, dragMonitor, upMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        downMonitor = nil
        dragMonitor = nil
        upMonitor = nil
        endSession(force: true)
    }

    // MARK: - Drag handling

    private func handleDrag() {
        guard !isDragSession else { return }

        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != pasteboardBaseline else { return }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: options) else { return }

        hideWorkItem?.cancel()
        hideWorkItem = nil
        isDragSession = true
        bubble.show(near: NSEvent.mouseLocation)

        // If a mouse-up is ever missed - spaces switch, app crash mid-drag - the
        // bubble should not be left stranded on screen.
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.endSession(force: true) }
        }
    }

    private func endSession(force: Bool = false) {
        guard force || !bubble.isCelebrating else { return }
        safetyTimer?.invalidate()
        safetyTimer = nil
        guard isDragSession else { return }
        isDragSession = false
        // A beat of slack so a drop landing on the bubble is processed first.
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.bubble.hide()
            self?.hideWorkItem = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
