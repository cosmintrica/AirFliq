import AppKit
import SwiftUI

// MARK: - Window

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let model = OnboardingExperienceModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 570),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AirFliq Setup"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()

        self.init(window: window)
        window.delegate = self
        model.window = window
        model.onFinish = { [weak self] in self?.finish() }

        let host = NSHostingView(rootView: OnboardingExperience(model: model))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func present(startAtShortcut: Bool = false, focusFinderMenu: Bool = false) {
        guard let window else { return }
        let wasVisible = window.isVisible
        if !wasVisible { window.alphaValue = 0 }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        if !wasVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        model.present(forceShortcutStage: startAtShortcut, focusFinderMenu: focusFinderMenu)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.42
            context.timingFunction = Motion.easeOut
            window.animator().alphaValue = 1
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }

    private func finish() {
        Permissions.hasRunSetup = true
        model.stop()
        guard let window, !Motion.reduceMotion else {
            close()
            return
        }
        // Lift and fade out instead of vanishing: the setup hands off to the
        // menu bar, where AirFliq now lives.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = Motion.easeInOut
            window.animator().alphaValue = 0
            window.animator().setFrameOrigin(NSPoint(x: window.frame.origin.x,
                                                     y: window.frame.origin.y + 14))
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.close()
                window.alphaValue = 1
            }
        })
    }
}

// MARK: - State

@MainActor
final class OnboardingExperienceModel: ObservableObject {

    enum HelpMode: Equatable {
        case finderAccess
        case folderAccess
        case enableExtension
        case menuMissing
    }

