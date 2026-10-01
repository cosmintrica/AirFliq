import Cocoa
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var dropView: StatusDropView!
    private let menuPanel = AirFliqMenuPanel()
    private var onboarding: OnboardingWindowController?
    private var captureBubble: DropBubble?
    private var lastOpenAt: Date = .distantPast
    private var sendSuccessObserver: NSObjectProtocol?
    private let captureMode = ProcessInfo.processInfo.environment["AIRFLIQ_CAPTURE_MODE"]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open AirFliq.app` can immediately produce a reopen callback after
        // launch. Treat that as launch, not as a toolbar click to send files.
        lastOpenAt = Date()
#if DEBUG
        // Test builds only: `scripts/test-onboarding.sh` relaunches with this
        // flag so setup can be walked through from the very first screen.
        if ProcessInfo.processInfo.environment["AIRFLIQ_RESET_SETUP"] == "1" {
            for key in ["hasRunSetup", "shortcutConfigured.v2", "shortcutName",
                        "shortcutKeyCode.v2", "shortcutModifiers.v2",
                        "airfliq.onboarding.didRequestFinderExtension.v1",
                        "airfliq.onboarding.skippedSteps.v1",
                        "selectedFolderBookmarks", "dragToSendEnabled",
                        FreeSendAllowance.dayKey, FreeSendAllowance.countKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
#endif
        Monetization.shared.configure()
        setUpStatusItem()
        sendSuccessObserver = NotificationCenter.default.addObserver(
            forName: .airFliqSendSucceeded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dropView?.pulseSuccess()
            }
        }
        ShortcutManager.shared.start()
        DragCatcher.shared.restoreFromDefaults()

        if let captureMode {
            DispatchQueue.main.async { [weak self] in
                self?.presentCaptureMode(captureMode)
            }
            return
        }

        // Setup is shown until the user finishes it once. Optional routes the
        // user skipped (or cannot enable, for example on a managed Mac) never
        // bring the whole setup back; the menu offers them instead.
        if !Permissions.hasRunSetup || !Shortcut.hasConfigured {
            showOnboarding()
        }
        Permissions.refreshFinderExtensionCache()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let sendSuccessObserver {
            NotificationCenter.default.removeObserver(sendSuccessObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Monetization.shared.refresh()
        Permissions.refreshFinderExtensionCache()
    }

    /// Files dropped on the Finder toolbar or Dock icon, or handed over by the
    /// Finder extension.
    func application(_ application: NSApplication, open urls: [URL]) {
        lastOpenAt = Date()
        var files: [URL] = []
        for url in urls {
            if url.isFileURL {
                files.append(url)
            } else if let selection = FinderSendRequest.decode(url) {
                files.append(contentsOf: selection)
            } else {
                Toast.show("Could not read the Finder selection",
                           subtitle: "Select the files in Finder and try Send with AirFliq again.")
                return
            }
        }
        AirDrop.send(files)
    }

    /// Clicking the toolbar icon without dragging: fall back to the selection.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if captureMode == nil,
           !hasVisibleWindows,
           Date().timeIntervalSince(lastOpenAt) > 0.5 {
            AirDrop.chooseAndSend()
        }
        return false
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        guard let button = statusItem.button else { return }
        button.image = nil

        let view = StatusDropView(frame: button.bounds)
        view.autoresizingMask = [.width, .height]
        view.onDrop = { urls in AirDrop.send(urls) }
        view.onClick = { [weak self] anchor in self?.showMenu(from: anchor) }
        button.addSubview(view)
        dropView = view
    }

    private func showMenu(from anchor: NSView) {
        let revenue = Monetization.shared
        revenue.refreshFreeAllowance()
        let tone: AirFliqMenuPanel.StatusTone
        if revenue.isPro {
            tone = .pro
        } else if revenue.hasUnlimitedSending {
            tone = .trial
        } else {
            tone = revenue.freeSendsRemainingToday == 0 ? .exhausted : .free
        }
        let snapshot = AirFliqMenuPanel.Snapshot(
            isPro: revenue.isPro,
            accessStatus: revenue.accessStatusText,
            statusTone: tone,
            freeRemaining: revenue.freeSendsRemainingToday,
            price: revenue.price,
            currentShortcut: Shortcut.current.name,
            dragEnabled: DragCatcher.shared.isEnabled,
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            finderMenuOff: Permissions.cachedFinderExtensionEnabled == false
        )
        Permissions.refreshFinderExtensionCache()
        let actions = AirFliqMenuPanel.Actions(
            send: { [weak self] in self?.sendSelection() },
            unlock: { [weak self] in self?.showPaywall() },
            enableFinderMenu: { [weak self] in self?.showFinderMenuSetup() },
            configureShortcut: { [weak self] in self?.showShortcutSetup() },
            toggleDrag: { [weak self] in self?.toggleDragToSend() ?? DragCatcher.shared.isEnabled },
            toggleLogin: { [weak self] in
                self?.toggleLaunchAtLogin() ?? (SMAppService.mainApp.status == .enabled)
            },
            setup: { [weak self] in self?.showOnboarding() },
            about: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
        menuPanel.toggle(from: anchor, snapshot: snapshot, actions: actions)
    }

    private func presentCaptureMode(_ mode: String) {
        switch mode {
        case "shortcut":
            showShortcutSetup()
        case "menu":
            showMenu(from: dropView)
        case "paywall":
            showPaywall()
        case "paywall-limit":
            PaywallWindowController.shared.present(reason: .dailyLimitReached)
        case "finder-guide":
            showFinderMenuSetup()
        case "coach":
            FinderMenuCoach.shared.show(onSkip: {}, onReopen: {})
        case "about":
            showAbout()
        case "drag-launch":
            let bubble = DropBubble()
            captureBubble = bubble
            let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            bubble.showLaunchForCapture(near: NSPoint(x: frame.midX - 150, y: frame.midY))
        case "drag", "drag-complete":
            let bubble = DropBubble()
            captureBubble = bubble
            let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            bubble.showForCapture(
                near: NSPoint(x: frame.midX - 150, y: frame.midY),
                complete: mode == "drag-complete"
            )
        case "toast":
            Toast.show(
                "Drag target online",
                subtitle: "Pick up any file and AirFliq will meet your cursor."
            )
        default:
            showOnboarding()
        }
    }

    // MARK: - Actions

    @objc private func sendSelection() {
        AirDrop.chooseAndSend()
    }

    @discardableResult
    private func toggleDragToSend() -> Bool {
        let enabled = !DragCatcher.shared.isEnabled
        DragCatcher.shared.setEnabled(enabled)
        Toast.show(enabled ? "Drag to Send is on" : "Drag to Send is off",
                   subtitle: enabled ? "Start dragging a file to see the drop target." : nil)
        return enabled
    }

    @discardableResult
    private func toggleLaunchAtLogin() -> Bool {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Toast.show("Could not change that setting",
                       subtitle: error.localizedDescription,
                       kind: .warning)
        }
        return SMAppService.mainApp.status == .enabled
    }

    @objc private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController()
        }
        onboarding?.present()
    }

    private func showShortcutSetup() {
        if onboarding == nil {
            onboarding = OnboardingWindowController()
        }
        onboarding?.present(startAtShortcut: true)
    }

    private func showFinderMenuSetup() {
        if onboarding == nil {
            onboarding = OnboardingWindowController()
        }
        onboarding?.present(focusFinderMenu: true)
    }

    @objc private func showPaywall() {
        PaywallWindowController.shared.present()
    }

    private func showAbout() {
        AboutWindowController.shared.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}
