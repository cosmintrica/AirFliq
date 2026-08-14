import AppKit
import QuartzCore

/// Small, consistent motion primitives used throughout the app.
///
/// Core Animation keeps these effects smooth without keeping a 60 fps timer
/// alive while the app is idle.
enum Motion {

    static let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func reveal(_ view: NSView, delay: CFTimeInterval = 0,
                       offsetY: CGFloat = -6, duration: CFTimeInterval = 0.72) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        guard !reduceMotion else { layer.opacity = 1; return }

        let now = layer.convertTime(CACurrentMediaTime(), from: nil)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.beginTime = now + delay
        fade.fillMode = .backwards
        fade.timingFunction = easeOut

        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = offsetY
        move.toValue = 0
        move.duration = duration
        move.beginTime = now + delay
        move.fillMode = .backwards
        move.timingFunction = easeOut

        layer.opacity = 1
        layer.add(fade, forKey: "airfliq.reveal.opacity")
        layer.add(move, forKey: "airfliq.reveal.position")
    }

    static func spring(_ view: NSView, from: CGFloat = 0.78,
                       duration: CFTimeInterval = 0.48,
                       key: String = "airfliq.spring") {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        guard !reduceMotion else { return }

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [from, 1.025, 0.992, 1.006, 1]
        animation.keyTimes = [0, 0.48, 0.69, 0.86, 1]
        animation.duration = duration
        animation.calculationMode = .cubic
        animation.timingFunction = easeOut
        layer.add(animation, forKey: key)
    }

    static func successPulse(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        guard !reduceMotion else { return }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.055, 0.988, 1.008, 1]
        scale.keyTimes = [0, 0.32, 0.62, 0.82, 1]
        scale.duration = 0.76
        scale.calculationMode = .cubic
        scale.timingFunction = easeOut
        layer.add(scale, forKey: "airfliq.success.scale")

        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 0.7
        glow.toValue = 0
        glow.duration = 0.95
        glow.timingFunction = easeOut
        layer.shadowColor = NSColor.systemGreen.cgColor
        layer.shadowRadius = 18
        layer.shadowOffset = .zero
        layer.add(glow, forKey: "airfliq.success.glow")
    }

    /// A button-safe confirmation that never changes the control's geometry.
    /// Scaling AppKit buttons can make their bezel look off-axis while their
    /// internal cell is redrawing, so primary actions use light instead.
    static func highlight(_ view: NSView, color: NSColor = .controlAccentColor,
                          key: String = "airfliq.highlight") {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        guard !reduceMotion else { return }

        layer.shadowColor = color.cgColor
        layer.shadowRadius = 14
        layer.shadowOffset = NSSize(width: 0, height: -2)

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [layer.shadowOpacity, 0.72, 0.34, layer.shadowOpacity]
        glow.keyTimes = [0, 0.22, 0.62, 1]
        glow.duration = 0.72
        glow.timingFunction = easeOut
        layer.add(glow, forKey: key)
    }

    static func beginFloating(_ view: NSView, distance: CGFloat = 3) {
        view.wantsLayer = true
        guard let layer = view.layer,
              layer.animation(forKey: "airfliq.float") == nil else { return }
        guard !reduceMotion else { return }

        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = -distance
        animation.toValue = distance
        animation.duration = 3.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = easeInOut
        layer.add(animation, forKey: "airfliq.float")
    }
}
