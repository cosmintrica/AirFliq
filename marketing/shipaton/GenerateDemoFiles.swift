import AppKit

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let output = root.appendingPathComponent("marketing/shipaton/demo-files", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

private final class BriefView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.09, alpha: 1).setFill()
        bounds.fill()

        let glow = NSGradient(colors: [
            NSColor(calibratedRed: 0.08, green: 0.68, blue: 1, alpha: 0.32),
            NSColor(calibratedRed: 0.43, green: 0.20, blue: 1, alpha: 0.02),
        ])!
        glow.draw(in: NSRect(x: 80, y: 50, width: 760, height: 760), relativeCenterPosition: .zero)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        "AIRFLIQ".draw(
            at: NSPoint(x: 96, y: 112),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.28, green: 0.80, blue: 1, alpha: 1),
                .kern: 6,
            ]
        )

        "Release\nto Fliq".draw(
            in: NSRect(x: 90, y: 178, width: 700, height: 260),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 92, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )

        "Select. Fliq. Sent.".draw(
            at: NSPoint(x: 96, y: 475),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
            ]
        )

        let chip = NSBezierPath(roundedRect: NSRect(x: 92, y: 570, width: 520, height: 78), xRadius: 26, yRadius: 26)
        NSColor(calibratedRed: 0.12, green: 0.43, blue: 1, alpha: 1).setFill()
        chip.fill()
        "Shipaton 2026 - Demo Brief".draw(
            at: NSPoint(x: 132, y: 589),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
    }
}

private let view = BriefView(frame: NSRect(x: 0, y: 0, width: 842, height: 720))
private let pdf = view.dataWithPDF(inside: view.bounds)
try pdf.write(to: output.appendingPathComponent("Release to Fliq.pdf"), options: .atomic)

private let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: rep)
private let png = rep.representation(using: .png, properties: [:])!
try png.write(to: output.appendingPathComponent("AirFliq Preview.png"), options: .atomic)

private let notes = """
AirFliq Shipaton Demo

Select a file in Finder. Use a global shortcut, right-click, the menu bar, or the magnetic drag target. AirFliq opens the native AirDrop panel immediately.
"""
try notes.write(
    to: output.appendingPathComponent("Shipaton Notes.txt"),
    atomically: true,
    encoding: .utf8
)

print(output.path)
