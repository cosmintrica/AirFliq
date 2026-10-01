import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// A non-activating magnetic target. AppKit owns drag routing while SwiftUI
/// renders every visual state from one finite state machine.
@MainActor
final class DropBubble {

    private var panel: NSPanel?
    private var bridge: DropDestinationBridge?

    var isVisible: Bool { panel?.isVisible ?? false }
    var isCelebrating: Bool { bridge?.isCelebrating ?? false }
    var onDrop: (([URL]) -> Void)?
    var onDropCompleted: (() -> Void)?

    /// The visible glass card. The panel adds only enough transparent room
    /// for the glow; the release flight runs in its own click-through overlay,
    /// so the drop target never blocks drops on windows behind it.
    static let cardSize = NSSize(width: 236, height: 126)
    static let margin = NSSize(width: 14, height: 14)
    static var panelSize: NSSize {
        NSSize(width: cardSize.width + margin.width * 2,
               height: cardSize.height + margin.height * 2)
    }

    func show(near cursor: NSPoint) {
        guard panel == nil else { return }

        let size = Self.panelSize
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
        bridge.onLaunch = { [weak self] urls in self?.fliq(urls) ?? false }
        panel.contentView = bridge

        let destination = origin(for: cursor)
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

    func showForCapture(near cursor: NSPoint, complete: Bool) {
        show(near: cursor)
        panel?.sharingType = .readOnly
        panel?.level = .normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.bridge?.model.prepareCapture(complete: complete)
        }
    }

    /// Capture-only: replays attraction and release without a real drag.
    func showLaunchForCapture(near cursor: NSPoint) {
        showForCapture(near: cursor, complete: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            let file = [URL(fileURLWithPath: "/tmp/Launch brief.pdf")]
            if self?.fliq(file) != true {
                self?.bridge?.model.launch(file) {}
            }
        }
    }

    private var retiredPanel: NSPanel?

