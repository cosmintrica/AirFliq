import AppKit
import SwiftUI

/// Where this macOS version keeps the Finder extension switch.
enum FinderMenuSettingsPath {
    enum Kind {
        /// macOS 15.2+: Settings opens the File Providers sheet directly.
        case fileProvidersSheet
        /// macOS 15.0-15.1: General > Login Items & Extensions > Extensions.
        case loginItems
        /// macOS 13-14: Privacy & Security > Extensions.
        case privacyExtensions
    }

    static var kind: Kind {
        if #available(macOS 15.2, *) { return .fileProvidersSheet }
        if #available(macOS 15.0, *) { return .loginItems }
        return .privacyExtensions
    }

    static var steps: [String] {
        switch kind {
        case .fileProvidersSheet:
            return ["System Settings opens the File Providers list.",
                    "Switch on AirFliq.",
                    "Click Done. This window notices instantly."]
        case .loginItems:
            return ["Open General → Login Items & Extensions.",
                    "Under Extensions, choose By App, then click ⓘ next to AirFliq.",
                    "Switch on AirFliq. This window notices instantly."]
        case .privacyExtensions:
            return ["Open Privacy & Security → Extensions.",
                    "Click Added Extensions and find AirFliq.",
                    "Tick Finder extension. This window notices instantly."]
        }
    }

    static var compactSteps: [String] {
        switch kind {
        case .fileProvidersSheet:
            return ["Find AirFliq under File Providers", "Switch it on", "Click Done"]
        case .loginItems:
            return ["Scroll down to Extensions", "By App → ⓘ next to AirFliq", "Switch on AirFliq"]
        case .privacyExtensions:
            return ["Open Added Extensions", "Find AirFliq", "Tick Finder extension"]
        }
    }
}

// MARK: - Floating coach beside System Settings

/// A small guide that docks beside System Settings while the user switches on
/// the Finder extension, then confirms the change the moment macOS reports it.
@MainActor
final class FinderMenuCoach {
    static let shared = FinderMenuCoach()

    private let model = FinderMenuCoachModel()
    private var panel: NSPanel?
    private var followTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private static let size = NSSize(width: 318, height: 258)

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(onSkip: @escaping () -> Void, onReopen: @escaping () -> Void) {
        dismissTask?.cancel()
        model.phase = .waiting
        model.onSkip = { [weak self] in
            self?.dismiss()
            onSkip()
        }
        model.onReopen = onReopen
        model.onClose = { [weak self] in self?.dismiss() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let destination = preferredOrigin(for: panel)
        if !panel.isVisible {
            panel.setFrameOrigin(NSPoint(x: destination.x + 16, y: destination.y))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            model.appear()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.reduceMotion ? 0 : 0.5
                context.timingFunction = Motion.easeOut
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(destination)
            }
        }
        startFollowing()
    }

