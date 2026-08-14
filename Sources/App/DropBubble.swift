import AppKit
import SwiftUI

/// A non-activating magnetic target. AppKit owns drag routing while SwiftUI
/// renders every visual state from one finite state machine.
final class DropBubble {

    private var panel: NSPanel?
    private var bridge: DropDestinationBridge?

    var isVisible: Bool { panel?.isVisible ?? false }
    var isCelebrating: Bool { bridge?.isCelebrating ?? false }
    var onDrop: (([URL]) -> Void)?
    var onDropCompleted: (() -> Void)?

    private static let size = NSSize(width: 236, height: 126)

    func show(near cursor: NSPoint) {
        guard panel == nil else { return }

        let size = Self.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bridge = DropDestinationBridge(frame: NSRect(origin: .zero, size: size))
        bridge.onDrop = { [weak self] urls in self?.onDrop?(urls) }
        bridge.onFinished = { [weak self] in self?.onDropCompleted?() }
        panel.contentView = bridge

        let destination = origin(for: cursor, size: size)
        panel.setFrameOrigin(NSPoint(x: destination.x + 18, y: destination.y - 12))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        bridge.model.appear()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.52
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(destination)
        }

        self.panel = panel
        self.bridge = bridge
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        self.bridge = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduceMotion ? 0 : 0.34
            context.timingFunction = Motion.easeInOut
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.origin.x + 12,
                                                     y: panel.frame.origin.y + 5))
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func origin(for cursor: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = cursor.x + 38
        var y = cursor.y + 28
        if x + size.width > bounds.maxX - 14 { x = cursor.x - size.width - 38 }
        if y + size.height > bounds.maxY - 14 { y = cursor.y - size.height - 28 }
        x = min(max(x, bounds.minX + 14), bounds.maxX - size.width - 14)
        y = min(max(y, bounds.minY + 14), bounds.maxY - size.height - 14)
        return NSPoint(x: x, y: y)
    }
}

@MainActor
private final class DropExperienceModel: ObservableObject {

    enum Phase: Equatable {
        case appearing
        case waiting
        case attracted(name: String, count: Int)
        case launching(name: String, count: Int)
        case complete(name: String, count: Int)
    }

    @Published var phase: Phase = .appearing
    @Published var entrance = false
    private var transitionTask: Task<Void, Never>?

    var isCelebrating: Bool {
        switch phase {
        case .launching, .complete: return true
        default: return false
        }
    }

    func appear() {
        phase = .appearing
        entrance = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.77)) {
                entrance = true
                phase = .waiting
            }
        }
    }

    func attract(_ urls: [URL]) {
        transitionTask?.cancel()
        let name = urls.first?.lastPathComponent ?? "File"
        withAnimation(.spring(response: 0.48, dampingFraction: 0.74)) {
            phase = .attracted(name: name, count: urls.count)
        }
    }

    func releaseAttraction() {
        guard !isCelebrating else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
            phase = .waiting
        }
    }

    func launch(_ urls: [URL], completion: @escaping @MainActor () -> Void) {
        transitionTask?.cancel()
        let name = urls.first?.lastPathComponent ?? "File"
        let count = urls.count
        withAnimation(.spring(response: 0.44, dampingFraction: 0.68)) {
            phase = .launching(name: name, count: count)
        }

        transitionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Motion.reduceMotion ? 80_000_000 : 720_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.64, dampingFraction: 0.66)) {
                phase = .complete(name: name, count: count)
            }
            try? await Task.sleep(nanoseconds: Motion.reduceMotion ? 80_000_000 : 720_000_000)
            guard !Task.isCancelled else { return }
            completion()
        }
    }
}

private final class DropDestinationBridge: NSView {

    let model = DropExperienceModel()
    var onDrop: (([URL]) -> Void)?
    var onFinished: (() -> Void)?
    var isCelebrating: Bool { model.isCelebrating }

    private let host: NSHostingView<DropExperienceView>

    override init(frame frameRect: NSRect) {
        host = NSHostingView(rootView: DropExperienceView(model: model))
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Drop files to AirFliq")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = urls(from: sender)
        guard !files.isEmpty else { return [] }
        model.attract(files)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.releaseAttraction()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = urls(from: sender)
        guard !files.isEmpty else { return false }
        model.launch(files) { [weak self] in
            self?.onDrop?(files)
            self?.onFinished?()
        }
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if !model.isCelebrating { onFinished?() }
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }
}

