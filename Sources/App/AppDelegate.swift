import Cocoa
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var dropView: StatusDropView!
    private let menuPanel = AirFliqMenuPanel()
    private var onboarding: OnboardingWindowController?
    private var lastOpenAt: Date = .distantPast
    private var sendSuccessObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open AirFliq.app` can immediately produce a reopen callback after
        // launch. Treat that as launch, not as a toolbar click to send files.
        lastOpenAt = Date()
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

        if !Permissions.hasRunSetup || !Shortcut.hasConfigured {
            showOnboarding()
        } else {
            // Permissions can be revoked later in System Settings. Re-check
            // without blocking launch and surface setup again if anything drifted.
            Task { [weak self] in
                async let automation = Task.detached(priority: .utility) {
                    Permissions.automationState()
                }.value
                async let menu = Task.detached(priority: .utility) {
                    Permissions.finderExtensionState()
                }.value
                let states = await [automation, Permissions.filesState(), menu]
                guard !states.allSatisfy({ $0 == .granted }) else { return }
                Permissions.hasRunSetup = false
                self?.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let sendSuccessObserver {
            NotificationCenter.default.removeObserver(sendSuccessObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Monetization.shared.refresh()
    }

    /// Files dropped on the Finder toolbar or Dock icon, or handed over by the
    /// Finder extension.
    func application(_ application: NSApplication, open urls: [URL]) {
        lastOpenAt = Date()
        AirDrop.send(urls)
    }

    /// Clicking the toolbar icon without dragging: fall back to the selection.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if Date().timeIntervalSince(lastOpenAt) > 0.5 {
            AirDrop.sendFinderSelection()
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
        let snapshot = AirFliqMenuPanel.Snapshot(
            isPro: revenue.isPro,
            trialStatus: revenue.trialStatusText,
            trialExpired: revenue.isTrialExpired,
            price: revenue.price,
            currentShortcut: Shortcut.current.name,
            dragEnabled: DragCatcher.shared.isEnabled,
            launchAtLogin: SMAppService.mainApp.status == .enabled
        )
        let actions = AirFliqMenuPanel.Actions(
            send: { [weak self] in self?.sendSelection() },
            unlock: { [weak self] in self?.showPaywall() },
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

    // MARK: - Actions

    @objc private func sendSelection() {
        AirDrop.sendFinderSelection()
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