    /// The signature release: the card folds into a paper plane and flies
    /// off the screen while AirDrop opens. Reduce Motion keeps the calm
    /// in-card confirmation instead.
    private func fliq(_ urls: [URL]) -> Bool {
        // A send that is blocked (today's free sends are used and the offer
        // opens instead) must not look sent: just step aside.
        guard Monetization.shared.canSend else {
            hide()
            DispatchQueue.main.async { [weak self] in self?.onDropCompleted?() }
            return true
        }
        guard !Motion.reduceMotion, let panel, let bridge,
              let screen = panel.screen ?? NSScreen.main else { return false }
        let glass = NSRect(x: panel.frame.minX + Self.margin.width + 8,
                           y: panel.frame.minY + Self.margin.height + 8,
                           width: Self.cardSize.width - 16,
                           height: Self.cardSize.height - 16)
        FliqFlight.launch(card: glass, icon: bridge.model.fileIcon, on: screen)

        // The overlay draws an identical card on top. Retire the drop target
        // on the next turn, after AppKit has finished this drag callback.
        self.panel = nil
        self.bridge = nil
        retiredPanel = panel
        DispatchQueue.main.async { [weak self] in
            // Dissolve the drop target while the overlay's card starts to fold.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in panel.orderOut(nil) }
            })
            self?.onDropCompleted?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.retiredPanel === panel { self?.retiredPanel = nil }
            }
        }
        return true
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

    /// Places the glass card beside the cursor (never under it), then returns
    /// the panel origin that surrounds that card with its effect margin.
    private func origin(for cursor: NSPoint) -> NSPoint {
        let card = Self.cardSize
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = cursor.x + 38
        var y = cursor.y + 28
        if x + card.width > bounds.maxX - 14 { x = cursor.x - card.width - 38 }
        if y + card.height > bounds.maxY - 14 { y = cursor.y - card.height - 28 }
        x = min(max(x, bounds.minX + 14), bounds.maxX - card.width - 14)
        y = min(max(y, bounds.minY + 14), bounds.maxY - card.height - 14)
        return NSPoint(x: x - Self.margin.width, y: y - Self.margin.height)
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
    /// Pointer position over the card, normalized to -1...1 on both axes.
    @Published var pointer: CGPoint = .zero
    @Published var fileIcon: NSImage?
    private(set) var appearedAt = Date()
    private(set) var launchedAt: Date?
    private(set) var completedAt: Date?
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
        appearedAt = Date()
        launchedAt = nil
        completedAt = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.68)) {
                entrance = true
                phase = .waiting
            }
        }
    }

    func prepareCapture(complete: Bool) {
        transitionTask?.cancel()
        entrance = true
        fileIcon = Self.icon(for: [URL(fileURLWithPath: "/tmp/Launch brief.pdf")])
        if complete {
            launchedAt = Date().addingTimeInterval(-2)
            completedAt = Date().addingTimeInterval(-1)
            phase = .complete(name: "Launch brief.pdf", count: 1)
        } else {
            pointer = CGPoint(x: -0.25, y: 0.1)
            phase = .attracted(name: "Launch brief.pdf", count: 1)
        }
    }

    func attract(_ urls: [URL]) {
        transitionTask?.cancel()
        let name = urls.first?.lastPathComponent ?? "File"
        fileIcon = Self.icon(for: urls)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.66)) {
            phase = .attracted(name: name, count: urls.count)
        }
    }

    func track(_ normalized: CGPoint) {
        guard case .attracted = phase else { return }
        pointer = normalized
    }

    func releaseAttraction() {
        guard !isCelebrating else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
            phase = .waiting
            pointer = .zero
        }
    }

    func launch(_ urls: [URL], completion: @escaping @MainActor () -> Void) {
        transitionTask?.cancel()
        let name = urls.first?.lastPathComponent ?? "File"
        let count = urls.count
        if fileIcon == nil { fileIcon = Self.icon(for: urls) }
        launchedAt = Date()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) {
            phase = .launching(name: name, count: count)
            pointer = .zero
        }

        transitionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Motion.reduceMotion ? 80_000_000 : 720_000_000)
            guard let self, !Task.isCancelled else { return }
            completedAt = Date()
            withAnimation(.spring(response: 0.56, dampingFraction: 0.64)) {
                phase = .complete(name: name, count: count)
            }
            try? await Task.sleep(nanoseconds: Motion.reduceMotion ? 80_000_000 : 820_000_000)
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    /// The dragged item's type icon. Using the content type needs no file
    /// access, so it works before the sandbox grants anything.
    private static func icon(for urls: [URL]) -> NSImage? {
        guard let first = urls.first else { return nil }
        if first.hasDirectoryPath { return NSWorkspace.shared.icon(for: .folder) }
        let type = UTType(filenameExtension: first.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

private final class DropDestinationBridge: NSView {

    let model = DropExperienceModel()
    var onDrop: (([URL]) -> Void)?
    var onFinished: (() -> Void)?
    var onLaunch: (([URL]) -> Bool)?
    var isCelebrating: Bool { model.isCelebrating }

    private let host: NSHostingView<DropExperienceView>

    /// The glass card inside the panel, in this view's coordinates.
    private var cardRect: NSRect {
        NSRect(x: DropBubble.margin.width, y: DropBubble.margin.height,
               width: DropBubble.cardSize.width, height: DropBubble.cardSize.height)
    }

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
        let local = convert(point, from: superview)
        // The glass plus its thin glow margin: a small magnetic edge.
        return cardRect.insetBy(dx: -DropBubble.margin.width,
                                dy: -DropBubble.margin.height).contains(local) ? self : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = urls(from: sender)
        guard !files.isEmpty else { return [] }
        model.attract(files)
        model.track(normalized(sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        model.track(normalized(sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.releaseAttraction()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = urls(from: sender)
        guard !files.isEmpty else { return false }

        // Start the share while AppKit's drag grant is still alive. Waiting for
        // the completion animation here can make sandboxed URLs lose their
        // transient access and leave NSSharingService resolving them for tens
        // of seconds. The visual confirmation now runs alongside the native
        // AirDrop handoff instead of blocking it.
        onDrop?(files)
        if onLaunch?(files) == true { return true }
        model.launch(files) { [weak self] in
            self?.onFinished?()
        }
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if !model.isCelebrating { onFinished?() }
    }

    private func normalized(_ sender: NSDraggingInfo) -> CGPoint {
        let location = convert(sender.draggingLocation, from: nil)
        let x = (location.x - cardRect.midX) / (cardRect.width / 2)
        // AppKit's y grows upward; SwiftUI's grows downward.
        let y = (cardRect.midY - location.y) / (cardRect.height / 2)
        return CGPoint(x: min(1, max(-1, x)), y: min(1, max(-1, y)))
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }
}

private struct DropExperienceView: View {

    @ObservedObject var model: DropExperienceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let panel = DropBubble.panelSize
    /// The visible glass, inset from the card frame like the original design.
    private var glass: CGRect {
        CGRect(x: DropBubble.margin.width + 8, y: DropBubble.margin.height + 8,
               width: DropBubble.cardSize.width - 16, height: DropBubble.cardSize.height - 16)
    }
    private var iconCenter: CGPoint { CGPoint(x: glass.minX + 12 + 33, y: glass.midY) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let now = timeline.date
            let time = now.timeIntervalSinceReferenceDate
            let sinceLaunch = model.launchedAt.map { now.timeIntervalSince($0) } ?? -1
            let sinceComplete = model.completedAt.map { now.timeIntervalSince($0) } ?? -1
            let sinceAppear = now.timeIntervalSince(model.appearedAt)

            ZStack(alignment: .topLeading) {
                card(time: time, sinceLaunch: sinceLaunch, sinceComplete: sinceComplete,
                     sinceAppear: sinceAppear)
                    .frame(width: glass.width, height: glass.height)
                    .rotation3DEffect(.degrees(targeted ? Double(model.pointer.x) * 7 : 0),
                                      axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .rotation3DEffect(.degrees(targeted ? Double(-model.pointer.y) * 6 : 0),
                                      axis: (x: 1, y: 0, z: 0), perspective: 0.7)
                    .scaleEffect(model.entrance ? cardScale(sinceLaunch: sinceLaunch) : 0.72)
                    .opacity(model.entrance ? 1 : 0)
                    .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.pointer)
                    .position(x: glass.midX, y: glass.midY)

                if !reduceMotion && sinceLaunch >= 0 && sinceLaunch < 1.4 {
                    LaunchEffects(origin: iconCenter, elapsed: sinceLaunch, panel: panel)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        }
    }

    private var targeted: Bool {
        switch model.phase {
        case .attracted, .launching, .complete: return true
        default: return false
        }
    }

    private var attracted: Bool {
        if case .attracted = model.phase { return true }
        return false
    }

    private var isComplete: Bool {
        if case .complete = model.phase { return true }
        return false
    }

    private var glowColor: Color {
        if isComplete { return .airFliqGreen }
        return targeted ? .airFliqCyan : .airFliqBlue
    }

    /// A squash on release, then a relieved overshoot as the file leaves.
    private func cardScale(sinceLaunch: TimeInterval) -> CGFloat {
        if attracted { return 1.045 }
        guard sinceLaunch >= 0, !reduceMotion else { return 1 }
        if sinceLaunch < 0.09 { return 1.045 - CGFloat(sinceLaunch / 0.09) * 0.075 }
        let t = min(1, (sinceLaunch - 0.09) / 0.55)
        return 0.97 + 0.03 * CGFloat(1 - pow(1 - t, 3)) + CGFloat(sin(t * .pi)) * 0.035
    }

    @ViewBuilder
    private func card(time: TimeInterval, sinceLaunch: TimeInterval,
                      sinceComplete: TimeInterval, sinceAppear: TimeInterval) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(backgroundGradient) }
                .overlay {
                    // Light that follows the file across the glass.
                    GeometryReader { proxy in
                        let x = proxy.size.width * (0.5 + model.pointer.x * 0.5)
                        let y = proxy.size.height * (0.5 + model.pointer.y * 0.5)
                        RadialGradient(colors: [Color.airFliqCyan.opacity(attracted ? 0.30 : 0), .clear],
                                       center: UnitPoint(x: x / max(proxy.size.width, 1),
                                                         y: y / max(proxy.size.height, 1)),
                                       startRadius: 0, endRadius: 130)
                    }
                    .clipShape(shape)
                    .animation(.easeOut(duration: 0.25), value: attracted)
                }
                .overlay {
                    if targeted && !isComplete {
                        shape.strokeBorder(
                            AngularGradient(colors: [.airFliqCyan, .airFliqViolet, .airFliqBlue,
                                                     .white.opacity(0.9), .airFliqCyan],
                                            center: .center,
                                            angle: .degrees(time * 110)),
                            lineWidth: 1.8)
                            .shadow(color: .airFliqCyan.opacity(0.55), radius: 8)
                    } else {
                        shape.strokeBorder(borderGradient, lineWidth: isComplete ? 1.6 : 1)
                    }
                }
                .shadow(color: glowColor.opacity(targeted ? 0.45 : 0.18),
                        radius: targeted ? 22 : 12, y: 6)

            Canvas { context, size in
                drawFlightLines(context: &context, size: size, time: time)
                if attracted && !reduceMotion {
                    drawGravityWell(context: &context, size: size, time: time)
                }
            }
            .clipShape(shape)

            if !reduceMotion && sinceLaunch >= 0.06 && sinceLaunch < 0.7 {
                LightSweep(progress: (sinceLaunch - 0.06) / 0.55)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 15) {
                visualMark(time: time, sinceLaunch: sinceLaunch,
                           sinceComplete: sinceComplete, sinceAppear: sinceAppear)
                    .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.22), value: title)
            }
            .padding(.horizontal, 12)
        }
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color]
        switch model.phase {
        case .complete:
            colors = [.airFliqGreen.opacity(0.24), .airFliqBlue.opacity(0.08), .clear]
        case .attracted, .launching:
            colors = [.airFliqCyan.opacity(0.20), .airFliqViolet.opacity(0.15), .clear]
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
        case .launching: return "Fliq!"
        case .complete: return "Ready to send"
        }
    }

    private var detail: String {
        switch model.phase {
        case .appearing, .waiting: return "AirFliq is following your drag"
        case .complete(_, let count):
            return count == 1 ? "AirDrop is opening" : "\(count) files, AirDrop is opening"
        case let .attracted(name, count), let .launching(name, count):
            return count == 1 ? name : "\(count) files"
        }
    }

    @ViewBuilder
    private func visualMark(time: TimeInterval, sinceLaunch: TimeInterval,
                            sinceComplete: TimeInterval, sinceAppear: TimeInterval) -> some View {
        let docking = attracted
        let launching = sinceLaunch >= 0 && !isComplete
        ZStack {
            // Entrance ripple.
            if !reduceMotion && sinceAppear < 0.9 {
                let t = sinceAppear / 0.9
                Circle()
                    .stroke(Color.airFliqCyan.opacity(0.65 * (1 - t)), lineWidth: 1.4)
                    .scaleEffect(0.7 + CGFloat(t) * 0.9)
            }

            Circle()
                .stroke(glowColor.opacity(0.26),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                .rotationEffect(.degrees(time * (targeted ? 90 : 18)))

            Circle()
                .fill(glowColor.opacity(targeted ? 0.20 : 0.08))
                .frame(width: targeted ? 60 : 50, height: targeted ? 60 : 50)
                .blur(radius: targeted ? 2 : 0)

            if isComplete {
                CompletionCheck(progress: sinceComplete < 0 ? 1 : min(1, sinceComplete / 0.42))
                    .frame(width: 50, height: 50)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                // The dragged file docks beside the AirFliq icon, then is
                // swallowed by it at the moment of release.
                if let icon = model.fileIcon, docking || launching {
                    let swallow = launching ? min(1, max(0, sinceLaunch / 0.22)) : 0
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .rotationEffect(.degrees(-12 * (1 - swallow) + sin(time * 3) * 2 * (1 - swallow)))
                        .offset(x: -24 * CGFloat(1 - swallow),
                                y: 8 * CGFloat(1 - swallow) + CGFloat(sin(time * 2.4)) * 1.5 * CGFloat(1 - swallow))
                        .scaleEffect(1 - 0.75 * CGFloat(swallow))
                        .opacity(1 - swallow)
                        .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity))
                }

                Image(nsImage: AirDropIcon.appIcon(size: 96))
                    .resizable()
                    .frame(width: targeted ? 44 : 39, height: targeted ? 44 : 39)
                    .rotation3DEffect(.degrees(targeted ? 7 : 0), axis: (x: 0, y: 1, z: 0))
                    .shadow(color: glowColor.opacity(0.7), radius: targeted ? 12 : 7)
                    .offset(x: docking ? 6 : 0,
                            y: targeted ? 0 : CGFloat(sin(time * 1.6)) * 1.5)
                    .scaleEffect(launching ? 1 + 0.18 * CGFloat(sin(min(1, sinceLaunch / 0.35) * .pi)) : 1)
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

    /// Streaks pulled inward toward the icon: the target is a gravity well.
    private func drawGravityWell(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: 12 + 33, y: size.height / 2)
        for index in 0..<12 {
            let angle = Double(index) / 12 * .pi * 2 + 0.3
            let cycle = (time * 1.1 + Double(index) * 0.37).truncatingRemainder(dividingBy: 1)
            let distance = CGFloat(1 - cycle) * 150 + 22
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let head = CGPoint(x: center.x + direction.x * distance,
                               y: center.y + direction.y * distance * 0.7)
            let tail = CGPoint(x: center.x + direction.x * (distance + 16),
                               y: center.y + direction.y * (distance + 16) * 0.7)
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            let alpha = min(1, Double(distance - 22) / 40) * 0.55 * cycle.squareRootClamped
            context.stroke(streak, with: .color(Color.airFliqCyan.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

private extension Double {
    var squareRootClamped: Double { max(0, self).squareRoot() }
}

/// Everything that leaves the card at the moment of release: a shockwave,
/// sparks, and a paper plane that flies off along a dashed route.
private struct LaunchEffects: View {
    let origin: CGPoint
    let elapsed: TimeInterval
    let panel: NSSize

    var body: some View {
        Canvas { context, _ in
            // Shockwave
            if elapsed < 0.65 {
                let t = elapsed / 0.65
                let eased = 1 - pow(1 - t, 3)
                let radius = 22 + CGFloat(eased) * 84
                context.stroke(Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius,
                                                      width: radius * 2, height: radius * 2)),
                               with: .color(Color.airFliqCyan.opacity(0.85 * (1 - t))),
                               lineWidth: 2.2 * CGFloat(1 - t) + 0.4)
            }

            // Sparks
            if elapsed < 0.95 {
                let t = elapsed / 0.95
                let eased = 1 - pow(1 - t, 3)
                let colors: [Color] = [.airFliqCyan, .airFliqBlue, .airFliqViolet, .white, .airFliqGreen]
                for index in 0..<26 {
                    let seed = Double(index) * 12.9898
                    let jitter = sin(seed) * 43758.5453
                    let random = jitter - floor(jitter)
                    let angle = Double(index) / 26 * .pi * 2 + random * 0.4
                    let speed = 58 + random * 70
                    let distance = CGFloat(eased * speed)
                    let point = CGPoint(x: origin.x + CGFloat(cos(angle)) * distance,
                                        y: origin.y + CGFloat(sin(angle)) * distance * 0.85)
                    let side = CGFloat(1.6 + random * 2.2) * CGFloat(1 - t * 0.6)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                                        width: side, height: side)),
                                 with: .color(colors[index % colors.count].opacity(1 - t)))
                }
            }

            // Paper plane with a dashed route behind it
            if elapsed > 0.05 && elapsed < 0.9 {
                let t = min(1, (elapsed - 0.05) / 0.72)
                let accelerate = t * t
                let start = origin
                // Up out of the icon first, then away over the top of the
                // card, so the plane never crosses the title.
                let control = CGPoint(x: origin.x + 36, y: origin.y - 104)
                let end = CGPoint(x: panel.width + 30, y: 2)
                func point(_ u: Double) -> CGPoint {
                    let a = 1 - u
                    return CGPoint(
                        x: CGFloat(a * a) * start.x + CGFloat(2 * a * u) * control.x + CGFloat(u * u) * end.x,
                        y: CGFloat(a * a) * start.y + CGFloat(2 * a * u) * control.y + CGFloat(u * u) * end.y)
                }
                var trail = Path()
                let tailStart = max(0, accelerate - 0.45)
                trail.move(to: point(tailStart))
                for step in 1...16 {
                    trail.addLine(to: point(tailStart + (accelerate - tailStart) * Double(step) / 16))
                }
                context.stroke(trail,
                               with: .linearGradient(Gradient(colors: [.clear, Color.airFliqCyan.opacity(0.8)]),
                                                     startPoint: point(tailStart),
                                                     endPoint: point(accelerate)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5]))

                let here = point(accelerate)
                let ahead = point(min(1, accelerate + 0.02))
                let heading = atan2(ahead.y - here.y, ahead.x - here.x)
                var plane = context
                plane.translateBy(x: here.x, y: here.y)
                plane.rotate(by: .radians(Double(heading) + .pi / 4))
                plane.opacity = t > 0.8 ? (1 - t) / 0.2 : 1
                var symbol = context.resolve(Image(systemName: "paperplane.fill"))
                symbol.shading = .color(.white)
                plane.addFilter(.shadow(color: Color.airFliqCyan.opacity(0.9), radius: 6))
                plane.draw(symbol, in: CGRect(x: -9, y: -9, width: 18, height: 18))
            }
        }
        .frame(width: panel.width, height: panel.height)
        .foregroundStyle(.white)
    }
}