private struct DropExperienceView: View {

    @ObservedObject var model: DropExperienceModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(backgroundGradient)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(borderGradient, lineWidth: targeted ? 1.8 : 1)
                    }
                    .shadow(color: glowColor.opacity(targeted ? 0.46 : 0.20),
                            radius: targeted ? 28 : 16, y: 8)

                Canvas { context, size in
                    drawFlightLines(context: &context, size: size, time: time)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 15) {
                    visualMark(time: time)
                        .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(detail)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
            }
            .scaleEffect(model.entrance ? 1 : 0.84)
            .opacity(model.entrance ? 1 : 0)
        }
        .padding(8)
    }

    private var targeted: Bool {
        switch model.phase {
        case .attracted, .launching, .complete: return true
        default: return false
        }
    }

    private var glowColor: Color {
        if case .complete = model.phase { return .airFliqGreen }
        return targeted ? .airFliqCyan : .airFliqBlue
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color]
        switch model.phase {
        case .complete:
            colors = [.airFliqGreen.opacity(0.22), .airFliqBlue.opacity(0.08), .clear]
        case .attracted, .launching:
            colors = [.airFliqCyan.opacity(0.18), .airFliqViolet.opacity(0.13), .clear]
        default:
            colors = [.airFliqBlue.opacity(0.09), .airFliqViolet.opacity(0.07), .clear]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(targeted ? 0.38 : 0.17),
                                glowColor.opacity(targeted ? 0.78 : 0.22),
                                Color.white.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var title: String {
        switch model.phase {
        case .appearing, .waiting: return "Bring it here"
        case .attracted: return "Release to Fliq"
        case .launching: return "Launching"
        case .complete: return "Ready to send"
        }
    }

    private var detail: String {
        switch model.phase {
        case .appearing, .waiting: return "AirFliq is following your drag"
        case let .attracted(name, count), let .launching(name, count), let .complete(name, count):
            return count == 1 ? name : "\(count) files"
        }
    }

    @ViewBuilder
    private func visualMark(time: TimeInterval) -> some View {
        ZStack {
            Circle()
                .stroke(glowColor.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                .rotationEffect(.degrees(time * (targeted ? 62 : 18)))

            Circle()
                .fill(glowColor.opacity(targeted ? 0.18 : 0.08))
                .frame(width: targeted ? 58 : 50, height: targeted ? 58 : 50)
                .blur(radius: targeted ? 2 : 0)

            if case .complete = model.phase {
                Image(systemName: "checkmark")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Image(nsImage: AirDropIcon.appIcon(size: 96))
                    .resizable()
                    .frame(width: targeted ? 44 : 39, height: targeted ? 44 : 39)
                    .rotation3DEffect(.degrees(targeted ? 7 : 0), axis: (x: 0, y: 1, z: 0))
                    .shadow(color: glowColor.opacity(0.7), radius: targeted ? 12 : 7)
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.68), value: model.phase)
    }

    private func drawFlightLines(context: inout GraphicsContext,
                                 size: CGSize, time: TimeInterval) {
        let lineCount = targeted ? 5 : 3
        for index in 0..<lineCount {
            let y = size.height * (0.22 + CGFloat(index) * 0.13)
            var path = Path()
            path.move(to: CGPoint(x: -20, y: y))
            path.addCurve(to: CGPoint(x: size.width + 20, y: y + 10),
                          control1: CGPoint(x: size.width * 0.38,
                                            y: y + CGFloat(sin(time * 2 + Double(index))) * 10),
                          control2: CGPoint(x: size.width * 0.70,
                                            y: y - CGFloat(cos(time * 1.6 + Double(index))) * 12))
            context.stroke(path,
                           with: .linearGradient(
                            Gradient(colors: [.clear, glowColor.opacity(targeted ? 0.42 : 0.12), .clear]),
                            startPoint: CGPoint(x: 0, y: y),
                            endPoint: CGPoint(x: size.width, y: y)),
                           style: StrokeStyle(lineWidth: targeted ? 1.4 : 0.8,
                                              lineCap: .round,
                                              dash: [2, 8],
                                              dashPhase: CGFloat(-time * (targeted ? 50 : 14) - Double(index) * 6)))
        }
    }
}
