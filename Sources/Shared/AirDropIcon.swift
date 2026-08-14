import Cocoa

/// All artwork is drawn in code, so the app, the Finder extension and the
/// .icns generator always stay in sync and the bundle ships no image assets.
///
/// Geometry is expressed in a 100×100, top-left-origin design space that matches
/// the original design mockups one-to-one.
enum AirDropIcon {

    // MARK: - Public

    /// Full-colour "Flying Card" app icon.
    ///
    /// `inset` is the fraction of the canvas left empty around the squircle.
    /// Dock icons need it so AirFliq sits the same size as its neighbours;
    /// icons drawn inside our own UI want the full bleed.
    static func appIcon(size: CGFloat, inset: CGFloat = 0) -> NSImage {
        image(size: size) { context in
            if inset > 0 {
                let margin = 100 * inset
                context.translateBy(x: margin, y: margin)
                context.scaleBy(x: 1 - 2 * inset, y: 1 - 2 * inset)
            }
            drawAppIcon(in: context)
        }
    }

    /// Monochrome glyph for the menu bar, which must adapt to light/dark.
    static func menuBarGlyph(size: CGFloat, color: NSColor) -> NSImage {
        image(size: size) { context in
            drawGlyph(in: context, color: color)
        }
    }

    /// Draws the monochrome glyph into the current AppKit context, filling `rect`.
    static func drawGlyph(in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let side = min(rect.width, rect.height)
        context.translateBy(x: rect.minX, y: rect.minY + side)
        context.scaleBy(x: side / 100, y: -side / 100)
        drawGlyph(in: context, color: color)
        context.restoreGState()
    }

    // MARK: - Canvas

    private static func image(size: CGFloat, _ body: (CGContext) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            // Flip into a top-left-origin, 100-unit design space.
            context.translateBy(x: 0, y: size)
            context.scaleBy(x: size / 100, y: -size / 100)
            body(context)
            context.restoreGState()
        }
        image.unlockFocus()
        return image
    }

    // MARK: - App icon

    private static func drawAppIcon(in context: CGContext) {
        let squircle = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              cornerWidth: 23, cornerHeight: 23, transform: nil)

        context.saveGState()
        context.addPath(squircle)
        context.clip()

        // Background: cyan → blue → violet, on the diagonal.
        fillGradient(context,
                     colors: [rgb(0x6F, 0xD6, 0xFF), rgb(0x2B, 0x6B, 0xFF), rgb(0x6A, 0x21, 0xD6)],
                     locations: [0, 0.52, 1],
                     from: CGPoint(x: 10, y: 0), to: CGPoint(x: 90, y: 100))

        // Restrained specular sheen - enough to give the surface curvature
        // without bleaching the gradient underneath.
        fillGradient(context,
                     colors: [white(0.26), white(0.03), white(0)],
                     locations: [0, 0.38, 1],
                     from: CGPoint(x: 50, y: 0), to: CGPoint(x: 50, y: 100))

        // Vignette at the bottom, to seat the icon.
        fillGradient(context,
                     colors: [black(0), black(0.26)],
                     locations: [0.5, 1],
                     from: CGPoint(x: 50, y: 0), to: CGPoint(x: 50, y: 100))

        // The card and its motion trail. Positive rotation reads as
        // counter-clockwise here, because the design space is y-flipped.
        context.saveGState()
        context.translateBy(x: 54, y: 50)
        context.rotate(by: 17 * .pi / 180)
        context.translateBy(x: -54, y: -50)

        // Ghosts trail down-left, opposite the direction of travel, and shrink as
        // they recede. The scaling is what separates "in flight" from "a stack of
        // paper" - equal-sized copies just read as a pile.
        context.addPath(rounded(16.2, 42.2, 33.6, 41.6, 6.4))
        context.setFillColor(white(0.15))
        context.fillPath()

        context.addPath(rounded(26.1, 32.6, 37.8, 46.8, 7.2))
        context.setFillColor(white(0.32))
        context.fillPath()

        context.setShadow(offset: CGSize(width: -2, height: 5), blur: 8,
                          color: CGColor(red: 0.02, green: 0.04, blue: 0.20, alpha: 0.45))
        context.addPath(rounded(37, 23, 42, 52, 8))
        context.setFillColor(white(1))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // A hint of content on the card: a thumbnail and two text lines.
        let accent = rgb(0x2F, 0x6B, 0xFF)
        context.addPath(rounded(44, 31, 28, 18, 4))
        context.setFillColor(accent.copy(alpha: 0.50)!)
        context.fillPath()

        context.addPath(rounded(44, 54, 28, 4.5, 2.25))
        context.addPath(rounded(44, 62, 17, 4.5, 2.25))
        context.setFillColor(accent.copy(alpha: 0.28)!)
        context.fillPath()

        context.restoreGState()
        context.restoreGState()
    }

    // MARK: - Menu bar glyph

    private static func drawGlyph(in context: CGContext, color: NSColor) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)

        // Speed lines stay horizontal - they read as motion, not as part of the card.
        context.addPath(rounded(4, 40, 20, 8, 4))
        context.addPath(rounded(11, 59, 17, 8, 4))
        context.fillPath()

        context.translateBy(x: 60, y: 50)
        context.rotate(by: 17 * .pi / 180)
        context.translateBy(x: -60, y: -50)

        context.addPath(rounded(40, 22, 44, 56, 9))
        context.setLineWidth(8)
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - Drawing helpers

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                                _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
               cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func fillGradient(_ context: CGContext, colors: [CGColor],
                                     locations: [CGFloat], from: CGPoint, to: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: locations) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [])
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static func white(_ alpha: CGFloat) -> CGColor {
        CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
    }

    private static func black(_ alpha: CGFloat) -> CGColor {
        CGColor(red: 0, green: 0, blue: 0, alpha: alpha)
    }
}