    struct Step: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let detail: String
        let action: String
        let symbol: String
        let accent: Color
        /// Optional routes can be skipped; setup finishes without them.
        let skipTitle: String?
    }

    private static var selectionStep: Step {
#if MAC_APP_STORE
        Step(id: 0,
             eyebrow: "FILE SELECTION",
             title: "Choose. AirFliq follows.",
             detail: "Your shortcut opens a file picker. For a Finder selection, use right-click or drag-and-drop.",
             action: "Continue",
             symbol: "cursorarrow.rays",
             accent: Color(red: 0.16, green: 0.72, blue: 1.0),
             skipTitle: nil)
#else
        Step(id: 0,
             eyebrow: "FINDER SELECTION",
             title: "Point. AirFliq sees it.",
             detail: "Allow read-only access to the files currently selected in Finder.",
             action: "Allow Finder Access",
             symbol: "cursorarrow.rays",
             accent: Color(red: 0.16, green: 0.72, blue: 1.0),
             skipTitle: nil)
#endif
    }

    let steps = [
        OnboardingExperienceModel.selectionStep,
        Step(id: 1,
             eyebrow: "YOUR FOLDERS  •  OPTIONAL",
             title: "You choose the boundaries.",
             detail: "Pick the folders AirFliq may use now, or let it ask the first time a file needs access.",
             action: "Choose Folders",
             symbol: "folder.fill",
             accent: Color(red: 0.42, green: 0.48, blue: 1.0),
             skipTitle: "Ask me when a file needs it"),
        Step(id: 2,
             eyebrow: "RIGHT-CLICK  •  OPTIONAL",
             title: "Send from where you already are.",
             detail: "Place Send with AirFliq directly inside Finder's contextual menu. It takes one switch in System Settings.",
             action: "Enable Finder Menu",
             symbol: "filemenu.and.selection",
             accent: Color(red: 0.68, green: 0.35, blue: 1.0),
             skipTitle: "Skip for now"),
    ]

    @Published private(set) var states: [PermissionState] = [.unknown, .unknown, .unknown]
    @Published private(set) var skippedSteps: Set<Int> = OnboardingExperienceModel.loadSkippedSteps()
    @Published private(set) var isWorking = false
    @Published private(set) var presentationCycle = 0
    @Published private(set) var showReadyStage = false
    @Published private(set) var showShortcutStage = false
    @Published private(set) var showsFinderMenuGuide = false
    @Published private(set) var isWatchingFinderMenu = false
    @Published private(set) var celebratingIndex: Int?
    @Published private(set) var shortcutConfigured = Shortcut.hasConfigured
    @Published private(set) var isShortcutCompleting = false
    @Published var helpMode: HelpMode?
    @Published var activeIndex = 0
    @Published var dragEnabled = false
    @Published private(set) var currentShortcut = Shortcut.current

    weak var window: NSWindow?
    var onFinish: (() -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var helpWatchTask: Task<Void, Never>?
    private var settingsCloseObserver: NSObjectProtocol?
    private var isRefreshing = false
    private var hasLoadedInitialState = false
    private var forceShortcutStage = false
    private var forceFinderMenuFocus = false

    private static let skippedStepsKey = "airfliq.onboarding.skippedSteps.v1"

    var completedCount: Int { states.filter { $0 == .granted }.count }
    /// Skipping an optional step completes it: folders are then requested on
    /// demand, and the Finder menu can be switched on later from the menu.
    var completedStepCount: Int {
        steps.indices.filter(isResolved).count + (shortcutConfigured ? 1 : 0)
    }
    /// Every setup step is either connected or deliberately skipped.
    var isComplete: Bool { steps.indices.allSatisfy(isResolved) }
    /// Setup is finished: every step resolved and a shortcut chosen.
    var isFullyConnected: Bool { isComplete && shortcutConfigured }
    var activeStep: Step { steps[activeIndex] }
    var activeState: PermissionState { states[activeIndex] }
    var firstUnresolvedIndex: Int? { steps.indices.first { !isResolved($0) } }

    func isResolved(_ index: Int) -> Bool {
        states[index] == .granted || skippedSteps.contains(index)
    }

    func isSkipped(_ index: Int) -> Bool {
        states[index] != .granted && skippedSteps.contains(index)
    }

    func present(forceShortcutStage: Bool = false, focusFinderMenu: Bool = false) {
        presentationCycle += 1
        helpMode = nil
        showReadyStage = false
        showShortcutStage = false
        showsFinderMenuGuide = false
        celebratingIndex = nil
        dragEnabled = DragCatcher.shared.isEnabled
        currentShortcut = Shortcut.current
        shortcutConfigured = Shortcut.hasConfigured
        isShortcutCompleting = false
        self.forceShortcutStage = forceShortcutStage
        forceFinderMenuFocus = focusFinderMenu
        if focusFinderMenu { unskip(2) }
        hasLoadedInitialState = false
        refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Permissions.prewarmFolderPicker()
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        advanceTask?.cancel()
        advanceTask = nil
        stopWatchingFinderMenu()
        stopWatchingSettingsClose()
        FinderMenuCoach.shared.dismiss()
    }

    func selectStep(_ index: Int) {
        guard steps.indices.contains(index), !isWorking else { return }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
            showReadyStage = false
            showShortcutStage = false
            showsFinderMenuGuide = false
            activeIndex = index
        }
    }

    func openShortcutSetup() {
        guard !isWorking, !isShortcutCompleting else { return }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
            showReadyStage = false
            showsFinderMenuGuide = false
            showShortcutStage = true
        }
    }

    @discardableResult
    func chooseShortcut(_ shortcut: Shortcut) -> Bool {
        guard ShortcutManager.shared.apply(shortcut, announcesResult: false) else { return false }
        // ShortcutConstellation owns the full card-to-card transition. Keeping
        // this model mutation transaction-free prevents the whole onboarding
        // tree from inheriting a second, competing spring.
        currentShortcut = shortcut
        return true
    }

    func completeShortcutSetup() {
        guard !isShortcutCompleting else { return }
        Shortcut.hasConfigured = true
        shortcutConfigured = true
        forceShortcutStage = false
        isShortcutCompleting = true
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.78, dampingFraction: 0.84)) {
                isShortcutCompleting = false
                showShortcutStage = false
                if isComplete {
                    showReadyStage = true
                    Permissions.hasRunSetup = true
                } else {
                    activeIndex = firstUnresolvedIndex ?? 0
                }
            }
        }
    }

    func toggleDrag() {
        dragEnabled.toggle()
        DragCatcher.shared.setEnabled(dragEnabled)
        Toast.show(dragEnabled ? "Drag target online" : "Drag target paused",
                   subtitle: dragEnabled
                       ? "Pick up any file and AirFliq will meet your cursor."
                       : "Shortcut, menubar and right-click still work.")
    }

    func performActiveAction() {
        guard !isWorking else { return }
        switch activeIndex {
        case 0: requestFinderAccess()
        case 1: requestFolderAccess()
        default: requestFinderMenu()
        }
    }

    /// Skips an optional route. Setup can finish without it and the menu
    /// offers it again later; the whole setup never returns because of it.
    func skipActiveStep() {
        skipStep(activeIndex)
    }

    func skipStep(_ index: Int) {
        guard steps.indices.contains(index), steps[index].skipTitle != nil,
              states[index] != .granted, !isWorking else { return }
        if index == 2 {
            stopWatchingFinderMenu()
            FinderMenuCoach.shared.dismiss()
        }
        skippedSteps.insert(index)
        persistSkippedSteps()
        withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
            showsFinderMenuGuide = false
            celebratingIndex = nil
        }
        advanceToNextStep()
    }

    func troubleshoot() {
        guard !isWorking else { return }
        let mode: HelpMode
        if states[0] != .granted {
            mode = .finderAccess
        } else if states[1] != .granted && !skippedSteps.contains(1) {
            mode = .folderAccess
        } else if states[2] != .granted {
            mode = .enableExtension
        } else {
            mode = .menuMissing
        }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
            helpMode = mode
        }
    }

    func closeHelp() {
        withAnimation(.easeInOut(duration: 0.26)) { helpMode = nil }
    }

    func performHelpAction() {
        guard let helpMode else { return }
        switch helpMode {
        case .finderAccess:
#if MAC_APP_STORE
            closeHelp()
            advanceToNextStep()
#else
            Permissions.openAutomationSettings()
            startWatching(for: .finderAccess)
#endif
        case .folderAccess:
            closeHelp()
            DispatchQueue.main.async { [weak self] in
                self?.requestFolderAccess()
            }
        case .enableExtension:
            closeHelp()
            showFinderMenuGuide()
        case .menuMissing:
#if MAC_APP_STORE
            closeHelp()
#else
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Finder"]
            try? process.run()
            closeHelp()
            Toast.show("Finder restarted",
                       subtitle: "Right-click a file to check the AirFliq menu.",
                       kind: .success)
#endif
        }
    }

    func finish() {
        guard isComplete else { return }
        Permissions.hasRunSetup = true
        onFinish?()
    }

    /// Ends setup and opens the offer, for people who want unlimited sending
    /// straight away. The trial still starts only after App Store confirmation.
    func finishAndShowPro() {
        finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PaywallWindowController.shared.present()
        }
    }

    // MARK: Finder menu guide

    /// Shows how to switch on the extension before anything opens. Opening
    /// System Settings is a separate, deliberate click.
    func showFinderMenuGuide() {
        guard !isWorking else { return }
        Permissions.hasRequestedFinderExtension = true
        unskip(2)
        withAnimation(.spring(response: 0.66, dampingFraction: 0.86)) {
            showReadyStage = false
            showShortcutStage = false
            activeIndex = 2
            showsFinderMenuGuide = true
        }
    }

    func closeFinderMenuGuide() {
        stopWatchingFinderMenu()
        FinderMenuCoach.shared.dismiss()
        withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
            showsFinderMenuGuide = false
        }
    }

    func openFinderMenuSettings() {
        Permissions.hasRequestedFinderExtension = true
        isWatchingFinderMenu = true
        watchSettingsClose()
        Permissions.openExtensionSettings()
        FinderMenuCoach.shared.show(
            onSkip: { [weak self] in self?.skipStep(2) },
            onReopen: { Permissions.openExtensionSettings() }
        )
        startWatching(for: .enableExtension)
    }

    private func stopWatchingFinderMenu() {
        helpWatchTask?.cancel()
        helpWatchTask = nil
        isWatchingFinderMenu = false
    }

    private func unskip(_ index: Int) {
        guard skippedSteps.contains(index) else { return }
        skippedSteps.remove(index)
        persistSkippedSteps()
    }

    private static func loadSkippedSteps() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: skippedStepsKey) as? [Int] ?? [])
    }

    private func persistSkippedSteps() {
        UserDefaults.standard.set(skippedSteps.sorted(), forKey: Self.skippedStepsKey)
    }

    // MARK: State

    private func refresh() {
        guard !isWorking, !isRefreshing, window?.isVisible == true else { return }
        isRefreshing = true
        let folders = Permissions.filesState()

        Task { [weak self] in
            async let automation = Task.detached(priority: .utility) {
                Permissions.selectionSetupState()
            }.value
            async let menu = Task.detached(priority: .utility) {
                Permissions.finderExtensionState()
            }.value
            let values = await [automation, folders, menu]
            guard let self else { return }
            isRefreshing = false
            apply(values)
        }
    }

    func apply(_ liveStates: [PermissionState], celebrate requestedStep: Int? = nil) {
        var displayed = liveStates
#if !MAC_APP_STORE
        if !Permissions.hasRequestedAutomation { displayed[0] = .unknown }
#endif
        if !Permissions.hasRequestedFinderExtension && displayed[2] != .granted {
            displayed[2] = .unknown
        }

        // A route connected later always wins over an earlier skip.
        let grantedSkips = skippedSteps.filter { displayed[$0] == .granted }
        if !grantedSkips.isEmpty {
            skippedSteps.subtract(grantedSkips)
            persistSkippedSteps()
        }

        if !hasLoadedInitialState {
            states = displayed
            activeIndex = firstUnresolvedIndex ?? 0
            let everyStepResolved = isComplete
            showShortcutStage = forceShortcutStage || (everyStepResolved && !Shortcut.hasConfigured)
            showReadyStage = everyStepResolved && !showShortcutStage
            if forceFinderMenuFocus {
                forceFinderMenuFocus = false
                showShortcutStage = false
                showReadyStage = false
                activeIndex = 2
                showsFinderMenuGuide = displayed[2] != .granted
            }
            hasLoadedInitialState = true
            if everyStepResolved && Shortcut.hasConfigured { Permissions.hasRunSetup = true }
            return
        }

        let previous = states
        let changedSteps = displayed.indices.filter {
            previous[$0] != .granted && displayed[$0] == .granted
        }
        // A permission callback and the two-second live refresh can resolve in
        // either order. Only the first real state transition owns the success
        // sequence; a later callback must never replay it merely because it
        // names the requested step again.
        let completed = requestedStep.flatMap { changedSteps.contains($0) ? $0 : nil }
            ?? changedSteps.first
        if let completed {
            activeIndex = completed
            // Publish the celebration before publishing the granted state.
            // Otherwise SwiftUI can render one transient frame as an already
            // completed check, then replace it with the beginning of the real
            // animation. That flash looks exactly like a duplicated sequence.
            celebratingIndex = completed
            if completed == 2 { showsFinderMenuGuide = false }
        }

        states = displayed
        if isComplete && shortcutConfigured { Permissions.hasRunSetup = true }
        if !isComplete { showReadyStage = false }

        let resolvedStep = completed ?? requestedStep
        if (resolvedStep == 0 && displayed[0] == .granted && helpMode == .finderAccess)
            || (resolvedStep == 2 && displayed[2] == .granted && helpMode == .enableExtension) {
            closeHelp()
        }

        guard completed != nil else {
            // Confirming an already-authorized folder is still a completed
            // action. A background refresh is not: it must preserve navigation.
            if let requestedStep, displayed[requestedStep] == .granted,
               celebratingIndex == nil {
                advanceToNextStep()
            }
            return
        }

        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_050_000_000)
            guard let self, !Task.isCancelled else { return }
            advanceToNextStep()
        }
    }

    private func advanceToNextStep() {
        withAnimation(.spring(response: isComplete ? 0.82 : 0.72,
                              dampingFraction: isComplete ? 0.84 : 0.86)) {
            celebratingIndex = nil
            showsFinderMenuGuide = false
            showShortcutStage = isComplete && !shortcutConfigured
            showReadyStage = isComplete && shortcutConfigured
            if let next = firstUnresolvedIndex {
                activeIndex = next
            }
        }
        if isComplete && shortcutConfigured { Permissions.hasRunSetup = true }
    }

    private func requestFinderAccess() {
#if MAC_APP_STORE
        helpMode = .finderAccess
#else
        if states[0] == .granted {
            Permissions.openAutomationSettings()
            return
        }
        beginSystemPresentation()
        Permissions.requestAutomation { [weak self] state in
            guard let self else { return }
            restoreAfterSystemPresentation()
            isWorking = false
            apply([state, Permissions.filesState(), Permissions.finderExtensionState()],
                  celebrate: state == .granted ? 0 : nil)
            if state != .granted { Permissions.openAutomationSettings() }
        }
#endif
    }

    private func requestFolderAccess() {
        // This is an app-owned sheet, not a macOS privacy prompt. Keeping the
        // parent floating and repeatedly re-keying it fights the sheet closing
        // animation and causes the visible pause reported after Choose.
        isWorking = true
        Permissions.requestFiles(attachedTo: window) { [weak self] state, confirmed in
            guard let self else { return }
            // The development permission probe invokes PluginKit. Running it
            // synchronously in NSOpenPanel's completion handler blocks AppKit's
            // dismissal animation and makes the chooser look frozen.
            Task { [weak self] in
                async let automation = Task.detached(priority: .utility) {
                    Permissions.selectionSetupState()
                }.value
                async let menu = Task.detached(priority: .utility) {
                    Permissions.finderExtensionState()
                }.value
                let values = await [automation, state, menu]
                guard let self else { return }
                isWorking = false
                apply(values, celebrate: confirmed && state == .granted ? 1 : nil)
                guard window?.isVisible == true else { return }
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func requestFinderMenu() {
        if states[2] == .granted {
            Permissions.openExtensionSettings()
            return
        }
#if MAC_APP_STORE
        showFinderMenuGuide()
#else
        beginSystemPresentation()
        Permissions.hasRequestedFinderExtension = true
        Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) {
                Permissions.enableFinderExtension()
            }.value
            guard let self else { return }
            restoreAfterSystemPresentation()
            isWorking = false
            apply([Permissions.selectionSetupState(), Permissions.filesState(), state],
                  celebrate: state == .granted ? 2 : nil)
            if state != .granted { showFinderMenuGuide() }
        }
#endif
    }

    private func startWatching(for mode: HelpMode) {
        helpWatchTask?.cancel()
        helpWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, !Task.isCancelled else { return }
                async let automation = Task.detached(priority: .utility) {
                    Permissions.selectionSetupState()
                }.value
                async let extensionState = Task.detached(priority: .utility) {
                    Permissions.finderExtensionState()
                }.value
                let values = await [automation, Permissions.filesState(), extensionState]
                let resolved = mode == .finderAccess
                    ? values[0] == .granted
                    : values[2] == .granted
                guard resolved else { continue }
                if mode == .enableExtension {
                    isWatchingFinderMenu = false
                    FinderMenuCoach.shared.complete()
                    stopWatchingSettingsClose()
                    // Bring setup back while the guide celebrates, so the
                    // route visibly connects the moment the switch flips.
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard !Task.isCancelled else { return }
                    bringToFront()
                }
                apply(values, celebrate: mode == .finderAccess ? 0 : 2)
                try? await Task.sleep(nanoseconds: 780_000_000)
                guard !Task.isCancelled else { return }
                closeHelp()
                if window?.isVisible != true {
                    Toast.show(mode == .finderAccess ? "Finder access connected" : "Finder menu connected",
                               subtitle: mode == .finderAccess
                                   ? "AirFliq can now read your current Finder selection."
                                   : "Send with AirFliq is now available on right-click.",
                               kind: .success)
                }
                helpWatchTask = nil
                return
            }
        }
    }

    private func beginSystemPresentation() {
        isWorking = true
        window?.level = .floating
        bringToFront()
    }

    private func watchSettingsClose() {
        guard settingsCloseObserver == nil else { return }
        settingsCloseObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                app.bundleIdentifier == "com.apple.systempreferences" else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                stopWatchingSettingsClose()
                FinderMenuCoach.shared.dismiss()
                guard window?.isVisible == true else { return }
                bringToFront()
                refresh()
            }
        }
    }

    private func stopWatchingSettingsClose() {
        if let settingsCloseObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(settingsCloseObserver)
            self.settingsCloseObserver = nil
        }
    }

    private func restoreAfterSystemPresentation() {
        guard window?.isVisible == true else { return }
        bringToFront()
        for delay in [0.16, 0.44] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard self?.window?.isVisible == true else { return }
                self?.bringToFront()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { [weak self] in
            self?.window?.level = .normal
        }
    }

    private func bringToFront() {
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }
}