    /// Celebrates the detected switch, then leaves on its own.
    func complete() {
        guard let panel, panel.isVisible else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            model.phase = .connected
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        followTask?.cancel()
        followTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel, panel.isVisible else { return }
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduceMotion ? 0 : 0.28
            context.timingFunction = Motion.easeInOut
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: origin.x + 12, y: origin.y))
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: FinderMenuCoachView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Follow the System Settings window for a few minutes so the guide stays
    /// beside the switch it describes, even if the user moves that window.
    private func startFollowing() {
        followTask?.cancel()
        followTask = Task { @MainActor [weak self] in
            for _ in 0..<600 {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, !Task.isCancelled, let panel = self.panel,
                      panel.isVisible else { return }
                let destination = self.preferredOrigin(for: panel)
                let current = panel.frame.origin
                guard hypot(destination.x - current.x, destination.y - current.y) > 3 else {
                    continue
                }
                self.glide(panel, to: destination)
            }
        }
    }

    private func glide(_ panel: NSPanel, to destination: NSPoint) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.42
            context.timingFunction = Motion.easeOut
            panel.animator().setFrameOrigin(destination)
        }
    }

    private func preferredOrigin(for panel: NSPanel) -> NSPoint {
        let size = panel.frame.size
        if let settings = Self.systemSettingsFrame() {
            let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? settings
            let top = min(settings.maxY - 36, visible.maxY - 12) - size.height
            let y = max(visible.minY + 12, top)
            if settings.maxX + 14 + size.width <= visible.maxX - 8 {
                return NSPoint(x: settings.maxX + 14, y: y)
            }
            if settings.minX - 14 - size.width >= visible.minX + 8 {
                return NSPoint(x: settings.minX - 14 - size.width, y: y)
            }
            // No room beside it: rest over its lower-right corner instead.
            return NSPoint(x: min(settings.maxX - size.width - 18, visible.maxX - size.width - 12),
                           y: max(visible.minY + 12, settings.minY + 18))
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20)
    }

    /// The frontmost normal System Settings window, in AppKit coordinates.
    /// Window bounds and owners are available without screen recording access.
    private static func systemSettingsFrame() -> NSRect? {
        let owners = Set(NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .map(\.processIdentifier))
        guard !owners.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for info in windows {
            guard let pid = info["kCGWindowOwnerPID"] as? Int32, owners.contains(pid),
                  (info["kCGWindowLayer"] as? Int) == 0,
                  let raw = info["kCGWindowBounds"] as? [String: Any],
                  let x = (raw["X"] as? NSNumber)?.doubleValue,
                  let y = (raw["Y"] as? NSNumber)?.doubleValue,
                  let width = (raw["Width"] as? NSNumber)?.doubleValue,
                  let height = (raw["Height"] as? NSNumber)?.doubleValue,
                  width > 320, height > 240 else { continue }
            return NSRect(x: x, y: primaryHeight - y - height, width: width, height: height)
        }
        return nil
    }
}

@MainActor
final class FinderMenuCoachModel: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case help
        case connected
    }

    @Published var phase: Phase = .waiting
    @Published var visible = false
    var onSkip: () -> Void = {}
    var onReopen: () -> Void = {}
    var onClose: () -> Void = {}

    func appear() {
        visible = false
        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.62, dampingFraction: 0.8)) { self?.visible = true }
        }
    }
}

private struct FinderMenuCoachView: View {
    @ObservedObject var model: FinderMenuCoachModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: AirDropIcon.appIcon(size: 64))
                    .resizable()
                    .frame(width: 22, height: 22)
                    .shadow(color: .airFliqBlue.opacity(0.5), radius: 6)
                Text("AIRFLIQ GUIDE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color.airFliqCyan)
                Spacer()
                Button(action: model.onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close guide")
            }

            Group {
                switch model.phase {
                case .waiting: waiting
                case .help: help
                case .connected: connected
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: 318, height: 258)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.72),
                                                      Color.airFliqViolet.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.24),
                                                        (model.phase == .connected
                                                         ? Color.airFliqGreen : .airFliqViolet).opacity(0.4),
                                                        .white.opacity(0.06)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.42), radius: 20, y: 10)
        }
        .environment(\.colorScheme, .dark)
        .scaleEffect(model.visible ? 1 : 0.94, anchor: .leading)
        .opacity(model.visible ? 1 : 0)
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Switch on AirFliq here")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.top, 12)

            TimelineView(.periodic(from: .now, by: 1.6)) { timeline in
                let step = Int(timeline.date.timeIntervalSinceReferenceDate / 1.6) % 3
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(FinderMenuSettingsPath.compactSteps.enumerated()), id: \.offset) { index, text in
                        HStack(spacing: 9) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(index == step ? Color.airFliqViolet : Color.white.opacity(0.10),
                                            in: Circle())
                                .shadow(color: index == step ? Color.airFliqViolet.opacity(0.7) : .clear,
                                        radius: 6)
                            Text(text)
                                .font(.system(size: 11.5, weight: index == step ? .semibold : .medium))
                                .foregroundStyle(index == step ? Color.primary : .secondary)
                        }
                        .animation(.easeOut(duration: 0.35), value: step)
                    }
                }
            }
            .padding(.top, 11)

            HStack(spacing: 8) {
                CoachRadar()
                    .frame(width: 18, height: 18)
                Text("Waiting for the switch…")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 13)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Can't find it?") {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { model.phase = .help }
                }
                .buttonStyle(AirFliqTextButtonStyle())
                Spacer()
                Button(action: model.onReopen) {
                    Text("Open Settings")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                }
                .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqViolet))
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Can't find AirFliq?")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.top, 12)
            Text(FinderMenuSettingsPath.kind == .fileProvidersSheet ? "AirFliq is listed under File Providers. If it is missing there, your organization may manage this Mac and block Finder extensions." : "Scroll to Extensions and switch to By App. If AirFliq is not listed, your organization may manage this Mac and block Finder extensions.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("AirFliq still works from your shortcut, the menu bar and the drag target.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Back") {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { model.phase = .waiting }
                }
                .buttonStyle(AirFliqTextButtonStyle())
                Spacer()
                Button(action: model.onSkip) {
                    Text("Skip for now")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                }
                .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqBlue))
            }
        }
    }

    private var connected: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ZStack {
                AirFliqSuccessBurst(active: model.phase == .connected)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.43, green: 1.0, blue: 0.58), .airFliqGreen],
                                         center: .center, startRadius: 0, endRadius: 30))
                    .frame(width: 58, height: 58)
                    .shadow(color: .airFliqGreen.opacity(0.6), radius: 14)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 96)
            Text("Finder menu connected")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Right-click any file and choose Send with AirFliq.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A sweeping radar: the guide is actively listening for the switch.
