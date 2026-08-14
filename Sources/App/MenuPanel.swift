import AppKit
import SwiftUI

@MainActor
final class AirFliqMenuPanel {

    struct Snapshot {
        var isPro: Bool
        var sendsRemaining: Int
        var price: String
        var currentShortcut: String
        var dragEnabled: Bool
        var launchAtLogin: Bool
    }

    struct Actions {
        let send: () -> Void
        let unlock: () -> Void
        let configureShortcut: () -> Void
        let toggleDrag: () -> Bool
        let toggleLogin: () -> Bool
        let setup: () -> Void
        let about: () -> Void
        let quit: () -> Void
    }

    private let model = MenuExperienceModel()
    private var panel: NSPanel?
    private var outsideMonitor: Any?

    func toggle(from anchor: NSView, snapshot: Snapshot, actions: Actions) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(from: anchor, snapshot: snapshot, actions: actions)
        }
    }

    func hide() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        guard let panel else { return }
        self.panel = nil
        model.dismiss()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduceMotion ? 0 : 0.28
            context.timingFunction = Motion.easeInOut
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.origin.x,
                                                     y: panel.frame.origin.y + 8))
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func show(from anchor: NSView, snapshot: Snapshot, actions: Actions) {
        let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorOnScreen = anchor.window?.convertToScreen(anchorInWindow)
            ?? NSRect(x: NSScreen.main?.frame.midX ?? 720,
                      y: NSScreen.main?.frame.maxY ?? 900,
                      width: 1, height: 1)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorOnScreen) }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Fit compact displays while retaining enough room for the action rows.
        // This removes both the right-edge clipping and the oversized empty
        // surface that fixed-width variants produced.
        let width = min(CGFloat(352), max(CGFloat(300), visible.width - 36))
        model.configure(snapshot: snapshot, actions: actions) { [weak self] in self?.hide() }

        let host = NSHostingView(rootView: MenuExperienceView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 560)
        host.layoutSubtreeIfNeeded()
        let measuredHeight = ceil(host.fittingSize.height)
        // Keep the panel fitted to its actual SwiftUI content. The former fixed
        // frame left a large dead zone below the actions.
        let fallbackHeight: CGFloat = snapshot.isPro ? 378 : 440
        let height = (300...520).contains(measuredHeight) ? measuredHeight : fallbackHeight
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // A menu-bar app is often not the active application when its status
        // item is clicked. Hiding on deactivate therefore made this panel order
        // out in the same frame in which it appeared.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        host.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        // macOS menus visually hang from the right side of their status item.
        // Clamp on every edge so the full glass surface always remains visible,
        // including on scaled, notched and vertically-arranged displays.
        let preferredX = anchorOnScreen.maxX - width + 24
        let x = min(max(preferredX, visible.minX + 18),
                    visible.maxX - width - 18)
        let screenTop = (screen?.frame.maxY ?? visible.maxY)
            - max(NSStatusBar.system.thickness, screen?.safeAreaInsets.top ?? 0)
        let preferredY = anchorOnScreen.minY - height - 7
        let y = min(max(preferredY, visible.minY + 18), screenTop - height - 8)
        let destination = NSPoint(x: x, y: y)
        panel.setFrameOrigin(NSPoint(x: destination.x, y: destination.y + 12))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        model.appear()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.46
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(destination)
        }

        self.panel = panel
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }
    }
}

@MainActor
private final class MenuExperienceModel: ObservableObject {
    @Published var snapshot = AirFliqMenuPanel.Snapshot(isPro: false, sendsRemaining: 50,
                                                        price: "$4.99", currentShortcut: "⌃⌥A",
                                                        dragEnabled: false, launchAtLogin: false)
    @Published var visible = false
    var actions: AirFliqMenuPanel.Actions?
    var close: (() -> Void)?

    func configure(snapshot: AirFliqMenuPanel.Snapshot,
                   actions: AirFliqMenuPanel.Actions,
                   close: @escaping () -> Void) {
        self.snapshot = snapshot
        self.actions = actions
        self.close = close
    }