// MARK: - Experience

private struct OnboardingExperience: View {

    @ObservedObject var model: OnboardingExperienceModel
    @ObservedObject private var monetization = Monetization.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        ZStack {
            AirFliqFlightField(intensity: model.isWorking ? 1.0 : 0.72)

            VStack(spacing: 0) {
                header
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : -10)

                FlightRoute(
                    states: model.states,
                    skipped: model.skippedSteps,
                    shortcutConfigured: model.shortcutConfigured,
                    celebratingIndex: model.celebratingIndex,
                    activeIndex: model.showShortcutStage || model.showReadyStage
                        ? 3 : model.activeIndex,
                    onSelect: { index in
                        if index == 3 {
                            model.openShortcutSetup()
                        } else {
                            model.selectStep(index)
                        }
                    }
                )
                .frame(height: 82)
                .padding(.top, 14)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : -8)

                Group {
                    if model.showReadyStage {
                        ReadyStage(model: model)
                            .transition(.airFliqStage)
                    } else if model.showShortcutStage {
                        ShortcutStage(model: model)
                            .transition(.airFliqStage)
                    } else if model.showsFinderMenuGuide {
                        FinderMenuGuideStage(model: model)
                            .transition(.airFliqStage)
                    } else {
                        PermissionStage(model: model)
                            .id(model.activeIndex)
                            .transition(.airFliqStage)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 12)
                .opacity(entered ? 1 : 0)
                .scaleEffect(entered ? 1 : 0.975)

                footer
                    .padding(.top, 14)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 10)
            }
            .padding(.horizontal, 26)
            .padding(.top, 23)
            .padding(.bottom, 20)

            if let mode = model.helpMode {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture(perform: model.closeHelp)

                InlineTroubleshoot(mode: mode,
                                   close: model.closeHelp,
                                   action: model.performHelpAction)
                    .padding(.horizontal, 58)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(minWidth: 660, idealWidth: 660, maxWidth: 660,
               minHeight: 570, idealHeight: 570, maxHeight: 570)
        .onAppear(perform: runEntrance)
        .onChange(of: model.presentationCycle) { _ in runEntrance() }
        .animation(.spring(response: 0.58, dampingFraction: 0.82), value: model.helpMode)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AirDropIcon.appIcon(size: 80))
                .resizable()
                .frame(width: 31, height: 31)
                .shadow(color: .airFliqBlue.opacity(0.45), radius: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text("AIRFLIQ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                Text("Select. Fliq. Sent.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(model.completedStepCount) / 4 READY")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(model.isFullyConnected ? Color.airFliqGreen : .secondary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.5, dampingFraction: 0.8),
                           value: model.completedStepCount)

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            AirFliqDragControl(isOn: model.dragEnabled, action: model.toggleDrag)

            Spacer(minLength: 8)

            Text(monetization.setupSummary)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)

            Button("Troubleshoot", action: model.troubleshoot)
                .buttonStyle(AirFliqTextButtonStyle())
        }
        .frame(height: 34)
    }

    private func runEntrance() {
        entered = false
        guard !reduceMotion else { entered = true; return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.92, dampingFraction: 0.88)) {
                entered = true
            }
        }
    }
}

private struct InlineTroubleshoot: View {