/// A band of light that crosses the glass as the file launches.
private struct LightSweep: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.32), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70, height: proxy.size.height * 1.8)
                .rotationEffect(.degrees(18))
                .offset(x: -90 + (width + 180) * CGFloat(min(1, max(0, progress))),
                        y: -proxy.size.height * 0.4)
        }
    }
}

/// The success mark: a green disc that pops in while the check draws itself.
private struct CompletionCheck: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let pop = progress < 0.5 ? progress / 0.5 : 1
            let eased = 1 - pow(1 - pop, 3)
            let overshoot = pop < 1 ? 1 + sin(pop * .pi) * 0.12 : 1
            let radius = min(size.width, size.height) / 2 * CGFloat(eased * overshoot)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 0.43, green: 1.0, blue: 0.58),
                                                                 .airFliqGreen]),
                                               center: center, startRadius: 0, endRadius: max(radius, 1)))
            let draw = max(0, min(1, (progress - 0.35) / 0.65))
            guard draw > 0 else { return }
            let r = min(size.width, size.height) / 2
            let points = [CGPoint(x: center.x - r * 0.42, y: center.y + r * 0.02),
                          CGPoint(x: center.x - r * 0.12, y: center.y + r * 0.30),
                          CGPoint(x: center.x + r * 0.45, y: center.y - r * 0.34)]
            let first = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
            let second = hypot(points[2].x - points[1].x, points[2].y - points[1].y)
            let target = (first + second) * CGFloat(draw)
            var check = Path()
            check.move(to: points[0])
            if target <= first {
                let u = target / first
                check.addLine(to: CGPoint(x: points[0].x + (points[1].x - points[0].x) * u,
                                          y: points[0].y + (points[1].y - points[0].y) * u))
            } else {
                check.addLine(to: points[1])
                let u = min(1, (target - first) / second)
                check.addLine(to: CGPoint(x: points[1].x + (points[2].x - points[1].x) * u,
                                          y: points[1].y + (points[2].y - points[1].y) * u))
            }
            context.stroke(check, with: .color(.white),
                           style: StrokeStyle(lineWidth: max(2.4, r * 0.15), lineCap: .round, lineJoin: .round))
        }
        .shadow(color: .airFliqGreen.opacity(0.7), radius: 12)
    }
}