private struct CoachRadar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = CGFloat((time * 0.8).truncatingRemainder(dividingBy: 1))
            ZStack {
                Circle()
                    .stroke(Color.airFliqViolet.opacity(0.7 * Double(1 - wave)), lineWidth: 1.2)
                    .scaleEffect(0.35 + wave * 0.65)
                Circle()
                    .fill(Color.airFliqViolet)
                    .frame(width: 6, height: 6)
                    .shadow(color: .airFliqViolet, radius: 4)
            }
        }
    }
}

// MARK: - Animated miniature of System Settings

/// A looping miniature of the exact clicks in System Settings. When the
/// extension is connected, the loop resolves into its final, switched-on state.
struct SettingsPathIllustration: View {
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cycle: TimeInterval = 6.4

    var body: some View {
        if FinderMenuSettingsPath.kind == .fileProvidersSheet {
            FileProvidersSheetIllustration(connected: connected)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || connected)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = connected || reduceMotion
                    ? 5.0
                    : (time.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle) * 6
                canvas(phase: phase)
            }
        }
    }

    // Phase 0...6: 0-1 reach sidebar, 1-2 choose pane, 2-3 choose By App,
    // 3-4 open ⓘ, 4-5 flip the switch, 5-6 hold.
    private func canvas(phase: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let window = CGRect(x: 4, y: 10, width: size.width - 8, height: size.height - 20)
            let sidebar = CGRect(x: window.minX, y: window.minY + 22,
                                 width: 62, height: window.height - 22)
            let content = CGRect(x: sidebar.maxX + 8, y: window.minY + 26,
                                 width: window.maxX - sidebar.maxX - 16, height: window.height - 34)
            let generalRow = CGRect(x: sidebar.minX + 6, y: sidebar.minY + 40,
                                    width: sidebar.width - 12, height: 15)
            let byAppChip = CGRect(x: content.minX, y: content.minY + 44,
                                   width: 44, height: 15)
            let appRow = CGRect(x: content.minX, y: content.minY + 68,
                                width: content.width, height: 30)
            let infoButton = CGPoint(x: appRow.maxX - 42, y: appRow.midY)
            let toggleCenter = CGPoint(x: appRow.maxX - 16, y: appRow.midY)

            let cursorTargets: [CGPoint] = [
                CGPoint(x: window.midX + 30, y: window.maxY - 14),
                CGPoint(x: generalRow.midX, y: generalRow.midY),
                CGPoint(x: byAppChip.midX, y: byAppChip.midY),
                infoButton,
                toggleCenter,
                toggleCenter,
            ]
            let cursor = Self.cursorPosition(phase: phase, targets: cursorTargets)
            let paneShown = phase >= 1.35
            let byAppActive = phase >= 2.35
            let infoOpened = phase >= 3.35
            let switchProgress = connected ? 1 : Self.smooth((phase - 4.25) / 0.5)

            ZStack(alignment: .topLeading) {
                // Window chrome
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)

                HStack(spacing: 4) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.2)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 0.2, green: 0.8, blue: 0.3)).frame(width: 6, height: 6)
                }
                .position(x: window.minX + 22, y: window.minY + 11)

                // Sidebar
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .frame(width: sidebar.width - 6, height: sidebar.height - 6)
                    .position(x: sidebar.midX, y: sidebar.midY)
                ForEach(0..<5, id: \.self) { index in
                    let row = CGRect(x: sidebar.minX + 6, y: sidebar.minY + 8 + CGFloat(index) * 16,
                                     width: sidebar.width - 12, height: 12)
                    let isGeneral = index == 2
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isGeneral && phase >= 1.0 ? Color.airFliqBlue : Color.clear)
                        .frame(width: row.width, height: row.height + 3)
                        .position(x: row.midX, y: row.midY)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(isGeneral ? Color.white.opacity(0.85) : Color.white.opacity(0.22))
                            .frame(width: 7, height: 7)
                        if isGeneral {
                            Text(FinderMenuSettingsPath.kind == .privacyExtensions ? "Privacy" : "General")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize()
                        } else {
                            Capsule().fill(Color.white.opacity(0.14))
                                .frame(width: CGFloat(22 + (index * 7) % 13), height: 4)
                        }
                    }
                    .frame(width: row.width - 4, alignment: .leading)
                    .position(x: row.midX, y: row.midY)
                }

                // Pane content
                Group {
                    Text(FinderMenuSettingsPath.kind == .privacyExtensions ? "Extensions" : "Login Items & Extensions")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .position(x: content.minX + 52, y: content.minY + 6)
                        .frame(width: content.width, alignment: .leading)
                    Capsule().fill(Color.white.opacity(0.10))
                        .frame(width: content.width * 0.72, height: 4)
                        .position(x: content.minX + content.width * 0.36, y: content.minY + 21)
                    Capsule().fill(Color.white.opacity(0.07))
                        .frame(width: content.width * 0.5, height: 4)
                        .position(x: content.minX + content.width * 0.25, y: content.minY + 30)

                    // "By App" chip
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(byAppActive ? Color.airFliqBlue : Color.white.opacity(0.08))
                        .frame(width: byAppChip.width, height: byAppChip.height)
                        .position(x: byAppChip.midX, y: byAppChip.midY)
                    Text(FinderMenuSettingsPath.kind == .privacyExtensions ? "Added" : "By App")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.white.opacity(byAppActive ? 1 : 0.6))
                        .fixedSize()
                        .position(x: byAppChip.midX, y: byAppChip.midY)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 50, height: byAppChip.height)
                        .position(x: byAppChip.maxX + 30, y: byAppChip.midY)

                    // AirFliq row
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(infoOpened ? Color.airFliqViolet.opacity(0.20) : Color.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(infoOpened ? Color.airFliqViolet.opacity(0.7) : .clear, lineWidth: 1)
                        }
                        .frame(width: appRow.width, height: appRow.height)
                        .position(x: appRow.midX, y: appRow.midY)
                    Image(nsImage: AirDropIcon.appIcon(size: 48))
                        .resizable()
                        .frame(width: 17, height: 17)
                        .position(x: appRow.minX + 15, y: appRow.midY)
                    Text("AirFliq")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .position(x: appRow.minX + 45, y: appRow.midY)
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(infoOpened ? Color.airFliqCyan : .white.opacity(0.55))
                        .position(infoButton)
                    MiniSwitch(progress: switchProgress)
                        .position(toggleCenter)
                }
                .opacity(paneShown ? 1 : 0.28)

                // Cursor with click ripple
                ClickRipple(progress: Self.rippleProgress(phase: phase))
                    .frame(width: 26, height: 26)
                    .position(cursor)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .position(x: cursor.x + 4, y: cursor.y + 6)
                    .opacity(connected ? 0 : 1)
            }
        }
    }

    private static func cursorPosition(phase: Double, targets: [CGPoint]) -> CGPoint {
        let segment = min(Int(phase), targets.count - 2)
        let local = smooth((phase - Double(segment) - 0.1) / 0.75)
        let from = targets[segment]
        let to = targets[segment + 1]
        // A gentle arc, like a hand moving a mouse.
        let lift = CGFloat(sin(local * .pi)) * 8
        return CGPoint(x: from.x + (to.x - from.x) * CGFloat(local),
                       y: from.y + (to.y - from.y) * CGFloat(local) - lift)
    }

    private static func rippleProgress(phase: Double) -> Double {
        let local = phase - floor(phase)
        guard phase >= 1, phase < 5.2 else { return 1 }
        return smooth((local - 0.86) / 0.14 + 0.0) * 0 + max(0, min(1, (local - 0.86) / 0.3))
    }

    private static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
}