    let mode: OnboardingExperienceModel.HelpMode
    let close: () -> Void
    let action: () -> Void
    @State private var entered = false

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(Color.airFliqViolet.opacity(0.16 + Double(index) * 0.05),
                                        style: StrokeStyle(lineWidth: 1,
                                                           dash: [2 + CGFloat(index), 7]))
                                .frame(width: 86 + CGFloat(index) * 28,
                                       height: 86 + CGFloat(index) * 28)
                                .rotationEffect(.degrees(time * Double(index.isMultiple(of: 2) ? 12 : -9)))
                        }
                        Circle()
                            .fill(RadialGradient(colors: [.airFliqBlue.opacity(0.30), .clear],
                                                 center: .center, startRadius: 0, endRadius: 68))
                            .frame(width: 138, height: 138)
                        Image(systemName: helpSymbol)
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(LinearGradient(colors: [.white, .airFliqCyan],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing))
                    }
                }
            }
            .frame(width: 170, height: 190)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("AIRFLIQ ASSIST")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color.airFliqCyan)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(-0.25)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.airFliqBlue, in: Circle())
                                .shadow(color: .airFliqBlue.opacity(0.55), radius: 6)
                            Text(step)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(entered ? 1 : 0)
                        .offset(x: entered ? 0 : 12)
                        .animation(.easeOut(duration: 0.48).delay(0.08 + Double(index) * 0.08),
                                   value: entered)
                    }
                }
                .padding(.top, 15)

                Button(action: action) {
                    HStack(spacing: 9) {
                        Text(actionTitle)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqBlue))
                .padding(.top, 17)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(28)
        .background { AirFliqGlassSurface(accent: .airFliqBlue, hovered: true) }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { entered = true }
        }
    }

    private var title: String {
        switch mode {
        case .finderAccess:
#if MAC_APP_STORE
            return "Choose files with your shortcut"
#else
            return "Reconnect Finder access"
#endif
        case .folderAccess: return "Choose your folder boundary"
        case .enableExtension: return "Connect the Finder menu"
        case .menuMissing: return "Finder needs one refresh"
        }
    }

    private var steps: [String] {
        switch mode {
        case .finderAccess:
#if MAC_APP_STORE
            return [
                "Press your shortcut to open the file picker.",
                "Choose files or folders, then confirm to open AirDrop.",
                "For Finder selections, use right-click or drag-and-drop.",
            ]
#else
            return [
                "Open Automation in System Settings.",
                "Allow AirFliq to control Finder.",
                "Return here. AirFliq verifies the change automatically.",
            ]
#endif
        case .folderAccess:
            return [
                "Open the macOS folder picker.",
                "Choose only the folders AirFliq may read.",
                "Change this list whenever you want.",
            ]
        case .enableExtension:
            if #available(macOS 15.0, *) {
                return [
                    "Open General → Login Items & Extensions.",
                    "Under Extensions, select AirFliq and switch it on.",
                    "Return here. AirFliq detects it automatically.",
                ]
            }
            return [
                "Open Finder Extensions in System Settings.",
                "Switch on AirFliq.",
                "Return here. AirFliq detects it automatically.",
            ]
        case .menuMissing:
            return [
                "The extension is already enabled.",
                "Finder has cached the previous menu.",
                "Restart Finder, then right-click the file again.",
            ]
        }
    }

    private var actionTitle: String {
        switch mode {
        case .finderAccess:
#if MAC_APP_STORE
            return "Got it"
#else
            return "Open Automation Settings"
#endif
        case .folderAccess: return "Choose Folders"
        case .enableExtension: return "Open Finder Extensions"
        case .menuMissing:
#if MAC_APP_STORE
            return "Close"
#else
            return "Restart Finder"
#endif
        }
    }

    private var helpSymbol: String {
        switch mode {
        case .finderAccess: return "cursorarrow.rays"
        case .folderAccess: return "folder.badge.gearshape"
        case .enableExtension: return "switch.2"
        case .menuMissing: return "arrow.clockwise"
        }
    }
}

// MARK: - Route

private struct FlightRoute: View {

    let states: [PermissionState]
    let skipped: Set<Int>
    let shortcutConfigured: Bool
    let celebratingIndex: Int?
    let activeIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 54
            let width = max(1, proxy.size.width - inset * 2)
            let points = (0..<4).map { index in
                CGPoint(x: inset + width * CGFloat(index) / 3,
                        y: index.isMultiple(of: 2) ? 35 : 25)
            }

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RouteSegment(
                        path: routeSegment(from: points[index], to: points[index + 1],
                                           rises: index.isMultiple(of: 2)),
                        complete: segmentIsComplete(index),
                        softened: false,
                        colors: index == 0
                            ? [.airFliqCyan, .airFliqBlue]
                            : index == 1
                                ? [.airFliqBlue, .airFliqViolet]
                                : [.airFliqViolet, .airFliqCyan]
                    )
                }

                ForEach(0..<4, id: \.self) { index in
                    let point = points[index]
                    Button { onSelect(index) } label: {
                        ZStack {
                            if activeIndex == index && !routeIsGranted(index) && !routeIsSkipped(index) {
                                ActiveNodePulse()
                                    .frame(width: 32, height: 32)
                            }
                            FlightPermissionGlyph(
                                state: routeState(index),
                                isActive: activeIndex == index,
                                size: 32,
                                animateCompletion: celebratingIndex == index
                            )
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(RouteNodeButtonStyle())
                    .position(x: point.x, y: point.y)

                    Text(routeTitle(index))
                        .font(.system(size: 10.5,
                                      weight: activeIndex == index ? .semibold : .medium))
                        .foregroundStyle(activeIndex == index ? .primary : .secondary)
                        .position(x: point.x, y: point.y + 29)
                        .animation(.easeOut(duration: 0.25), value: activeIndex)
                }
            }
        }
    }

    private func routeSegment(from first: CGPoint, to second: CGPoint,
                              rises: Bool) -> Path {
        let gap: CGFloat = 20
        let start = CGPoint(x: first.x + gap, y: first.y)
        let end = CGPoint(x: second.x - gap, y: second.y)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end,
                      control1: CGPoint(x: start.x + 48,
                                        y: start.y + (rises ? -20 : 18)),
                      control2: CGPoint(x: end.x - 48,
                                        y: end.y + (rises ? 18 : -20)))
        return path
    }

    private func routeTitle(_ index: Int) -> String {
#if MAC_APP_STORE
        ["Files", "Folders", "Right-click", "Shortcut"][index]
#else
        ["Finder", "Folders", "Right-click", "Shortcut"][index]
#endif
    }

    private func routeState(_ index: Int) -> PermissionState {
        guard routeIsGranted(index) || routeIsSkipped(index) else { return .unknown }
        return .granted
    }

    private func routeIsGranted(_ index: Int) -> Bool {
        if index < states.count { return states[index] == .granted }
        return shortcutConfigured
    }

    private func routeIsSkipped(_ index: Int) -> Bool {
        index < states.count && states[index] != .granted && skipped.contains(index)
    }

    private func segmentIsComplete(_ index: Int) -> Bool {
        (routeIsGranted(index) || routeIsSkipped(index))
            && (routeIsGranted(index + 1) || routeIsSkipped(index + 1))
    }
}

/// One leg of the flight route. When it connects, a comet travels the new
/// line from the completed step to the next one.
private struct RouteSegment: View {
    let path: Path
    let complete: Bool
    let softened: Bool
    let colors: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var comet: CGFloat = 0
    @State private var cometOpacity: Double = 0

    var body: some View {
        ZStack {
            path.stroke(Color.white.opacity(0.13),
                        style: StrokeStyle(lineWidth: 1.35, lineCap: .round, dash: [3, 7]))

            path.trim(from: 0, to: complete ? 1 : 0)
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: softened ? 1.7 : 2.35, lineCap: .round,
                                           dash: softened ? [4, 5] : []))
                .opacity(softened ? 0.5 : 1)
                .shadow(color: .airFliqBlue.opacity(softened ? 0.18 : 0.65), radius: 7)
                .animation(.spring(response: 0.95, dampingFraction: 0.9), value: complete)

            CometTrail(progress: comet, base: path)
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .shadow(color: .airFliqCyan, radius: 7)
                .shadow(color: .airFliqCyan.opacity(0.7), radius: 2)
                .opacity(cometOpacity)
        }
        .onChange(of: complete) { done in
            guard done, !softened, !reduceMotion else { return }
            comet = 0
            cometOpacity = 1
            withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 0.95)) { comet = 1.2 }
            withAnimation(.easeOut(duration: 0.3).delay(0.78)) { cometOpacity = 0 }
        }
    }
}

nonisolated private struct CometTrail: Shape {
    var progress: CGFloat
    let base: Path

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let head = min(1, max(0, progress))
        let tail = min(1, max(0, progress - 0.2))
        guard head > tail else { return Path() }
        return base.trimmedPath(from: tail, to: head)
    }
}

/// "You are here": a slow sonar ring around the step waiting for the user.
private struct ActiveNodePulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanding = false

    var body: some View {
        Circle()
            .stroke(Color.airFliqCyan.opacity(0.55), lineWidth: 1.2)
            .scaleEffect(expanding ? 1.75 : 1)
            .opacity(expanding ? 0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    expanding = true
                }
            }
    }
}

private struct RouteNodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Focused stages

private struct PermissionStage: View {