// MARK: - Fliq: the card folds into a paper plane and leaves the screen

/// A click-through overlay that owns the release moment. Everything runs on
/// Core Animation, so the fold and the flight stay smooth at the display's
/// full refresh rate: the card's outline morphs into a paper plane, a flash
/// and a burst of sparks fire, and the plane shoots off to the right along a
/// fresh, slightly curved route, leaving a dashed contrail and sparks.
@MainActor
enum FliqFlight {
    static let duration: TimeInterval = 1.35
    private static var panels: [NSPanel] = []
#if DEBUG
    /// Debug builds can replay the release slowly for frame-by-frame review.
    static let timeScale = Double(ProcessInfo.processInfo.environment["AIRFLIQ_FLIQ_SLOWMO"] ?? "") ?? 1
#else
    static let timeScale = 1.0
#endif

    static func launch(card: NSRect, icon: NSImage?, on screen: NSScreen) {
        let frame = screen.frame
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.setFrame(frame, display: false)

        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let root = CALayer()
        root.frame = host.bounds
        root.speed = Float(timeScale)
        host.layer = root
        host.wantsLayer = true
        panel.contentView = host

        let local = NSRect(x: card.minX - frame.minX, y: card.minY - frame.minY,
                           width: card.width, height: card.height)
        FliqChoreography(root: root, card: local, canvas: frame.size,
                         scale: screen.backingScaleFactor).run()
        panel.orderFrontRegardless()
        panels.append(panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration / timeScale) {
            panel.orderOut(nil)
            panels.removeAll { $0 === panel }
        }
    }
}

