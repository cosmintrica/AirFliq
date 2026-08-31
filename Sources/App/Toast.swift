import AppKit
import SwiftUI

/// AirFliq's transient flight-status HUD. Text determines the window height, so
/// no title or subtitle can be clipped by a fixed AppKit frame.
@MainActor
enum Toast {

    enum Kind {
        case info
        case success
        case warning

        var color: Color {
            switch self {
            case .info: return .airFliqCyan
            case .success: return .airFliqGreen
            case .warning: return .orange
            }
        }

        var symbol: String {
            switch self {
            case .info: return "sparkles"
            case .success: return "checkmark"
            case .warning: return "exclamationmark"
            }
        }
    }

    private static var window: NSWindow?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ title: String, subtitle: String? = nil, kind: Kind? = nil) {
        Task { @MainActor in
            present(title, subtitle, kind ?? inferredKind(title))
        }
    }

    private static func inferredKind(_ title: String) -> Kind {
        let value = title.lowercased()
        if value.contains("could not") || value.contains("needs") ||
            value.contains("taken") || value.contains("missing") {
            return .warning
        }
        if value.contains("ready") || value.contains("enabled") ||
            value.contains("changed") || value.contains("restarted") ||
            value.contains("unlocked") || value.contains(" is on") {
            return .success
        }
        return .info
    }

    private static func present(_ title: String, _ subtitle: String?, _ kind: Kind) {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)

        let model = ToastExperienceModel(title: title, subtitle: subtitle, kind: kind)
        let root = ToastExperienceView(model: model)
        let host = NSHostingView(rootView: root)
        host.frame.size = NSSize(width: 360, height: subtitle == nil ? 76 : 94)
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let width: CGFloat = 360
        let minimumHeight: CGFloat = subtitle == nil ? 76 : 90
        // NSHostingView can briefly report an unbounded fitting height while a
        // material-backed Text view is settling. That creates a huge transparent
        // panel whose visible card is centered halfway down the screen. Keep the
        // content-driven height, but within the real toast envelope.
        let maximumHeight: CGFloat = subtitle == nil ? 96 : 132
        let height = min(max(minimumHeight, ceil(fitting.height)), maximumHeight)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Full-screen apps and floating utility windows can sit above the
        // status-bar level. popUpMenu keeps this transient HUD visible without
        // placing it above macOS security prompts.
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        host.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: height)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        var destination = panel.frame.origin
        let pointer = NSEvent.mouseLocation
        // Follow the active app window first. Pointer-first placement made the
        // HUD jump between displays when a setting was toggled from another
        // screen, unlike a normal macOS notification.
        let targetScreen = NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSApp.windows.first(where: { $0.isVisible && $0 !== window })?.screen
            ?? NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            // visibleFrame already excludes the menu bar, notch and Dock.
            let topEdge = visible.maxY - 10
            let rightEdge = visible.maxX - 18
            destination = NSPoint(x: rightEdge - width,
                                  y: topEdge - height)
        }
        panel.setFrameOrigin(NSPoint(x: destination.x + 14, y: destination.y + 3))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        model.appear()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.48
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(destination)
        }
        window = panel

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_300_000_000)
            guard !Task.isCancelled else { return }
            model.dismiss()
            try? await Task.sleep(nanoseconds: Motion.reduceMotion ? 30_000_000 : 260_000_000)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Motion.reduceMotion ? 0 : 0.3
                context.timingFunction = Motion.easeInOut
                panel.animator().alphaValue = 0
                panel.animator().setFrameOrigin(NSPoint(x: destination.x + 16,
                                                         y: destination.y + 2))
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    if window === panel { window = nil }
                }
            })
        }
    }
}

@MainActor
private final class ToastExperienceModel: ObservableObject {
    let title: String
    let subtitle: String?
    let kind: Toast.Kind
    @Published var visible = false
    @Published var completed = false

    init(title: String, subtitle: String?, kind: Toast.Kind) {
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
    }

    func appear() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.74)) { visible = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.22)) { completed = true }
        }
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.24)) { visible = false }
    }
}

private struct ToastExperienceView: View {

    @ObservedObject var model: ToastExperienceModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(model.kind.color.opacity(0.18), lineWidth: 1)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: model.completed ? 1 : 0.04)
                    .stroke(model.kind.color,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: model.kind.color.opacity(0.45), radius: 3)
                Image(systemName: model.kind.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(model.completed ? 1 : 0.55)
                    .opacity(model.completed ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [model.kind.color.opacity(0.07),
                                                     .clear, .airFliqViolet.opacity(0.035)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.18),
                                                       model.kind.color.opacity(0.22),
                                                       .white.opacity(0.05)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.34), radius: 16, y: 8)
        }
        .padding(5)
        .scaleEffect(model.visible ? 1 : 0.88, anchor: .trailing)
        .opacity(model.visible ? 1 : 0)
        .offset(x: model.visible ? 0 : 20)
    }
}