    @ObservedObject var model: OnboardingExperienceModel
    @State private var hovered = false

    private var step: OnboardingExperienceModel.Step { model.activeStep }
    private var state: PermissionState { model.activeState }

    var body: some View {
        HStack(spacing: 34) {
            StepConstellation(step: step, isWorking: model.isWorking,
                              completionState: state,
                              isCelebrating: model.celebratingIndex == step.id)
                .frame(width: 196, height: 196)

            VStack(alignment: .leading, spacing: 0) {
                Text(displayEyebrow)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(step.accent)

                Text(displayTitle)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.35)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Text(displayDetail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)

                Group {
                    if model.celebratingIndex == step.id {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(Color.airFliqGreen, in: Circle())
                            Text("Route secured")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.airFliqGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.airFliqGreen.opacity(0.10), in:
                                        RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.airFliqGreen.opacity(0.28), lineWidth: 1)
                        }
                    } else {
                        VStack(spacing: 5) {
                            Button(action: model.performActiveAction) {
                                HStack(spacing: 10) {
                                    if model.isWorking {
                                        AirFliqCometLoader(color: step.accent)
                                            .frame(width: 19, height: 19)
                                    } else {
                                        Image(systemName: state == .granted
                                              ? "slider.horizontal.3" : "arrow.up.right")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    Text(buttonTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            }
                            .buttonStyle(AirFliqPrimaryButtonStyle(accent: step.accent))
                            .disabled(model.isWorking)

                            if let skipTitle = step.skipTitle, state != .granted {
                                Button(action: model.skipActiveStep) {
                                    HStack(spacing: 6) {
                                        Text(model.isSkipped(step.id) ? "Skipped  •  \(skipTitle)" : skipTitle)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                }
                                .buttonStyle(AirFliqTextButtonStyle())
                                .disabled(model.isWorking)
                            }
                        }
                    }
                }
                .padding(.top, 19)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background {
            AirFliqGlassSurface(accent: step.accent, hovered: hovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.32)) { hovered = value }
        }
    }

    private var buttonTitle: String {
        if model.isWorking { return "Waiting for macOS" }
#if MAC_APP_STORE
        if step.id == 0 { return "How it works" }
#endif
        if state == .granted {
            return step.id == 1 ? "Manage Folders" : "Review in Settings"
        }
        if state == .denied {
            switch step.id {
            case 1: return "Choose Folders Again"
            case 2: return "Turn On Finder Menu"
            default: return "Fix Access"
            }
        }
        return step.action
    }

    private var displayEyebrow: String {
        model.celebratingIndex == step.id ? "ROUTE SECURED" : step.eyebrow
    }

    private var displayTitle: String {
        model.celebratingIndex == step.id ? "Connected." : step.title
    }

    private var displayDetail: String {
        if model.celebratingIndex == step.id {
            return step.id == 2
                ? "Send with AirFliq is now in Finder's right-click menu."
                : "AirFliq is moving the flight path to your next setup step."
        }
        return step.detail
    }
}

/// The Right-click step's guide. It explains the one switch in System
/// Settings first; opening Settings is a separate, deliberate click.
private struct FinderMenuGuideStage: View {
    @ObservedObject var model: OnboardingExperienceModel
    @State private var revealed = false

    private let accent = Color(red: 0.68, green: 0.35, blue: 1.0)

    var body: some View {
        HStack(spacing: 24) {
            SettingsPathIllustration(connected: model.states[2] == .granted)
                .frame(width: 212, height: 196)
                .scaleEffect(revealed ? 1 : 0.94)
                .opacity(revealed ? 1 : 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("RIGHT-CLICK  •  ONE SWITCH")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(accent)

                Text("Switch on AirFliq in System Settings.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(FinderMenuSettingsPath.steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(accent, in: Circle())
                                .shadow(color: accent.opacity(0.55), radius: 5)
                            Text(text)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(revealed ? 1 : 0)
                        .offset(x: revealed ? 0 : 10)
                        .animation(.spring(response: 0.55, dampingFraction: 0.84)
                            .delay(0.12 + Double(index) * 0.07), value: revealed)
                    }
                }
                .padding(.top, 12)

                Button(action: model.openFinderMenuSettings) {
                    HStack(spacing: 9) {
                        if model.isWatchingFinderMenu {
                            AirFliqCometLoader(color: .white)
                                .frame(width: 17, height: 17)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(model.isWatchingFinderMenu
                             ? "Waiting for the switch…"
                             : "Open System Settings")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(AirFliqPrimaryButtonStyle(accent: accent))
                .padding(.top, 14)
                .accessibilityHint("Opens System Settings. AirFliq detects the switch automatically.")

                HStack {
                    Button(action: model.closeFinderMenuGuide) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 9, weight: .bold))
                            Text("Back")
                        }
                    }
                    .buttonStyle(AirFliqTextButtonStyle())
                    Spacer()
                    Button(action: model.skipActiveStep) {
                        HStack(spacing: 5) {
                            Text("Skip for now")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .buttonStyle(AirFliqTextButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background { AirFliqGlassSurface(accent: accent, hovered: model.isWatchingFinderMenu) }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) { revealed = true }
        }
    }
}

private struct ShortcutStage: View {
    @ObservedObject var model: OnboardingExperienceModel
    @State private var revealed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        HStack(spacing: 34) {
            ShortcutConstellation(shortcut: model.currentShortcut,
                                  active: revealed,
                                  onSelect: model.chooseShortcut)
                .frame(width: 196, height: 196)

            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR LAUNCH GESTURE")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.airFliqCyan)

                Text("Make AirFliq yours.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.3)
                    .padding(.top, 7)

                Text("Choose a preset or record any safe global shortcut.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Shortcut.presets) { shortcut in
                        Button(shortcut.name) { _ = model.chooseShortcut(shortcut) }
                            .buttonStyle(ShortcutPresetStyle(
                                selected: shortcut == model.currentShortcut
                            ))
                    }
                }
                .padding(.top, 11)

                AirFliqShortcutRecorder(current: model.currentShortcut,
                                         onCapture: model.chooseShortcut)
                    .padding(.top, 8)

                Group {
                    if model.isShortcutCompleting {
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.airFliqGreen, in: Circle())
                            Text("Launch gesture secured")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.airFliqGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.airFliqGreen.opacity(0.10), in:
                                        RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.airFliqGreen.opacity(0.30), lineWidth: 1)
                        }
                    } else {
                        Button(action: model.completeShortcutSetup) {
                            HStack(spacing: 9) {
                                Text("Use \(model.currentShortcut.name)")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        }
                        .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqBlue))
                    }
                }
                .padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background { AirFliqGlassSurface(accent: .airFliqBlue, hovered: false) }
        .onAppear {
            withAnimation(.spring(response: 0.84, dampingFraction: 0.8)) { revealed = true }
        }
    }
}

private struct ShortcutConstellation: View {
    let shortcut: Shortcut
    let active: Bool
    let onSelect: (Shortcut) -> Bool

    @State private var displayedCenter: Shortcut
    @State private var orbitItems: [Shortcut]
    @State private var swapFlight: ShortcutSwapFlight?
    @State private var swapProgress: CGFloat = 0
    @State private var queuedShortcut: Shortcut?

    init(shortcut: Shortcut, active: Bool,
         onSelect: @escaping (Shortcut) -> Bool) {
        self.shortcut = shortcut
        self.active = active
        self.onSelect = onSelect
        _displayedCenter = State(initialValue: shortcut)
        _orbitItems = State(initialValue:
            Array(Shortcut.presets.filter { $0 != shortcut }.prefix(7)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 32 + CGFloat(index) * 5,
                                     style: .continuous)
                        .stroke(index == 1 ? Color.airFliqViolet.opacity(0.22)
                                           : Color.airFliqBlue.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1,
                                                   dash: [3 + CGFloat(index), 7]))
                        .frame(width: 108 + CGFloat(index) * 25,
                               height: 108 + CGFloat(index) * 25)
                        .rotationEffect(.degrees(time * Double(index.isMultiple(of: 2) ? 7 : -6)))
                }

                ForEach(Array(orbitItems.enumerated()), id: \.element.id) { slot, item in
                    Button { _ = onSelect(item) } label: {
                        ShortcutOrbitCard(shortcut: item, prominence: 0)
                    }
                    .buttonStyle(.plain)
                    .offset(orbitOffset(slot: slot, time: time))
                    .opacity(swapFlight?.outgoing.id == item.id
                             ? 0 : 1)
                    .allowsHitTesting(swapFlight == nil)
                    .zIndex(2)
                }