private struct MiniSwitch: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(progress > 0.5 ? Color.airFliqBlue : Color.white.opacity(0.18))
                .frame(width: 22, height: 13)
                .overlay {
                    Capsule().stroke(Color.airFliqCyan.opacity(0.7 * progress), lineWidth: 1)
                }
                .shadow(color: .airFliqCyan.opacity(0.7 * progress), radius: 5)
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .offset(x: 1.5 + CGFloat(progress) * 9)
        }
        .frame(width: 22, height: 13)
    }
}

private struct ClickRipple: View {
    let progress: Double

    var body: some View {
        Circle()
            .stroke(Color.airFliqCyan.opacity(0.9 * (1 - progress)), lineWidth: 1.5)
            .scaleEffect(0.3 + progress * 0.9)
            .opacity(progress >= 1 ? 0 : 1)
    }
}


/// The File Providers sheet that System Settings presents on macOS 15.2 and
/// later: the cursor switches on AirFliq, then confirms with Done.
private struct FileProvidersSheetIllustration: View {
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cycle: TimeInterval = 5.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || connected)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = connected || reduceMotion
                ? 5.0
                : (time.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle) * 6
            scene(phase: phase)
        }
    }

    // Phase 0...6: 0-1.2 reach the switch, 1.2-1.9 flip it, 2.1-3.2 reach
    // Done, 3.2-3.6 press it, then hold.
    private func scene(phase: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let window = CGRect(x: 4, y: 10, width: size.width - 8, height: size.height - 20)
            let sheet = CGRect(x: window.minX + 14, y: window.minY + 18,
                               width: window.width - 28, height: window.height - 26)
            let header = CGRect(x: sheet.minX + 8, y: sheet.minY + 8, width: sheet.width - 16, height: 40)
            let rowA = CGRect(x: sheet.minX + 8, y: header.maxY + 8, width: sheet.width - 16, height: 30)
            let rowB = CGRect(x: sheet.minX + 8, y: rowA.maxY + 6, width: sheet.width - 16, height: 26)
            let done = CGRect(x: sheet.maxX - 46, y: sheet.maxY - 24, width: 38, height: 16)
            let toggle = CGPoint(x: rowA.maxX - 18, y: rowA.midY)
            let start = CGPoint(x: sheet.minX + 30, y: sheet.maxY + 4)

            let toSwitch = smooth((phase - 0.1) / 1.0)
            let toDone = smooth((phase - 2.1) / 1.0)
            let cursor = phase < 2.1
                ? mix(start, toggle, toSwitch)
                : mix(toggle, CGPoint(x: done.midX, y: done.midY), toDone)
            let lift = CGFloat(sin((phase < 2.1 ? toSwitch : toDone) * .pi)) * 7
            let switchOn = connected ? 1 : smooth((phase - 1.3) / 0.45)
            let donePressed = connected || (phase >= 3.2 && phase < 3.6)
            let ripple = phase >= 1.2 && phase < 1.6 ? (phase - 1.2) / 0.4
                : (phase >= 3.2 && phase < 3.6 ? (phase - 3.2) / 0.4 : 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)

                HStack(spacing: 4) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.2)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 0.2, green: 0.8, blue: 0.3)).frame(width: 6, height: 6)
                }
                .position(x: window.minX + 22, y: window.minY + 11)

                // The sheet
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.17, green: 0.17, blue: 0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .frame(width: sheet.width, height: sheet.height)
                    .position(x: sheet.midX, y: sheet.midY)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: header.width, height: header.height)
                    .position(x: header.midX, y: header.midY)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .position(x: header.minX + 16, y: header.midY)
                Text("File Providers")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: header.minX + 60, y: header.minY + 12)
                Capsule().fill(Color.white.opacity(0.12))
                    .frame(width: header.width - 44, height: 3.5)
                    .position(x: header.minX + 30 + (header.width - 44) / 2, y: header.minY + 24)
                Capsule().fill(Color.white.opacity(0.08))
                    .frame(width: (header.width - 44) * 0.7, height: 3.5)
                    .position(x: header.minX + 30 + (header.width - 44) * 0.35, y: header.minY + 31)

                // AirFliq row
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(switchOn > 0.5 ? Color.airFliqBlue.opacity(0.16) : Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(connected ? Color.airFliqGreen.opacity(0.75)
                                    : Color.airFliqCyan.opacity(0.5 * switchOn), lineWidth: 1)
                    }
                    .shadow(color: connected ? Color.airFliqGreen.opacity(0.45) : .clear, radius: 8)
                    .frame(width: rowA.width, height: rowA.height)
                    .position(x: rowA.midX, y: rowA.midY)
                Image(nsImage: AirDropIcon.appIcon(size: 48))
                    .resizable()
                    .frame(width: 17, height: 17)
                    .position(x: rowA.minX + 15, y: rowA.midY)
                Text("AirFliq")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: rowA.minX + 46, y: rowA.midY)
                SheetSwitch(progress: switchOn)
                    .position(toggle)

                // Another provider, left alone
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .frame(width: rowB.width, height: rowB.height)
                    .position(x: rowB.midX, y: rowB.midY)
                Circle().fill(Color.white.opacity(0.85))
                    .frame(width: 13, height: 13)
                    .overlay(Image(systemName: "cloud.fill").font(.system(size: 6.5))
                        .foregroundStyle(Color.airFliqBlue))
                    .position(x: rowB.minX + 15, y: rowB.midY)
                Capsule().fill(Color.white.opacity(0.14))
                    .frame(width: 44, height: 4)
                    .position(x: rowB.minX + 52, y: rowB.midY)
                SheetSwitch(progress: 0)
                    .position(x: rowB.maxX - 18, y: rowB.midY)

                // Done
                Capsule()
                    .fill(Color(red: 0.16, green: 0.47, blue: 1.0).opacity(donePressed ? 0.75 : 1))
                    .frame(width: done.width, height: done.height)
                    .position(x: done.midX, y: done.midY)
                Text("Done")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: done.midX, y: done.midY)

                ClickRipple(progress: ripple)
                    .frame(width: 26, height: 26)
                    .position(x: cursor.x, y: cursor.y - lift)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .position(x: cursor.x + 4, y: cursor.y + 6 - lift)
                    .opacity(connected ? 0 : 1)
            }
        }
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }
}

private struct SheetSwitch: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(progress > 0.5 ? Color(red: 0.16, green: 0.47, blue: 1.0) : Color.white.opacity(0.2))
                .frame(width: 22, height: 13)
                .shadow(color: .airFliqCyan.opacity(0.6 * progress), radius: 5)
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .offset(x: 1.5 + CGFloat(progress) * 9)
        }
        .frame(width: 22, height: 13)
    }
}
