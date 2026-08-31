import AppKit
import AVFoundation
import CoreMedia
import QuartzCore

private struct Scene {
    let file: String
    let title: String
    let subtitle: String
    let crop: NSEdgeInsets
}

private enum DemoError: Error {
    case missingTrack(String)
    case exportFailed(String)
}

@main
struct ComposeDemo {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let raw = root.appendingPathComponent("marketing/shipaton/video/raw", isDirectory: true)
        let output = root.appendingPathComponent("marketing/shipaton/video/airfliq-demo-draft.mp4")
        let iconURL = root.appendingPathComponent("marketing/shipaton/assets/airfliq-icon-1024.png")

        let scenes = [
            Scene(file: "01-ready.mov", title: "AirDrop. One move.",
                  subtitle: "Four native ways to launch the panel you already know.",
                  crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105)),
            Scene(file: "02-shortcut.mov", title: "Your shortcut. Your way.",
                  subtitle: "Choose a preset or record any safe global combination.",
                  crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105)),
            Scene(file: "03-drag-hover.mov", title: "A target when you need it.",
                  subtitle: "Pick up a file and AirFliq meets the cursor.",
                  crop: NSEdgeInsets(top: 4, left: 6, bottom: 8, right: 6)),
            Scene(file: "04-drag-complete.mov", title: "Drop. Confirmed.",
                  subtitle: "Immediate visual feedback before the native handoff.",
                  crop: NSEdgeInsets(top: 3, left: 4, bottom: 6, right: 4)),
            Scene(file: "05-paywall.mov", title: "Seven days. Every feature.",
                  subtitle: "Then one $4.99 Lifetime Pro purchase powered by RevenueCat.",
                  crop: NSEdgeInsets(top: 76, left: 70, bottom: 142, right: 70)),
            Scene(file: "01-ready.mov", title: "Select. Fliq. Sent.",
                  subtitle: "AirFliq for macOS. Built in public for Shipaton.",
                  crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105)),
        ]

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw DemoError.missingTrack("composition") }

        let renderSize = CGSize(width: 1920, height: 1080)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        var cursor = CMTime.zero
        var sceneRanges: [CMTimeRange] = []
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for (index, scene) in scenes.enumerated() {
            let asset = AVURLAsset(url: raw.appendingPathComponent(scene.file))
            let duration = try await asset.load(.duration)
            let sourceTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceTrack = sourceTracks.first else {
                throw DemoError.missingTrack(scene.file)
            }

            let useDuration: CMTime
            if index == scenes.count - 1 {
                useDuration = CMTime(seconds: min(6, CMTimeGetSeconds(duration)), preferredTimescale: 600)
            } else {
                useDuration = duration
            }
            let sourceRange = CMTimeRange(start: .zero, duration: useDuration)
            try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: cursor)

            let timeRange = CMTimeRange(start: cursor, duration: useDuration)
            sceneRanges.append(timeRange)

            let naturalSize = try await sourceTrack.load(.naturalSize)
            let preferred = try await sourceTrack.load(.preferredTransform)
            let oriented = CGRect(origin: .zero, size: naturalSize).applying(preferred).standardized.size
            let crop = CGRect(
                x: scene.crop.left,
                y: scene.crop.bottom,
                width: max(1, oriented.width - scene.crop.left - scene.crop.right),
                height: max(1, oriented.height - scene.crop.top - scene.crop.bottom)
            )

            let maxContent = index == 2 || index == 3
                ? CGSize(width: 980, height: 690)
                : CGSize(width: 980, height: 850)
            let scale = min(maxContent.width / crop.width, maxContent.height / crop.height)
            let scaled = CGSize(width: crop.width * scale, height: crop.height * scale)
            let targetX = 66 + (maxContent.width - scaled.width) / 2
            let targetY = 92 + (maxContent.height - scaled.height) / 2

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            instruction.backgroundColor = NSColor.clear.cgColor

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setCropRectangle(crop, at: cursor)
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                              tx: targetX - crop.minX * scale,
                                              ty: targetY - crop.minY * scale)
            layer.setTransform(transform, at: cursor)
            layer.setOpacity(1, at: cursor)
            layer.setOpacity(0, at: CMTimeSubtract(CMTimeRangeGetEnd(timeRange), CMTime(value: 1, timescale: 600)))
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = CMTimeRangeGetEnd(timeRange)
        }
        videoComposition.instructions = instructions

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.backgroundColor = NSColor(calibratedRed: 0.01, green: 0.018, blue: 0.045, alpha: 1).cgColor

        let background = CAGradientLayer()
        background.frame = parent.bounds
        background.colors = [
            NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.15, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.018, green: 0.02, blue: 0.075, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.055, green: 0.018, blue: 0.09, alpha: 1).cgColor,
        ]
        background.locations = [0, 0.55, 1]
        background.startPoint = CGPoint(x: 0, y: 1)
        background.endPoint = CGPoint(x: 1, y: 0)
        parent.addSublayer(background)

        addAmbientOrb(to: parent, frame: CGRect(x: -180, y: 620, width: 650, height: 650),
                      color: NSColor(calibratedRed: 0.0, green: 0.63, blue: 1, alpha: 0.18))
        addAmbientOrb(to: parent, frame: CGRect(x: 1420, y: -150, width: 650, height: 650),
                      color: NSColor(calibratedRed: 0.47, green: 0.16, blue: 1, alpha: 0.16))

        let videoLayer = CALayer()
        videoLayer.frame = parent.bounds
        parent.addSublayer(videoLayer)

        let border = CAShapeLayer()
        border.path = CGPath(roundedRect: CGRect(x: 38, y: 66, width: 1040, height: 894),
                             cornerWidth: 54, cornerHeight: 54, transform: nil)
        border.fillColor = NSColor(calibratedWhite: 0.03, alpha: 0.12).cgColor
        border.strokeColor = NSColor(calibratedRed: 0.23, green: 0.67, blue: 1, alpha: 0.22).cgColor
        border.lineWidth = 2
        parent.addSublayer(border)

        if let image = NSImage(contentsOf: iconURL) {
            let icon = CALayer()
            icon.frame = CGRect(x: 1140, y: 930, width: 72, height: 72)
            icon.contents = image
            icon.contentsGravity = .resizeAspect
            parent.addSublayer(icon)
        }

        parent.addSublayer(textLayer("AIRFLIQ", frame: CGRect(x: 1230, y: 956, width: 300, height: 36),
                                      size: 25, weight: .bold, color: .white, tracking: 5))
        parent.addSublayer(textLayer("SELECT. FLIQ. SENT.", frame: CGRect(x: 1230, y: 928, width: 420, height: 24),
                                      size: 14, weight: .semibold,
                                      color: NSColor(calibratedWhite: 0.63, alpha: 1), tracking: 2.2))

        addPill(to: parent, text: "NATIVE MACOS", frame: CGRect(x: 1140, y: 180, width: 205, height: 48))
        addPill(to: parent, text: "NO FULL DISK ACCESS", frame: CGRect(x: 1362, y: 180, width: 310, height: 48))
        addPill(to: parent, text: "$4.99 LIFETIME", frame: CGRect(x: 1140, y: 116, width: 240, height: 48))

        let totalDuration = CMTimeGetSeconds(cursor)
        for (index, range) in sceneRanges.enumerated() {
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            let accent = index % 2 == 0
                ? NSColor(calibratedRed: 0.23, green: 0.79, blue: 1, alpha: 1)
                : NSColor(calibratedRed: 0.50, green: 0.36, blue: 1, alpha: 1)
            addSceneText(to: parent, scene: scenes[index], index: index,
                         start: start, duration: duration, accent: accent)
        }

        let progressTrack = CALayer()
        progressTrack.frame = CGRect(x: 76, y: 48, width: 1768, height: 4)
        progressTrack.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progressTrack.cornerRadius = 2
        parent.addSublayer(progressTrack)

        let progress = CAGradientLayer()
        progress.frame = progressTrack.bounds
        progress.colors = [
            NSColor(calibratedRed: 0.18, green: 0.79, blue: 1, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.49, green: 0.28, blue: 1, alpha: 1).cgColor,
        ]
        progress.startPoint = CGPoint(x: 0, y: 0.5)
        progress.endPoint = CGPoint(x: 1, y: 0.5)
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.position = CGPoint(x: 0, y: 2)
        progress.transform = CATransform3DMakeScale(0.001, 1, 1)
        progress.cornerRadius = 2
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0.001
        grow.toValue = 1
        grow.beginTime = AVCoreAnimationBeginTimeAtZero
        grow.duration = totalDuration
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        progress.add(grow, forKey: "progress")
        progressTrack.addSublayer(progress)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parent
        )

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw DemoError.exportFailed("Could not create export session")
        }
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: output, as: .mp4)
        print(output.path)
        print(String(format: "%.2f seconds", totalDuration))
    }

    private static func addAmbientOrb(to parent: CALayer, frame: CGRect, color: NSColor) {
        let orb = CAGradientLayer()
        orb.type = .radial
        orb.frame = frame
        orb.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
        orb.locations = [0, 1]
        parent.addSublayer(orb)
    }

    private static func textLayer(_ text: String, frame: CGRect, size: CGFloat,
                                  weight: NSFont.Weight, color: NSColor,
                                  tracking: CGFloat = 0,
                                  wrapped: Bool = false,
                                  alignment: NSTextAlignment = .left) -> CALayer {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = wrapped ? .byWordWrapping : .byClipping

        let scale: CGFloat = 2
        let pixelsWide = max(1, Int(ceil(frame.width * scale)))
        let pixelsHigh = max(1, Int(ceil(frame.height * scale)))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: pixelsWide,
                                      pixelsHigh: pixelsHigh,
                                      bitsPerSample: 8,
                                      samplesPerPixel: 4,
                                      hasAlpha: true,
                                      isPlanar: false,
                                      colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0,
                                      bitsPerPixel: 0)!
        bitmap.size = frame.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: frame.size).fill()
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
        ]).draw(with: CGRect(origin: .zero, size: frame.size),
                options: wrapped ? [.usesLineFragmentOrigin, .usesFontLeading] : [],
                context: nil)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: frame.size)
        image.addRepresentation(bitmap)
        let layer = CALayer()
        layer.frame = frame
        layer.contentsScale = scale
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        return layer
    }

    private static func addPill(to parent: CALayer, text: String, frame: CGRect) {
        let pill = CALayer()
        pill.frame = frame
        pill.cornerRadius = frame.height / 2
        pill.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        pill.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pill.borderWidth = 1
        parent.addSublayer(pill)
        let label = textLayer(text,
                              frame: CGRect(x: 20, y: 14, width: frame.width - 40, height: 24),
                              size: 13, weight: .bold,
                              color: NSColor(calibratedWhite: 0.78, alpha: 1), tracking: 1.7,
                              alignment: .center)
        pill.addSublayer(label)
    }

    private static func addSceneText(to parent: CALayer, scene: Scene, index: Int,
                                     start: Double, duration: Double, accent: NSColor) {
        let eyebrow = textLayer(String(format: "%02d  AIRFLIQ", index + 1),
                                frame: CGRect(x: 1140, y: 850, width: 320, height: 26),
                                size: 13, weight: .bold, color: accent, tracking: 3)
        let title = textLayer(scene.title,
                              frame: CGRect(x: 1140, y: 690, width: 690, height: 150),
                              size: 54, weight: .bold, color: .white, wrapped: true)
        let subtitle = textLayer(scene.subtitle,
                                 frame: CGRect(x: 1140, y: 555, width: 650, height: 120),
                                 size: 24, weight: .medium,
                                 color: NSColor(calibratedWhite: 0.68, alpha: 1), wrapped: true)

        for layer in [eyebrow, title, subtitle] {
            layer.opacity = 0
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.12, 0.88, 1]
            opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
            opacity.duration = duration
            opacity.fillMode = .both
            opacity.isRemovedOnCompletion = false
            layer.add(opacity, forKey: "scene-opacity")

            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = 22
            slide.toValue = 0
            slide.beginTime = AVCoreAnimationBeginTimeAtZero + start
            slide.duration = min(0.7, duration * 0.18)
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slide.fillMode = .both
            slide.isRemovedOnCompletion = false
            layer.add(slide, forKey: "scene-slide")
            parent.addSublayer(layer)
        }
    }
}