                Circle()
                    .fill(RadialGradient(colors: [.airFliqCyan.opacity(0.30), .clear],
                                         center: .center, startRadius: 0, endRadius: 72))
                    .frame(width: 150, height: 150)
                    .scaleEffect(0.86 + 0.32 * swapProgress)
                    .opacity(0.18 + 0.57 * swapProgress)
                    .allowsHitTesting(false)

                if let swapFlight {
                    let movingOffset = orbitOffset(slot: swapFlight.slot, time: time)
                    let incomingOffset = flightOffset(base: movingOffset,
                                                      progress: 1 - swapProgress,
                                                      lane: 1)
                    let outgoingOffset = flightOffset(base: movingOffset,
                                                      progress: swapProgress,
                                                      lane: -1)

                    ShortcutOrbitCard(shortcut: swapFlight.incoming,
                                      prominence: swapProgress)
                        .offset(incomingOffset)
                        .zIndex(12)

                    ShortcutOrbitCard(shortcut: swapFlight.outgoing,
                                      prominence: 1 - swapProgress)
                        .offset(outgoingOffset)
                        .zIndex(11)
                }

                // The stable destination is swapped in only after the moving
                // card reaches this exact geometry. There is deliberately no
                // crossfade or settlement pause at the endpoint.
                ShortcutOrbitCard(shortcut: displayedCenter, prominence: 1)
                    .scaleEffect(active ? 1 : 0.76)
                    .opacity(swapFlight == nil ? 1 : 0)
                    .zIndex(10)
            }
        }
        .task(id: shortcut.id) {
            // A parent refresh can recreate the value input before onChange
            // observes the old one while this view's @State survives. A task
            // keyed by the stable shortcut ID always synchronizes that retained
            // visual state and still cancels cleanly on the next selection.
            await MainActor.run {
                beginSwap(to: shortcut)
            }
        }
    }

    private func orbitOffset(slot: Int, time: TimeInterval) -> CGSize {
        let count = max(orbitItems.count, 1)
        let angle = time * 0.40 + Double(slot) * (.pi * 2 / Double(count))
        return CGSize(width: cos(angle) * 65, height: sin(angle) * 65)
    }

    private func flightOffset(base: CGSize,
                              progress: CGFloat,
                              lane: CGFloat) -> CGSize {
        let clamped = min(max(progress, 0), 1)
        let distance = max(hypot(base.width, base.height), 1)
        let perpendicular = CGSize(width: -base.height / distance,
                                   height: base.width / distance)
        let arc = CGFloat(sin(Double(clamped) * .pi)) * 18 * lane
        return CGSize(width: base.width * clamped + perpendicular.width * arc,
                      height: base.height * clamped + perpendicular.height * arc)
    }

    private func beginSwap(to incoming: Shortcut) {
        guard incoming.id != displayedCenter.id else { return }

        // Preset buttons can be clicked faster than one flight. Queue only the
        // latest choice so an in-flight card never gets replaced mid-frame.
        if swapFlight != nil {
            queuedShortcut = incoming
            return
        }

        let outgoing = displayedCenter
        let slot = orbitItems.firstIndex(where: { $0.id == incoming.id }) ?? 0
        if orbitItems.indices.contains(slot) {
            orbitItems[slot] = outgoing
        } else {
            orbitItems = [outgoing]
        }
        displayedCenter = incoming

        let flight = ShortcutSwapFlight(incoming: incoming,
                                        outgoing: outgoing,
                                        slot: slot)
        swapFlight = flight
        DispatchQueue.main.async {
            // Only position, uniform scale and rotation animate. The card's
            // layout stays fixed, so it cannot stretch or deform in flight.
            withAnimation(.timingCurve(0.18, 0.80, 0.22, 1,
                                       duration: 0.76)) {
                swapProgress = 1
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 780_000_000)
            guard swapFlight?.id == flight.id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swapFlight = nil
                swapProgress = 0
            }

            let next = queuedShortcut
            queuedShortcut = nil
            if let next, next.id != displayedCenter.id {
                DispatchQueue.main.async { beginSwap(to: next) }
            }
        }
    }
}

private struct ShortcutSwapFlight: Identifiable {
    let id = UUID()
    let incoming: Shortcut
    let outgoing: Shortcut
    let slot: Int
}

private struct ShortcutOrbitCard: View {
    let shortcut: Shortcut
    let prominence: CGFloat

    private var progress: CGFloat { min(max(prominence, 0), 1) }
    private var cardScale: CGFloat { 0.50 + 0.50 * progress }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 25, weight: .medium))
                .frame(height: 25)
            Text(shortcut.name)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(width: 105, height: 86)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(colors: [.white.opacity(0.075),
                                            .white.opacity(0.045)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [.airFliqBlue.opacity(0.34),
                                                      .airFliqViolet.opacity(0.22)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .opacity(progress)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10 * (1 - progress)), lineWidth: 1)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.airFliqCyan.opacity(0.42 * progress),
                        lineWidth: 1 + 0.2 * progress)
        }
        .shadow(color: Color.airFliqBlue.opacity(0.42 * progress),
                radius: 22 * progress)
        .scaleEffect(cardScale)
        .opacity(0.72 + 0.28 * progress)
        .compositingGroup()
    }
}

private struct ShortcutPresetStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(selected ? Color.white : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(selected ? Color.airFliqBlue.opacity(0.86)
                                 : Color.white.opacity(configuration.isPressed ? 0.10 : 0.045),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.airFliqCyan.opacity(0.52)
                                     : Color.white.opacity(0.07), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.72),
                       value: configuration.isPressed)
    }
}

private struct ReadyStage: View {

    @ObservedObject var model: OnboardingExperienceModel
    @ObservedObject private var monetization = Monetization.shared
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 34) {
            ZStack {
                AirFliqSuccessBurst(active: revealed)
                FlightPermissionGlyph(state: .granted,
                                      isActive: true, size: 104,
                                      animateCompletion: false)
            }
            .frame(width: 196, height: 196)

            VStack(alignment: .leading, spacing: 0) {
                Text("CLEARED FOR TAKEOFF")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.airFliqGreen)

                Text("AirFliq is ready.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .padding(.top, 10)

                Text(AirDrop.readyInstructions)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ReadyRouteChip(symbol: "keyboard", title: model.currentShortcut.name,
                                       isOn: true, order: 0, revealed: revealed)
                        ReadyRouteChip(symbol: "menubar.rectangle", title: "Menu bar",
                                       isOn: true, order: 1, revealed: revealed)
                    }
                    HStack(spacing: 6) {
                        ReadyRouteChip(symbol: "filemenu.and.selection", title: "Right-click",
                                       isOn: model.states[2] == .granted, order: 2, revealed: revealed)
                        ReadyRouteChip(symbol: "cursorarrow.motionlines", title: "Drag target",
                                       isOn: model.dragEnabled, order: 3, revealed: revealed)
                    }
                }
                .padding(.top, 12)

                Button(action: model.finish) {
                    HStack(spacing: 10) {
                        Text("Start sending")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqGreen))
                .padding(.top, 15)

                if !monetization.isPro && !monetization.isTrialStarted {
                    Button(action: model.finishAndShowPro) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("\(Monetization.freeDailySendLimit) free sends a day  •  Try unlimited for 7 days")
                        }
                    }
                    .buttonStyle(AirFliqTextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background { AirFliqGlassSurface(accent: .airFliqGreen, hovered: false) }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.78).delay(0.08)) {
                revealed = true
            }
        }
    }
}

// MARK: - Symbols and motion

private struct StepConstellation: View {