@MainActor
private struct FliqChoreography {
    let root: CALayer
    let card: NSRect
    let canvas: NSSize
    let scale: CGFloat

    // Seconds from release.
    let foldStart: CFTimeInterval = 0.03
    let foldLength: CFTimeInterval = 0.27
    let launchAt: CFTimeInterval = 0.31
    let flightLength: CFTimeInterval = 0.62
    private static let planeSize = CGSize(width: 124, height: 76)

    func run() {
        // Local time, so the debug slow-motion speed applies to every delay.
        let now = root.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let size = card.size
        let center = CGPoint(x: card.midX, y: card.midY)
        let cardPath = Self.cardPath(size: size, radius: 26)
        let planePath = Self.planePath(size: size)
        let foldTiming = CAMediaTimingFunction(controlPoints: 0.6, 0.0, 0.3, 1.0)

        // The flyer follows the route and turns with it; the body inside it
        // carries the squash, the pop and the speed stretch.
        let flyer = CALayer()
        flyer.bounds = CGRect(origin: .zero, size: size)
        flyer.position = center
        root.addSublayer(flyer)

        let body = CALayer()
        body.frame = flyer.bounds
        flyer.addSublayer(body)

        let glow = CAShapeLayer()
        glow.frame = body.bounds
        glow.path = cardPath
        glow.fillColor = NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 1).cgColor
        glow.shadowColor = glow.fillColor
        glow.shadowRadius = 16
        glow.shadowOpacity = 1
        glow.shadowOffset = .zero
        glow.opacity = 0
        body.addSublayer(glow)

