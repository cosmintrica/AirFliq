import Cocoa

/// The menu bar icon: drawn in code, accepts dropped files, opens the menu on click.
final class StatusDropView: NSView {

    var onDrop: ([URL]) -> Void = { _ in }
    var onClick: (NSView) -> Void = { _ in }

    private var isDropTarget = false { didSet { animateHighlight() } }
    private var isHovered = false { didSet { animateHighlight() } }
    private var highlightAmount: CGFloat = 0
    private var pulseAmount: CGFloat = 0
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("AirFliq")
        setAccessibilityHelp("Open the AirFliq menu, or drop files here to send them.")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited,
                                                 .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 3)

        if highlightAmount > 0.01 {
            let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.28 * highlightAmount).setFill()
            path.fill()
        }

        if pulseAmount > 0.01 {
            let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            NSColor.systemGreen.withAlphaComponent(0.35 * pulseAmount).setFill()
            path.fill()

            let progress = 1 - pulseAmount
            let ringRect = box.insetBy(dx: -3 * progress, dy: -3 * progress)
            let ring = NSBezierPath(roundedRect: ringRect, xRadius: 6, yRadius: 6)
            ring.lineWidth = 1.5
            NSColor.systemGreen.withAlphaComponent(0.75 * pulseAmount).setStroke()
            ring.stroke()
        }

        let successBounce = pulseAmount > 0
            ? 0.10 * sin((1 - pulseAmount) * .pi * 2)
            : 0
        let scale = 1.0 + 0.12 * highlightAmount + successBounce
        let side = min(bounds.width, bounds.height) * 0.90 * scale
        let glyphRect = NSRect(x: bounds.midX - side / 2,
                               y: bounds.midY - side / 2,
                               width: side, height: side)

        let color: NSColor
        if pulseAmount > 0.2 {
            color = .systemGreen
        } else {
            color = highlightAmount > 0.5 ? .controlAccentColor : .labelColor
        }
        AirDropIcon.drawGlyph(in: glyphRect, color: color)
    }

    private func animateHighlight() {
        startAnimation()
    }

    /// A brief green flash after a successful send.
    func pulseSuccess() {
        pulseAmount = 1
        startAnimation()
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60,
                          target: self,
                          selector: #selector(animationTick(_:)),
                          userInfo: nil,
                          repeats: true)
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func animationTick(_ timer: Timer) {
        let target: CGFloat = isDropTarget ? 1 : (isHovered ? 0.34 : 0)
        highlightAmount += (target - highlightAmount) * 0.25
        pulseAmount *= 0.94

        if abs(highlightAmount - target) < 0.01 && pulseAmount < 0.01 {
            highlightAmount = target
            pulseAmount = 0
            timer.invalidate()
            animationTimer = nil
        }
        needsDisplay = true
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        onClick(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick(self)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func accessibilityPerformPress() -> Bool {
        onClick(self)
        return true
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        isDropTarget = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        let files = urls(from: sender)
        guard !files.isEmpty else { return false }
        onDrop(files)
        return true
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }
}