    let step: OnboardingExperienceModel.Step
    let isWorking: Bool
    let completionState: PermissionState
    let isCelebrating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            constellation(at: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    private func constellation(at time: TimeInterval) -> some View {
        ZStack {
            orbitRings(at: time)
            orbitParticles(at: time)
            constellationGlow
            constellationCenter
        }
    }

    private func orbitRings(at time: TimeInterval) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .stroke(step.accent.opacity(0.10 + Double(index) * 0.05),
                        style: StrokeStyle(lineWidth: 1,
                                           dash: [2 + CGFloat(index), 7]))
                .frame(width: 112 + CGFloat(index) * 24,
                       height: 112 + CGFloat(index) * 24)
                .rotationEffect(.degrees(
                    time * (isWorking ? 30 : 8)
                        * (index.isMultiple(of: 2) ? 1 : -1)
                ))
        }
    }

    private func orbitParticles(at time: TimeInterval) -> some View {
        let particleColor = step.accent.opacity(0.55)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<7 {
                let rect = particleRect(index: index, time: time, center: center)
                context.fill(Path(ellipseIn: rect),
                             with: .color(particleColor))
            }
        }
    }

    private func particleRect(index: Int,
                              time: TimeInterval,
                              center: CGPoint) -> CGRect {
        let speed: Double = isWorking ? 1.15 : 0.34
        let spacing: Double = .pi * 2.0 / 7.0
        let angle: Double = time * speed + Double(index) * spacing
        let radius: CGFloat = 64.0 + CGFloat(index % 3) * 9.0
        let x = center.x + CGFloat(cos(angle)) * radius
        let y = center.y + CGFloat(sin(angle)) * radius
        return CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
    }

    private var constellationGlow: some View {
        Circle()
            .fill(
                RadialGradient(colors: [step.accent.opacity(0.34),
                                        step.accent.opacity(0.10), .clear],
                               center: .center, startRadius: 0, endRadius: 68)
            )
            .frame(width: 138, height: 138)
            .blur(radius: 4)
    }

    @ViewBuilder
    private var constellationCenter: some View {
        if completionState == .granted {
            FlightPermissionGlyph(state: .granted,
                                  isActive: true, size: 88,
                                  animateCompletion: isCelebrating)
        } else {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Circle().stroke(step.accent.opacity(0.34), lineWidth: 1)
                    }
                Image(systemName: step.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, step.accent],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .symbolRenderingMode(.monochrome)
            }
            .shadow(color: step.accent.opacity(isWorking ? 0.8 : 0.38),
                    radius: isWorking ? 24 : 14)
        }
    }
}

private struct FlightPermissionGlyph: View {

    let state: PermissionState
    let isActive: Bool
    let size: CGFloat
    let animateCompletion: Bool
    var skipped = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var hasPlayedCompletion = false
    @State private var completionScale: CGFloat = 1

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 2

            switch state {
            case .unknown where skipped:
                drawSegments(context: &context, center: center, radius: radius,
                             litProgress: 0, baseColor: Color.airFliqViolet.opacity(isActive ? 0.6 : 0.42))
                drawSkipMark(context: &context, center: center, radius: radius)
            case .unknown:
                drawSegments(context: &context, center: center, radius: radius,
                             litProgress: 0, baseColor: Color.white.opacity(isActive ? 0.28 : 0.16))
            case .denied:
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(.orange.opacity(0.92)))
                drawExclamation(context: &context, center: center, radius: radius)
            case .granted:
                drawSuccess(context: &context, center: center, radius: radius)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(completionScale)
        .shadow(color: state == .granted ? Color.airFliqGreen.opacity(0.52) : .clear,
                radius: renderedProgress > 0.7 ? 11 : 0)
        .onAppear(perform: applyVisualPhase)
        .onChange(of: visualPhase) { _ in applyVisualPhase() }
    }

    private var renderedProgress: CGFloat {
        state == .granted && !animateCompletion ? 1 : progress
    }

    private var visualPhase: Int {
        switch state {
        case .unknown: return 0
        case .denied: return 1
        case .granted: return animateCompletion ? 3 : 2
        }
    }

    private func applyVisualPhase() {
        if state == .granted, animateCompletion {
            guard !hasPlayedCompletion else { return }
            hasPlayedCompletion = true
            runCompletion()
        } else {
            if state != .granted { hasPlayedCompletion = false }
            progress = state == .granted ? 1 : 0
            completionScale = 1
        }
    }

    private func runCompletion() {
        progress = 0
        completionScale = 0.82
        guard !reduceMotion else {
            progress = 1
            completionScale = 1
            return
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.72)) { progress = 1 }
            // The bounce starts exactly as the solid disc finishes. Starting it
            // during the fill phase was the small hitch visible at the end.
            withAnimation(.spring(response: 0.58, dampingFraction: 0.62)
                .delay(1.31)) {
                completionScale = 1
            }
        }
    }

    private func drawSuccess(context: inout GraphicsContext,
                             center: CGPoint, radius: CGFloat) {
        // One continuous sequence: finish every perimeter segment, replace it
        // with the solid disc, then draw the check. The phases meet at their
        // boundaries, so there is neither a gap nor a duplicated overlap.
        let segmentProgress = remap(renderedProgress, 0, 0.56)
        let fillProgress = smoothStep(remap(renderedProgress, 0.56, 0.76))
        let checkProgress = smoothStep(remap(renderedProgress, 0.76, 1))

        if fillProgress < 1 {
            drawSegments(context: &context, center: center, radius: radius,
                         litProgress: segmentProgress,
                         baseColor: Color.white.opacity(0.16))
        }

        if fillProgress > 0 {
            let discRadius = radius * (0.18 + 0.82 * fillProgress)
            let rect = CGRect(x: center.x - discRadius, y: center.y - discRadius,
                              width: discRadius * 2, height: discRadius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(
                            Gradient(colors: [Color(red: 0.43, green: 1.0, blue: 0.58),
                                              .airFliqGreen]),
                            center: center,
                            startRadius: 0,
                            endRadius: discRadius
                         ))
        }

        guard checkProgress > 0 else { return }
        let start = CGPoint(x: center.x - radius * 0.43, y: center.y + radius * 0.02)
        let middle = CGPoint(x: center.x - radius * 0.12, y: center.y + radius * 0.31)
        let end = CGPoint(x: center.x + radius * 0.47, y: center.y - radius * 0.36)
        let path = partialPolyline([start, middle, end], progress: checkProgress)
        context.stroke(path, with: .color(.white),
                       style: StrokeStyle(lineWidth: max(2.2, radius * 0.16),
                                          lineCap: .round, lineJoin: .round))
    }

    private func drawSegments(context: inout GraphicsContext,
                              center: CGPoint, radius: CGFloat,
                              litProgress: CGFloat, baseColor: Color) {
        let count = 14
        for index in 0..<count {
            let fraction = CGFloat(index) / CGFloat(count)
            let start = Angle.degrees(-90 + Double(index) * 360 / Double(count) + 3)
            let end = Angle.degrees(-90 + Double(index + 1) * 360 / Double(count) - 3)
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: start, endAngle: end, clockwise: false)
            let lit = min(1, max(0, (litProgress - fraction) * CGFloat(count)))
            let color = lit > 0
                ? Color.airFliqGreen.opacity(0.35 + 0.65 * lit)
                : baseColor
            context.stroke(arc, with: .color(color),
                           style: StrokeStyle(lineWidth: max(1.8, radius * 0.12),
                                              lineCap: .round))
        }
    }

    private func drawSkipMark(context: inout GraphicsContext,
                              center: CGPoint, radius: CGFloat) {
        let side = radius * 0.26
        var mark = Path()
        for shift in [-side * 0.62, side * 0.62] {
            mark.move(to: CGPoint(x: center.x + shift - side * 0.5, y: center.y - side))
            mark.addLine(to: CGPoint(x: center.x + shift + side * 0.5, y: center.y))
            mark.addLine(to: CGPoint(x: center.x + shift - side * 0.5, y: center.y + side))
        }
        context.stroke(mark, with: .color(Color.white.opacity(0.72)),
                       style: StrokeStyle(lineWidth: max(1.4, radius * 0.1),
                                          lineCap: .round, lineJoin: .round))
    }

    private func drawExclamation(context: inout GraphicsContext,
                                 center: CGPoint, radius: CGFloat) {
        var mark = Path()
        mark.move(to: CGPoint(x: center.x, y: center.y - radius * 0.42))
        mark.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.13))
        context.stroke(mark, with: .color(.white),
                       style: StrokeStyle(lineWidth: max(2, radius * 0.14), lineCap: .round))
        let dot = CGRect(x: center.x - radius * 0.08, y: center.y + radius * 0.42,
                         width: radius * 0.16, height: radius * 0.16)
        context.fill(Path(ellipseIn: dot), with: .color(.white))
    }

    private func partialPolyline(_ points: [CGPoint], progress: CGFloat) -> Path {
        guard points.count == 3 else { return Path() }
        let first = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let second = hypot(points[2].x - points[1].x, points[2].y - points[1].y)
        let target = (first + second) * progress
        var path = Path()
        path.move(to: points[0])
        if target <= first {
            let amount = target / max(first, 0.001)
            path.addLine(to: interpolate(points[0], points[1], amount))
        } else {
            path.addLine(to: points[1])
            let amount = min(1, (target - first) / max(second, 0.001))
            path.addLine(to: interpolate(points[1], points[2], amount))
        }
        return path
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, _ value: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * value,
                y: a.y + (b.y - a.y) * value)
    }

    private func remap(_ value: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
        min(1, max(0, (value - start) / (end - start)))
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}