        let fill = CAGradientLayer()
        fill.frame = body.bounds
        fill.startPoint = CGPoint(x: 0.5, y: 1)
        fill.endPoint = CGPoint(x: 0.5, y: 0)
        let darkTop = NSColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 0.92).cgColor
        let darkBottom = NSColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 0.92).cgColor
        let paperColors: [CGColor] = [
            NSColor.white.cgColor,
            NSColor(red: 0.80, green: 0.95, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.10, green: 0.48, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.49, green: 0.28, blue: 1.0, alpha: 1).cgColor,
        ]
        fill.colors = [darkTop, darkTop, darkBottom, darkBottom, darkBottom]
        fill.locations = [0, 0.49, 0.51, 0.8, 1]
        let mask = CAShapeLayer()
        mask.frame = fill.bounds
        mask.path = cardPath
        fill.mask = mask
        body.addSublayer(fill)

        let rim = CAShapeLayer()
        rim.frame = body.bounds
        rim.path = cardPath
        rim.fillColor = nil
        rim.strokeColor = NSColor(red: 0.55, green: 0.92, blue: 1.0, alpha: 1).cgColor
        rim.lineWidth = 1.6
        body.addSublayer(rim)

        let crease = CAShapeLayer()
        crease.frame = body.bounds
        crease.path = Self.creasePath(size: size)
        crease.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        crease.lineWidth = 1.4
        crease.lineCap = .round
        crease.strokeEnd = 0
        body.addSublayer(crease)

        // Appear over the fading drop target, then fold.
        flyer.add(animation("opacity", from: 0, to: 1, begin: now, length: 0.07), forKey: "in")
        for layer in [glow, mask, rim] as [CAShapeLayer] {
            layer.add(animation("path", from: cardPath, to: planePath, begin: now + foldStart,
                                length: foldLength, timing: foldTiming), forKey: "fold")
        }
        fill.add(animation("colors", from: fill.colors, to: paperColors, begin: now + foldStart,
                           length: foldLength, timing: foldTiming), forKey: "paper")
        glow.add(animation("opacity", from: 0, to: 0.55, begin: now + foldStart + 0.08,
                           length: foldLength - 0.08), forKey: "glow")
        rim.add(animation("opacity", from: 1, to: 0.25, begin: now + foldStart,
                          length: foldLength), forKey: "rim")
        crease.add(animation("strokeEnd", from: 0, to: 1, begin: now + 0.2, length: 0.11),
                   forKey: "crease")

        let squash = CAKeyframeAnimation(keyPath: "transform.scale")
        squash.values = [1.0, 0.9, 1.06, 1.0]
        squash.keyTimes = [0, 0.3, 0.75, 1]
        squash.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                  CAMediaTimingFunction(name: .easeInEaseOut),
                                  CAMediaTimingFunction(name: .easeOut)]
        squash.beginTime = now
        squash.duration = launchAt
        body.add(squash, forKey: "squash")

        // Launch: a random, gently curved route to the right, off the screen.
        let route = Self.route(from: center, canvas: canvas)
        let launchTiming = CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.25, 1.0)
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = route
        fly.calculationMode = .paced
        fly.rotationMode = .rotateAuto
        fly.timingFunction = launchTiming
        fly.beginTime = now + launchAt
        fly.duration = flightLength
        fly.fillMode = .forwards
        fly.isRemovedOnCompletion = false
        flyer.add(fly, forKey: "fly")

        // Pop at launch, then a speed stretch that settles as it shrinks away.
        let stretchX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        stretchX.values = [1.0, 1.18, 1.32, 0.9, 0.62]
        stretchX.keyTimes = [0, 0.08, 0.3, 0.7, 1]
        let stretchY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        stretchY.values = [1.0, 1.12, 0.82, 0.74, 0.55]
        stretchY.keyTimes = stretchX.keyTimes
        for stretch in [stretchX, stretchY] {
            stretch.beginTime = now + launchAt
            stretch.duration = flightLength
            stretch.fillMode = .forwards
            stretch.isRemovedOnCompletion = false
            body.add(stretch, forKey: stretch.keyPath)
        }
        flyer.add(animation("opacity", from: 1, to: 0, begin: now + launchAt + flightLength * 0.7,
                            length: flightLength * 0.3), forKey: "out")

        addBoom(at: center, begin: now + launchAt)
        addContrail(route: route, begin: now + launchAt, timing: launchTiming)
        addSparkTrail(route: route, begin: now + launchAt, timing: launchTiming)

        CATransaction.commit()
    }

    // MARK: Boom

    private func addBoom(at center: CGPoint, begin: CFTimeInterval) {
        // A bloom of light, bright at the core and gone at the edge.
        let flash = CAGradientLayer()
        flash.type = .radial
        flash.colors = [NSColor.white.cgColor,
                        NSColor(red: 0.62, green: 0.92, blue: 1.0, alpha: 0.75).cgColor,
                        NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 0).cgColor]
        flash.locations = [0, 0.3, 1]
        flash.startPoint = CGPoint(x: 0.5, y: 0.5)
        flash.endPoint = CGPoint(x: 1, y: 1)
        flash.bounds = CGRect(x: 0, y: 0, width: 220, height: 220)
        flash.position = center
        flash.opacity = 0
        root.addSublayer(flash)
        let flashOpacity = CAKeyframeAnimation(keyPath: "opacity")
        flashOpacity.values = [0, 1, 0]
        flashOpacity.keyTimes = [0, 0.18, 1]
        flashOpacity.beginTime = begin
        flashOpacity.duration = 0.3
        flash.add(flashOpacity, forKey: "flash")
        flash.add(animation("transform.scale", from: 0.35, to: 1.4, begin: begin, length: 0.3,
                            timing: CAMediaTimingFunction(name: .easeOut)), forKey: "grow")

        for (index, color) in [NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 1),
                               NSColor(red: 0.49, green: 0.28, blue: 1.0, alpha: 1)].enumerated() {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40), transform: nil)
            ring.position = center
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = index == 0 ? 2.6 : 1.6
            ring.opacity = 0
            root.addSublayer(ring)
            let start = begin + Double(index) * 0.05
            ring.add(animation("transform.scale", from: 0.6, to: 6.5 - Double(index) * 1.5,
                               begin: start, length: 0.55,
                               timing: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)),
                     forKey: "wave")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.95, 0]
            fade.keyTimes = [0, 0.1, 1]
            fade.beginTime = start
            fade.duration = 0.55
            ring.add(fade, forKey: "fade")
        }

        let burst = CAEmitterLayer()
        burst.emitterPosition = center
        burst.emitterShape = .point
        burst.renderMode = .additive
        burst.birthRate = 0
        burst.emitterCells = Self.sparkCells(velocity: 340, range: .pi * 2, lifetime: 0.7, rate: 900)
        root.addSublayer(burst)
        let pulse = CAKeyframeAnimation(keyPath: "birthRate")
        pulse.values = [1, 1, 0]
        pulse.keyTimes = [0, 0.99, 1]
        pulse.beginTime = begin
        pulse.duration = 0.06
        burst.add(pulse, forKey: "burst")
    }

    // MARK: Trail

    private func addContrail(route: CGPath, begin: CFTimeInterval, timing: CAMediaTimingFunction) {
        let trail = CAShapeLayer()
        trail.path = route
        trail.fillColor = nil
        trail.strokeColor = NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 0.85).cgColor
        trail.lineWidth = 2.4
        trail.lineCap = .round
        trail.lineDashPattern = [6, 8]
        trail.strokeEnd = 0
        trail.shadowColor = trail.strokeColor
        trail.shadowRadius = 6
        trail.shadowOpacity = 0.8
        trail.shadowOffset = .zero
        root.addSublayer(trail)
        trail.add(animation("strokeEnd", from: 0, to: 1, begin: begin, length: flightLength,
                            timing: timing), forKey: "head")
        trail.add(animation("strokeStart", from: 0, to: 1, begin: begin + 0.13,
                            length: flightLength, timing: timing), forKey: "tail")
    }

    private func addSparkTrail(route: CGPath, begin: CFTimeInterval, timing: CAMediaTimingFunction) {
        let sparks = CAEmitterLayer()
        sparks.emitterShape = .point
        sparks.renderMode = .additive
        sparks.birthRate = 0
        sparks.emitterCells = Self.sparkCells(velocity: 60, range: .pi * 2, lifetime: 0.5, rate: 420)
        root.addSublayer(sparks)
        let follow = CAKeyframeAnimation(keyPath: "emitterPosition")
        follow.path = route
        follow.calculationMode = .paced
        follow.timingFunction = timing
        follow.beginTime = begin
        follow.duration = flightLength
        sparks.add(follow, forKey: "follow")
        let on = CAKeyframeAnimation(keyPath: "birthRate")
        on.values = [1, 1, 0]
        on.keyTimes = [0, 0.85, 1]
        on.beginTime = begin
        on.duration = flightLength
        sparks.add(on, forKey: "on")
    }

    // MARK: Geometry

    /// Right-ish, never straight: up to ~45° up or ~15° down, bending a
    /// little differently on every launch, and long enough to leave the screen.
    private static func route(from start: CGPoint, canvas: NSSize) -> CGPath {
        let angle = Double.random(in: -0.26...0.78)
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let reach = exitDistance(from: start, direction: direction, canvas: canvas) + 260
        let bendA = Double.random(in: -0.42...0.42)
        let bendB = -bendA * Double.random(in: 0.4...0.9)
        func point(_ distance: CGFloat, _ bend: Double) -> CGPoint {
            let a = angle + bend
            return CGPoint(x: start.x + CGFloat(cos(a)) * distance,
                           y: start.y + CGFloat(sin(a)) * distance)
        }
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: CGPoint(x: start.x + direction.x * reach, y: start.y + direction.y * reach),
                      control1: point(reach * 0.28, bendA),
                      control2: point(reach * 0.62, bendB))
        return path
    }

    private static func exitDistance(from start: CGPoint, direction: CGPoint, canvas: NSSize) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        if direction.x > 0.01 { best = min(best, (canvas.width - start.x) / direction.x) }
        if direction.y > 0.01 { best = min(best, (canvas.height - start.y) / direction.y) }
        if direction.y < -0.01 { best = min(best, -start.y / direction.y) }
        return best.isFinite ? max(200, best) : 1200
    }

    /// Eight cubic segments, so Core Animation can morph it into the plane.
    private static func cardPath(size: CGSize, radius r: CGFloat) -> CGPath {
        let w = size.width, h = size.height, k = r * 0.5523
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h - r))
        path.addCurve(to: CGPoint(x: r, y: h), control1: CGPoint(x: 0, y: h - r + k),
                      control2: CGPoint(x: r - k, y: h))
        line(path, CGPoint(x: r, y: h), CGPoint(x: w - r, y: h))
        path.addCurve(to: CGPoint(x: w, y: h - r), control1: CGPoint(x: w - r + k, y: h),
                      control2: CGPoint(x: w, y: h - r + k))
        line(path, CGPoint(x: w, y: h - r), CGPoint(x: w, y: r))
        path.addCurve(to: CGPoint(x: w - r, y: 0), control1: CGPoint(x: w, y: r - k),
                      control2: CGPoint(x: w - r + k, y: 0))
        line(path, CGPoint(x: w - r, y: 0), CGPoint(x: r, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: r), control1: CGPoint(x: r - k, y: 0),
                      control2: CGPoint(x: 0, y: r - k))
        line(path, CGPoint(x: 0, y: r), CGPoint(x: 0, y: h - r))
        path.closeSubpath()
        return path
    }

    /// A paper dart pointing right, with the same eight segments as the card.
    private static func planePath(size: CGSize) -> CGPath {
        let p = planePoint(size:)
        let path = CGMutablePath()
        path.move(to: p(size)(0.10, 0.18))
        line(path, p(size)(0.10, 0.18), p(size)(0.00, 0.03))
        line(path, p(size)(0.00, 0.03), p(size)(0.70, 0.38))
        line(path, p(size)(0.70, 0.38), p(size)(1.00, 0.50))
        line(path, p(size)(1.00, 0.50), p(size)(1.00, 0.50))
        line(path, p(size)(1.00, 0.50), p(size)(0.70, 0.62))
        line(path, p(size)(0.70, 0.62), p(size)(0.00, 0.97))
        line(path, p(size)(0.00, 0.97), p(size)(0.10, 0.82))
        path.addCurve(to: p(size)(0.10, 0.18), control1: p(size)(0.27, 0.56),
                      control2: p(size)(0.27, 0.44))
        path.closeSubpath()
        return path
    }

    private static func creasePath(size: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.move(to: planePoint(size: size)(0.24, 0.50))
        path.addLine(to: planePoint(size: size)(1.0, 0.50))
        return path
    }

    /// Maps unit plane coordinates (y down) into the card's layer space (y up).
    private static func planePoint(size: CGSize) -> (CGFloat, CGFloat) -> CGPoint {
        let w = planeSize.width, h = planeSize.height
        let ox = (size.width - w) / 2, oy = (size.height - h) / 2
        return { u, v in CGPoint(x: ox + u * w, y: oy + (1 - v) * h) }
    }

    private static func line(_ path: CGMutablePath, _ a: CGPoint, _ b: CGPoint) {
        path.addCurve(to: b,
                      control1: CGPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3),
                      control2: CGPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3))
    }

    // MARK: Sparks

    private static func sparkCells(velocity: CGFloat, range: CGFloat,
                                   lifetime: Float, rate: Float) -> [CAEmitterCell] {
        let image = sparkImage()
        let colors = [NSColor(red: 0.18, green: 0.82, blue: 1.0, alpha: 1),
                      NSColor(red: 0.10, green: 0.48, blue: 1.0, alpha: 1),
                      NSColor(red: 0.49, green: 0.28, blue: 1.0, alpha: 1),
                      NSColor.white]
        return colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = rate / Float(colors.count)
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetime * 0.4
            cell.velocity = velocity
            cell.velocityRange = velocity * 0.6
            cell.emissionRange = range
            cell.scale = 0.16
            cell.scaleRange = 0.08
            cell.scaleSpeed = -0.18
            cell.alphaSpeed = -1.0 / lifetime
            cell.spin = 2
            cell.spinRange = 4
            return cell
        }
    }

    private static func sparkImage() -> CGImage? {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor.white.cgColor,
                                                 NSColor.white.withAlphaComponent(0.6).cgColor,
                                                 NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: [0, 0.35, 1]) else { return nil }
        let middle = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0,
                                   endCenter: middle, endRadius: CGFloat(side) / 2, options: [])
        return context.makeImage()
    }

    // MARK: Helpers

    private func animation(_ keyPath: String, from: Any?, to: Any?, begin: CFTimeInterval,
                           length: CFTimeInterval,
                           timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut))
        -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = begin
        animation.duration = length
        animation.timingFunction = timing
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }
}
