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

    func present(startAtShortcut: Bool = false) {
        guard let window else { return }
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
        model.present(forceShortcutStage: startAtShortcut)

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
        close()
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
    }

    let steps = [
        Step(id: 0,
             eyebrow: "FINDER SELECTION",
             title: "Point. AirFliq sees it.",
             detail: "Allow read-only access to the files currently selected in Finder.",
             action: "Allow Finder Access",
             symbol: "cursorarrow.rays",
             accent: Color(red: 0.16, green: 0.72, blue: 1.0)),
        Step(id: 1,
             eyebrow: "YOUR FOLDERS",
             title: "You choose the boundaries.",
             detail: "Pick only the folders AirFliq may use. Add another only when you need it.",
             action: "Choose Folders",
             symbol: "folder.fill",
             accent: Color(red: 0.42, green: 0.48, blue: 1.0)),
        Step(id: 2,
             eyebrow: "RIGHT-CLICK",
             title: "Send from where you already are.",
             detail: "Place Send with AirFliq directly inside Finder's contextual menu.",
             action: "Enable Finder Menu",
             symbol: "filemenu.and.selection",
             accent: Color(red: 0.68, green: 0.35, blue: 1.0)),
    ]

    @Published private(set) var states: [PermissionState] = [.unknown, .unknown, .unknown]
    @Published private(set) var isWorking = false
    @Published private(set) var presentationCycle = 0
    @Published private(set) var showReadyStage = false
    @Published private(set) var showShortcutStage = false
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
    private var isRefreshing = false
    private var hasLoadedInitialState = false
    private var forceShortcutStage = false

    var completedCount: Int { states.filter { $0 == .granted }.count }
    var completedStepCount: Int { completedCount + (shortcutConfigured ? 1 : 0) }
    var isComplete: Bool { completedCount == steps.count }
    var activeStep: Step { steps[activeIndex] }
    var activeState: PermissionState { states[activeIndex] }

    func present(forceShortcutStage: Bool = false) {
        presentationCycle += 1
        helpMode = nil
        showReadyStage = false
        showShortcutStage = false
        celebratingIndex = nil
        dragEnabled = DragCatcher.shared.isEnabled
        currentShortcut = Shortcut.current
        shortcutConfigured = Shortcut.hasConfigured
        isShortcutCompleting = false
        self.forceShortcutStage = forceShortcutStage
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
        helpWatchTask?.cancel()
        helpWatchTask = nil
    }

    func selectStep(_ index: Int) {
        guard steps.indices.contains(index), !isWorking else { return }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
            showReadyStage = false
            showShortcutStage = false
            activeIndex = index
        }
    }

    func openShortcutSetup() {
        guard !isWorking, !isShortcutCompleting else { return }
        withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
            showReadyStage = false
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
                } else {
                    activeIndex = states.firstIndex(where: { $0 != .granted }) ?? 0
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

    func troubleshoot() {
        guard !isWorking else { return }
        let mode: HelpMode
        if states[0] != .granted {
            mode = .finderAccess
        } else if states[1] != .granted {
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
        helpWatchTask?.cancel()
        helpWatchTask = nil
        withAnimation(.easeInOut(duration: 0.26)) { helpMode = nil }
    }

    func performHelpAction() {
        guard let helpMode else { return }
        switch helpMode {
        case .finderAccess:
            Permissions.openAutomationSettings()
            startWatchingFromInlineHelp(for: .finderAccess)
        case .folderAccess:
            closeHelp()
            DispatchQueue.main.async { [weak self] in
                self?.requestFolderAccess()
            }
        case .enableExtension:
            Permissions.openExtensionSettings()
            startWatchingFromInlineHelp(for: .enableExtension)
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
        onFinish?()
    }

    private func refresh() {
        guard !isWorking, !isRefreshing, window?.isVisible == true else { return }
        isRefreshing = true
        let folders = Permissions.filesState()

        Task { [weak self] in
            async let automation = Task.detached(priority: .utility) {
                Permissions.automationState()
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

    private func apply(_ liveStates: [PermissionState], celebrate requestedStep: Int? = nil) {
        var displayed = liveStates
        if !Permissions.hasRequestedAutomation { displayed[0] = .unknown }
        if !Permissions.hasRequestedFinderExtension { displayed[2] = .unknown }

        if !hasLoadedInitialState {
            states = displayed
            activeIndex = displayed.firstIndex(where: { $0 != .granted }) ?? 0
            let allPermissionsReady = displayed.allSatisfy { $0 == .granted }
            showShortcutStage = forceShortcutStage || (allPermissionsReady && !Shortcut.hasConfigured)
            showReadyStage = allPermissionsReady && !showShortcutStage
            hasLoadedInitialState = true
            Permissions.hasRunSetup = displayed.allSatisfy { $0 == .granted }
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
        }

        states = displayed
        Permissions.hasRunSetup = displayed.allSatisfy { $0 == .granted }
        if !displayed.allSatisfy({ $0 == .granted }) { showReadyStage = false }

        guard completed != nil else { return }

        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_050_000_000)
            guard let self, !Task.isCancelled else { return }
            if isComplete {
                withAnimation(.spring(response: 0.82, dampingFraction: 0.84)) {
                    celebratingIndex = nil
                    if Shortcut.hasConfigured {
                        showReadyStage = true
                    } else {
                        showShortcutStage = true
                    }
                }
            } else if let next = states.indices.first(where: { states[$0] != .granted }) {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
                    celebratingIndex = nil
                    activeIndex = next
                }
            } else {
                celebratingIndex = nil
            }
        }
    }

    private func requestFinderAccess() {
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
    }

    private func requestFolderAccess() {
        // This is an app-owned sheet, not a macOS privacy prompt. Keeping the
        // parent floating and repeatedly re-keying it fights the sheet closing
        // animation and causes the visible pause reported after Choose.
        isWorking = true
        Permissions.requestFiles(attachedTo: window) { [weak self] state in
            guard let self else { return }
            isWorking = false
            apply([Permissions.automationState(), state, Permissions.finderExtensionState()],
                  celebrate: state == .granted ? 1 : nil)
            DispatchQueue.main.async { [weak self] in
                guard let self, window?.isVisible == true else { return }
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func requestFinderMenu() {
        if states[2] == .granted {
            Permissions.openExtensionSettings()
            return
        }
        beginSystemPresentation()
        Permissions.hasRequestedFinderExtension = true
        Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) {
                Permissions.enableFinderExtension()
            }.value
            guard let self else { return }
            restoreAfterSystemPresentation()
            isWorking = false
            apply([Permissions.automationState(), Permissions.filesState(), state],
                  celebrate: state == .granted ? 2 : nil)
            if state != .granted {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                    helpMode = .enableExtension
                }
            }
        }
    }

    private func startWatchingFromInlineHelp(for mode: HelpMode) {
        helpWatchTask?.cancel()
        helpWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled else { return }
                async let automation = Task.detached(priority: .utility) {
                    Permissions.automationState()
                }.value
                async let extensionState = Task.detached(priority: .utility) {
                    Permissions.finderExtensionState()
                }.value
                let values = await [automation, Permissions.filesState(), extensionState]
                let resolved = mode == .finderAccess
                    ? values[0] == .granted
                    : values[2] == .granted
                guard resolved else { continue }
                apply(values)
                try? await Task.sleep(nanoseconds: 780_000_000)
                guard !Task.isCancelled else { return }
                closeHelp()
                Toast.show(mode == .finderAccess ? "Finder access connected" : "Finder menu connected",
                           subtitle: mode == .finderAccess
                               ? "AirFliq can now read your current Finder selection."
                               : "Send with AirFliq is now available on right-click.",
                           kind: .success)
                return
            }
        }
    }

    private func beginSystemPresentation() {
        isWorking = true
        window?.level = .floating
        bringToFront()
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
                    } else if model.showShortcutStage {
                        ShortcutStage(model: model)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        PermissionStage(model: model)
                            .id(model.activeIndex)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
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
                .foregroundStyle(model.isComplete ? Color.airFliqGreen : .secondary)

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

            Text("7-day full trial  •  Pro $4.99 lifetime")
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
        case .finderAccess: return "Reconnect Finder access"
        case .folderAccess: return "Choose your folder boundary"
        case .enableExtension: return "Connect the Finder menu"
        case .menuMissing: return "Finder needs one refresh"
        }
    }

    private var steps: [String] {
        switch mode {
        case .finderAccess:
            return [
                "Open Automation in System Settings.",
                "Allow AirFliq to control Finder.",
                "Return here. AirFliq verifies the change automatically.",
            ]
        case .folderAccess:
            return [
                "Open the macOS folder picker.",
                "Choose only the folders AirFliq may read.",
                "Change this list whenever you want.",
            ]
        case .enableExtension:
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
        case .finderAccess: return "Open Automation Settings"
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
                    let segment = routeSegment(from: points[index], to: points[index + 1],
                                               rises: index.isMultiple(of: 2))
                    segment
                        .stroke(Color.white.opacity(0.13),
                                style: StrokeStyle(lineWidth: 1.35, lineCap: .round,
                                                   dash: [3, 7]))

                    segment
                        .trim(from: 0, to: routeIsGranted(index) ? 1 : 0)
                        .stroke(
                            LinearGradient(colors: index == 0
                                           ? [.airFliqCyan, .airFliqBlue]
                                           : index == 1
                                               ? [.airFliqBlue, .airFliqViolet]
                                               : [.airFliqViolet, .airFliqCyan],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.35, lineCap: .round)
                        )
                        .shadow(color: .airFliqBlue.opacity(0.65), radius: 7)
                        .animation(.spring(response: 0.95, dampingFraction: 0.9),
                                   value: states[index])
                }

                ForEach(0..<4, id: \.self) { index in
                    let point = points[index]
                    Button { onSelect(index) } label: {
                        FlightPermissionGlyph(
                            state: routeState(index),
                            isActive: activeIndex == index,
                            size: 32,
                            animateCompletion: celebratingIndex == index
                        )
                    }
                    .buttonStyle(.plain)
                    .position(x: point.x, y: point.y)

                    Text(routeTitle(index))
                        .font(.system(size: 10.5,
                                      weight: activeIndex == index ? .semibold : .medium))
                        .foregroundStyle(activeIndex == index ? .primary : .secondary)
                        .position(x: point.x, y: point.y + 29)
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
        ["Finder", "Folders", "Right-click", "Shortcut"][index]
    }

    private func routeState(_ index: Int) -> PermissionState {
        guard routeIsGranted(index) else { return .unknown }
        return .granted
    }

    private func routeIsGranted(_ index: Int) -> Bool {
        if index < states.count { return states[index] == .granted }
        return shortcutConfigured
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
                    }
                }
                .padding(.top, 21)
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
        if state == .granted {
            return step.id == 1 ? "Manage Folders" : "Review Access"
        }
        if state == .denied { return "Fix Access" }
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
                ? "The final connection is settling before AirFliq takes you to the ready screen."
                : "AirFliq is moving the flight path to your next setup step."
        }
        return step.detail
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

                Text("Select a file. Use your shortcut, right-click, or simply drag. The native AirDrop panel appears instantly.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)

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
                .padding(.top, 20)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var hasPlayedCompletion = false
    @State private var completionScale: CGFloat = 1

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 2

            switch state {
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
            withAnimation(.spring(response: 0.74, dampingFraction: 0.56)
                .delay(1.12)) {
                completionScale = 1
            }
        }
    }

    private func drawSuccess(context: inout GraphicsContext,
                             center: CGPoint, radius: CGFloat) {
        let segmentProgress = remap(renderedProgress, 0, 0.62)
        let fillProgress = smoothStep(remap(renderedProgress, 0.60, 0.78))
        let checkProgress = smoothStep(remap(renderedProgress, 0.72, 1))

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
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.airFliqGreen : .airFliqCyan)
                    .frame(width: 3, height: 14)
                    .offset(y: active ? -82 : -30)
                    .rotationEffect(.degrees(Double(index) * 30))
                    .opacity(active ? 0 : 0.9)
                    .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.018),
                               value: active)
            }
        }
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
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.035, green: 0.047, blue: 0.075),
                    Color(red: 0.055, green: 0.045, blue: 0.085),
                    Color(red: 0.025, green: 0.028, blue: 0.045),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)

                Circle()
                    .fill(Color.airFliqBlue.opacity(0.16 * intensity))
                    .frame(width: 360, height: 360)
                    .blur(radius: 90)
                    .offset(x: -250 + sin(time * 0.22) * 24,
                            y: -210 + cos(time * 0.18) * 18)

                Circle()
                    .fill(Color.airFliqViolet.opacity(0.14 * intensity))
                    .frame(width: 390, height: 390)
                    .blur(radius: 110)
                    .offset(x: 270 + cos(time * 0.19) * 28,
                            y: 240 + sin(time * 0.16) * 22)

                Canvas { context, size in
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