struct AirFliqSuccessBurst: View {

    let active: Bool

    var body: some View {
        ZStack {
            // A shockwave first, then two rings of sparks at different speeds.
            Circle()
                .stroke(Color.airFliqGreen.opacity(active ? 0 : 0.75), lineWidth: 2)
                .frame(width: 96, height: 96)
                .scaleEffect(active ? 2.05 : 0.8)
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.05), value: active)

            ForEach(0..<18, id: \.self) { index in
                let long = index.isMultiple(of: 2)
                Capsule()
                    .fill([Color.airFliqGreen, .airFliqCyan, .airFliqBlue][index % 3])
                    .frame(width: long ? 3 : 2.4, height: long ? 15 : 9)
                    .offset(y: active ? (long ? -90 : -68) : -30)
                    .rotationEffect(.degrees(Double(index) * 20 + (long ? 0 : 10)))
                    .opacity(active ? 0 : 0.95)
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: long ? 1.1 : 0.85)
                        .delay(Double(index % 6) * 0.014), value: active)
            }
        }
    }
}

private struct ReadyRouteChip: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let order: Int
    let revealed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            Circle()
                .fill(isOn ? Color.airFliqGreen : Color.white.opacity(0.22))
                .frame(width: 5, height: 5)
                .shadow(color: isOn ? Color.airFliqGreen.opacity(0.8) : .clear, radius: 3)
        }
        .foregroundStyle(isOn ? Color.primary : .secondary)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.white.opacity(isOn ? 0.075 : 0.035), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(isOn ? 0.12 : 0.06), lineWidth: 1))
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 6)
        .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25 + Double(order) * 0.06),
                   value: revealed)
    }
}

extension AnyTransition {
    /// Stages trade places with depth: the new one drifts in sharpening, the
    /// old one drifts out softening, instead of a flat slide.
    static var airFliqStage: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: StageMotion(offset: 44, scale: 0.965, blur: 7, opacity: 0),
                                 identity: StageMotion(offset: 0, scale: 1, blur: 0, opacity: 1)),
            removal: .modifier(active: StageMotion(offset: -44, scale: 0.975, blur: 7, opacity: 0),
                               identity: StageMotion(offset: 0, scale: 1, blur: 0, opacity: 1))
        )
    }
}

private struct StageMotion: ViewModifier {
    let offset: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

// MARK: - Shared controls

private struct AirFliqDragControl: View {

    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.airFliqCyan : .secondary)
                Text("Drag target")
                    .font(.system(size: 11.5, weight: .semibold))

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.airFliqBlue.opacity(0.9) : Color.white.opacity(0.10))
                        .frame(width: 34, height: 18)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .padding(2)
                        .shadow(color: isOn ? .airFliqCyan.opacity(0.8) : .clear, radius: 5)
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isOn)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.white.opacity(hovered ? 0.10 : 0.055), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(hovered ? 0.16 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.22)) { hovered = value }
        }
    }
}

struct AirFliqCometLoader: View {

    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate * 260
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.23)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(angle))
                    .shadow(color: color, radius: 4)
            }
        }
    }
}

struct AirFliqGlassSurface: View {

    let accent: Color
    let hovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(colors: [accent.opacity(hovered ? 0.15 : 0.08),
                                                Color.white.opacity(0.025),
                                                Color.black.opacity(0.10)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(hovered ? 0.24 : 0.15),
                                                accent.opacity(hovered ? 0.32 : 0.12),
                                                Color.white.opacity(0.05)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .shadow(color: accent.opacity(hovered ? 0.20 : 0.08), radius: hovered ? 30 : 18, y: 8)
    }
}

struct AirFliqPrimaryButtonStyle: ButtonStyle {

    let accent: Color

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, accent: accent)
    }

    struct Body: View {
        let configuration: Configuration
        let accent: Color
        @State private var hovered = false
        @State private var sheen = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(colors: [accent.opacity(0.98), .airFliqBlue,
                                                    .airFliqViolet.opacity(0.92)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                }
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.42), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: 70)
                            .rotationEffect(.degrees(18))
                            .offset(x: sheen ? proxy.size.width + 40 : -110)
                            .opacity(hovered ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(hovered ? 0.32 : 0.14), lineWidth: 1)
                }
                .shadow(color: accent.opacity(hovered ? 0.58 : 0.26),
                        radius: hovered ? 18 : 10, y: hovered ? 6 : 3)
                .scaleEffect(configuration.isPressed ? 0.975 : (hovered ? 1.012 : 1))
                .animation(.spring(response: 0.34, dampingFraction: 0.72),
                           value: configuration.isPressed)
                .animation(.easeOut(duration: 0.24), value: hovered)
                .onHover { value in
                    hovered = value
                    if value {
                        sheen = false
                        withAnimation(.easeInOut(duration: 0.72)) { sheen = true }
                    }
                }
        }
    }
}

struct AirFliqTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> TextButtonBody {
        TextButtonBody(configuration: configuration)
    }

    struct TextButtonBody: View {
        let configuration: Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? Color.airFliqCyan : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.white.opacity(hovered ? 0.065 : 0), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.2), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct AirFliqFlightField: View {

    let intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0,
                                paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // One Canvas draws the whole field. It takes exactly the space it
            // is offered, never influences layout, and is cheap to redraw.
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(Path(bounds), with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.035, green: 0.047, blue: 0.075),
                        Color(red: 0.055, green: 0.045, blue: 0.085),
                        Color(red: 0.025, green: 0.028, blue: 0.045),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)))

                let middle = CGPoint(x: size.width / 2, y: size.height / 2)
                let blue = CGPoint(x: middle.x - 250 + CGFloat(sin(time * 0.22)) * 24,
                                   y: middle.y - 210 + CGFloat(cos(time * 0.18)) * 18)
                let violet = CGPoint(x: middle.x + 270 + CGFloat(cos(time * 0.19)) * 28,
                                     y: middle.y + 240 + CGFloat(sin(time * 0.16)) * 22)
                for (center, color, radius, strength) in [
                    (blue, Color.airFliqBlue, CGFloat(270), 0.17),
                    (violet, Color.airFliqViolet, CGFloat(300), 0.15),
                ] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(strength * intensity),
                                              color.opacity(strength * 0.35 * intensity),
                                              color.opacity(0)]),
                            center: center, startRadius: 0, endRadius: radius))
                }

                for index in 0..<4 {
                    var path = Path()
                    let y = size.height * (0.18 + CGFloat(index) * 0.19)
                    path.move(to: CGPoint(x: -40, y: y))
                    path.addCurve(
                        to: CGPoint(x: size.width + 40, y: y + (index.isMultiple(of: 2) ? 26 : -22)),
                        control1: CGPoint(x: size.width * 0.28,
                                          y: y + CGFloat(sin(time * 0.30 + Double(index))) * 30),
                        control2: CGPoint(x: size.width * 0.72,
                                          y: y - CGFloat(cos(time * 0.24 + Double(index))) * 28)
                    )
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [.clear,
                                              Color.airFliqBlue.opacity(0.12 * intensity),
                                              Color.airFliqViolet.opacity(0.10 * intensity),
                                              .clear]),
                            startPoint: CGPoint(x: 0, y: y),
                            endPoint: CGPoint(x: size.width, y: y)
                        ),
                        style: StrokeStyle(lineWidth: 1,
                                           lineCap: .round,
                                           dash: [2, 12],
                                           dashPhase: CGFloat(-time * 18 - Double(index) * 9))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension Color {
    static let airFliqCyan = Color(red: 0.18, green: 0.82, blue: 1.0)
    static let airFliqBlue = Color(red: 0.10, green: 0.48, blue: 1.0)
    static let airFliqViolet = Color(red: 0.49, green: 0.28, blue: 1.0)
    static let airFliqGreen = Color(red: 0.20, green: 0.88, blue: 0.43)
}