    func appear() {
        visible = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { visible = true }
        }
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.22)) { visible = false }
    }

    func send() { close?(); actions?.send() }
    func unlock() { close?(); actions?.unlock() }
    func setup() { close?(); actions?.setup() }
    func configureShortcut() { close?(); actions?.configureShortcut() }
    func about() { close?(); actions?.about() }
    func quit() { close?(); actions?.quit() }

    func toggleDrag() {
        let enabled = actions?.toggleDrag() ?? snapshot.dragEnabled
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            snapshot.dragEnabled = enabled
        }
    }

    func toggleLogin() {
        let enabled = actions?.toggleLogin() ?? snapshot.launchAtLogin
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            snapshot.launchAtLogin = enabled
        }
    }
}

private struct MenuExperienceView: View {

    @ObservedObject var model: MenuExperienceModel

    var body: some View {
        ZStack {
            AirFliqFlightField(intensity: 0.72)

            VStack(spacing: 12) {
                header
                sendButton

                if !model.snapshot.isPro { proCard }

                VStack(spacing: 7) {
                    MenuToggleRow(symbol: "cursorarrow.motionlines",
                                  title: "Drag target",
                                  detail: "Meet every file beside your cursor",
                                  isOn: model.snapshot.dragEnabled,
                                  action: model.toggleDrag)
                    MenuToggleRow(symbol: "power",
                                  title: "Launch at login",
                                  detail: "Keep AirFliq ready",
                                  isOn: model.snapshot.launchAtLogin,
                                  action: model.toggleLogin)
                }

                shortcutPicker

                HStack(spacing: 8) {
                    MenuCompactButton(symbol: "gearshape", title: "Setup", action: model.setup)
                    MenuCompactButton(symbol: "info.circle", title: "About", action: model.about)
                    MenuCompactButton(symbol: "power", title: "Quit", action: model.quit)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.22),
                                                .airFliqBlue.opacity(0.22),
                                                .white.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 30, y: 12)
        .padding(7)
        .scaleEffect(model.visible ? 1 : 0.92, anchor: .top)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AirDropIcon.appIcon(size: 80))
                .resizable()
                .frame(width: 36, height: 36)
                .shadow(color: .airFliqBlue.opacity(0.55), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("AIRFLIQ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.4)
                Text(model.snapshot.isPro
                     ? "Pro  •  Unlimited"
                     : "\(model.snapshot.sendsRemaining) free sends remaining")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.snapshot.isPro ? Color.airFliqGreen : .secondary)
            }
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var sendButton: some View {
        Button(action: model.send) {
            HStack(spacing: 11) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send Finder selection")
                        .font(.system(size: 13, weight: .bold))
                    Text("Open native AirDrop now")
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqBlue))
    }

    private var proCard: some View {
        Button(action: model.unlock) {
            HStack(spacing: 11) {
                Image(systemName: "infinity")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.airFliqViolet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime Pro")
                        .font(.system(size: 12, weight: .bold))
                    Text("Unlimited sends for \(model.snapshot.price)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("UNLOCK")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color.airFliqCyan)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.airFliqViolet.opacity(0.09), in:
                            RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.airFliqViolet.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var shortcutPicker: some View {
        Button(action: model.configureShortcut) {
            HStack(spacing: 11) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.airFliqCyan)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Global shortcut")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Presets or any custom combination")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)
                Spacer()
                Text(model.snapshot.currentShortcut)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.airFliqBlue.opacity(0.18), in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: 47)
            .background(Color.white.opacity(0.045), in:
                            RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MenuToggleRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.airFliqCyan : .secondary)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Color.airFliqBlue : Color.white.opacity(0.10))
                        .frame(width: 34, height: 18)
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                        .shadow(color: isOn ? .airFliqCyan.opacity(0.7) : .clear, radius: 5)
                }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: 43)
            .background(Color.white.opacity(hovered ? 0.085 : 0.045), in:
                            RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(hovered ? 0.15 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(.easeOut(duration: 0.2)) { hovered = value } }
    }
}

private struct MenuCompactButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.white.opacity(hovered ? 0.09 : 0.045), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(hovered ? 0.15 : 0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { value in withAnimation(.easeOut(duration: 0.2)) { hovered = value } }
    }
}
