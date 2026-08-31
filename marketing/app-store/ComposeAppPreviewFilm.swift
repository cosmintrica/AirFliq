import AppKit
import AVFoundation
import CoreMedia
import QuartzCore

private enum PreviewError: Error {
    case missingAsset(String)
    case missingTrack(String)
    case exportFailed(String)
}

private enum PreviewStage {
    case center(CGSize)
    case right(CGSize)
}

private struct PreviewSegment {
    let file: String
    let sourceStart: Double
    let sourceDuration: Double
    let outputDuration: Double
    let crop: NSEdgeInsets
    let stage: PreviewStage
    let number: String
    let title: String
    let detail: String
    let accent: NSColor
    let labelFrame: CGRect
    let menuOverlay: Bool
}

@main
struct ComposeAppPreviewFilm {
    private static let renderSize = CGSize(width: 1_920, height: 1_080)
    private static let deepNavy = NSColor(calibratedRed: 0.008, green: 0.020, blue: 0.062, alpha: 1)
    private static let cyan = NSColor(calibratedRed: 0.13, green: 0.80, blue: 1.00, alpha: 1)
    private static let blue = NSColor(calibratedRed: 0.12, green: 0.48, blue: 1.00, alpha: 1)
    private static let violet = NSColor(calibratedRed: 0.49, green: 0.25, blue: 1.00, alpha: 1)

    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let raw = root.appendingPathComponent("marketing/shipaton/video/raw", isDirectory: true)
        let menuURL = root.appendingPathComponent("marketing/app-store/native/menu-panel.png")
        let output = root.appendingPathComponent("marketing/app-store/final/airfliq-app-preview-29s-silent.mp4")

        guard FileManager.default.fileExists(atPath: menuURL.path) else {
            throw PreviewError.missingAsset(menuURL.path)
        }

        // 29 seconds total. Every scene is real AirFliq footage except the animated
        // menu capture, which is a native screenshot of the shipping menu.
        let segments = [
            PreviewSegment(
                file: "01-ready.mov", sourceStart: 0.8, sourceDuration: 4.0, outputDuration: 4.0,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .center(CGSize(width: 1_190, height: 1_000)),
                number: "01", title: "Ready in four steps", detail: "Choose access once. Stay in control.",
                accent: cyan, labelFrame: CGRect(x: 54, y: 430, width: 430, height: 194), menuOverlay: false
            ),
            PreviewSegment(
                file: "02-shortcut.mov", sourceStart: 2.0, sourceDuration: 7.0, outputDuration: 7.0,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .right(CGSize(width: 1_170, height: 1_000)),
                number: "02", title: "Your shortcut", detail: "Pick a preset or record your own.",
                accent: violet, labelFrame: CGRect(x: 54, y: 430, width: 520, height: 194), menuOverlay: false
            ),
            PreviewSegment(
                file: "03-drag-hover.mov", sourceStart: 0, sourceDuration: 4.5, outputDuration: 4.5,
                crop: NSEdgeInsets(top: 4, left: 6, bottom: 8, right: 6),
                // Preserve the small real capture near native scale. The field
                // around it carries the composition instead of enlarged pixels.
                stage: .center(CGSize(width: 540, height: 280)),
                number: "03", title: "Drag from anywhere", detail: "The send target meets your cursor.",
                accent: cyan, labelFrame: CGRect(x: 550, y: 840, width: 820, height: 166), menuOverlay: false
            ),
            PreviewSegment(
                file: "04-drag-complete.mov", sourceStart: 0, sourceDuration: 4.0, outputDuration: 4.0,
                crop: NSEdgeInsets(top: 3, left: 4, bottom: 6, right: 4),
                stage: .center(CGSize(width: 530, height: 260)),
                number: "04", title: "Drop. Confirmed.", detail: "Clear feedback before the native handoff.",
                accent: NSColor.systemGreen, labelFrame: CGRect(x: 550, y: 840, width: 820, height: 166), menuOverlay: false
            ),
            PreviewSegment(
                file: "01-ready.mov", sourceStart: 0, sourceDuration: 3.5, outputDuration: 3.5,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .center(CGSize(width: 1_190, height: 1_000)),
                number: "05", title: "Four paths", detail: "Shortcut. Right-click. Menu bar. Drag.",
                accent: violet, labelFrame: CGRect(x: 70, y: 410, width: 570, height: 194), menuOverlay: true
            ),
            PreviewSegment(
                file: "05-paywall.mov", sourceStart: 1.0, sourceDuration: 6.0, outputDuration: 6.0,
                crop: NSEdgeInsets(top: 76, left: 70, bottom: 142, right: 70),
                stage: .right(CGSize(width: 1_000, height: 1_010)),
                number: "06", title: "Seven full days", detail: "Every feature, then $4.99 once.",
                accent: cyan, labelFrame: CGRect(x: 54, y: 420, width: 620, height: 194), menuOverlay: false
            ),
        ]

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw PreviewError.missingTrack("composition") }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        var cursor = CMTime.zero
        var ranges: [CMTimeRange] = []
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for segment in segments {
            let asset = AVURLAsset(url: raw.appendingPathComponent(segment.file))
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw PreviewError.missingTrack(segment.file)
            }

            let sourceDuration = CMTime(seconds: segment.sourceDuration, preferredTimescale: 600)
            let outputDuration = CMTime(seconds: segment.outputDuration, preferredTimescale: 600)
            try compositionTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(seconds: segment.sourceStart, preferredTimescale: 600),
                    duration: sourceDuration
                ),
                of: sourceTrack,
                at: cursor
            )
            if sourceDuration != outputDuration {
                compositionTrack.scaleTimeRange(
                    CMTimeRange(start: cursor, duration: sourceDuration),
                    toDuration: outputDuration
                )
            }

            let range = CMTimeRange(start: cursor, duration: outputDuration)
            ranges.append(range)

            let natural = try await sourceTrack.load(.naturalSize)
            let preferred = try await sourceTrack.load(.preferredTransform)
            let oriented = CGRect(origin: .zero, size: natural).applying(preferred).standardized.size
            let crop = CGRect(
                x: segment.crop.left,
                y: segment.crop.bottom,
                width: oriented.width - segment.crop.left - segment.crop.right,
                height: oriented.height - segment.crop.top - segment.crop.bottom
            )
            let target = targetRect(segment.stage, content: crop.size)
            let startTransform = transform(crop: crop, target: target, zoom: 0.992)
            let endTransform = transform(crop: crop, target: target, zoom: 1.012)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.backgroundColor = NSColor.clear.cgColor
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setCropRectangle(crop, at: cursor)
            layer.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: range)
            let fadeDuration = CMTime(seconds: 0.22, preferredTimescale: 600)
            let visibleOpacity: Float = segment.menuOverlay ? 0.08 : 1
            layer.setOpacityRamp(
                fromStartOpacity: 0,
                toEndOpacity: visibleOpacity,
                timeRange: CMTimeRange(start: cursor, duration: fadeDuration)
            )
            layer.setOpacityRamp(
                fromStartOpacity: visibleOpacity,
                toEndOpacity: 0,
                timeRange: CMTimeRange(
                    start: CMTimeSubtract(CMTimeRangeGetEnd(range), fadeDuration),
                    duration: fadeDuration
                )
            )
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = CMTimeRangeGetEnd(range)
        }

        videoComposition.instructions = instructions
        let duration = CMTimeGetSeconds(cursor)

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.backgroundColor = deepNavy.cgColor
        parent.masksToBounds = true
        addBackground(to: parent, duration: duration)

        let videoLayer = CALayer()
        videoLayer.frame = parent.bounds
        parent.addSublayer(videoLayer)

        let dragBackdrops = CALayer()
        dragBackdrops.frame = parent.bounds
        parent.addSublayer(dragBackdrops)
        for index in [2, 3] {
            let range = ranges[index]
            addDragBackdrop(
                to: dragBackdrops,
                accent: segments[index].accent,
                start: CMTimeGetSeconds(range.start),
                duration: CMTimeGetSeconds(range.duration),
                completed: index == 3
            )
        }

        for (index, range) in ranges.enumerated() {
            let segment = segments[index]
            let start = CMTimeGetSeconds(range.start)
            let sceneDuration = CMTimeGetSeconds(range.duration)
            addLabel(to: parent, segment: segment, start: start, duration: sceneDuration)
            if segment.menuOverlay {
                addMenu(to: parent, imageURL: menuURL, start: start, duration: sceneDuration)
            }
        }

        addProgress(to: parent, duration: duration)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parent
        )

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw PreviewError.exportFailed("Could not create preview export session")
        }
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: output, as: .mp4)

        print("Created \(output.path)")
        print(String(format: "App Preview picture: %.2f seconds, 1920x1080, 30 fps", duration))
    }

    private static func targetRect(_ stage: PreviewStage, content: CGSize) -> CGRect {
        let maximum: CGSize
        let x: CGFloat
        switch stage {
        case .center(let value):
            maximum = value
            let size = aspectFit(content, in: maximum)
            x = (renderSize.width - size.width) / 2
            return CGRect(x: x, y: (renderSize.height - size.height) / 2, width: size.width, height: size.height)
        case .right(let value):
            maximum = value
            let size = aspectFit(content, in: maximum)
            x = renderSize.width - size.width - 62
            return CGRect(x: x, y: (renderSize.height - size.height) / 2, width: size.width, height: size.height)
        }
    }

    private static func aspectFit(_ source: CGSize, in maximum: CGSize) -> CGSize {
        let scale = min(maximum.width / source.width, maximum.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private static func transform(crop: CGRect, target: CGRect, zoom: CGFloat) -> CGAffineTransform {
        let scale = min(target.width / crop.width, target.height / crop.height) * zoom
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        return CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: target.midX - size.width / 2 - crop.minX * scale,
            ty: target.midY - size.height / 2 - crop.minY * scale
        )
    }

    private static func addBackground(to parent: CALayer, duration: Double) {
        let gradient = CAGradientLayer()
        gradient.frame = parent.bounds
        gradient.colors = [
            NSColor(calibratedRed: 0.012, green: 0.050, blue: 0.135, alpha: 1).cgColor,
            deepNavy.cgColor,
            NSColor(calibratedRed: 0.070, green: 0.018, blue: 0.13, alpha: 1).cgColor,
        ]
        gradient.locations = [0, 0.56, 1]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        parent.addSublayer(gradient)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -80, y: 118))
        path.addCurve(
            to: CGPoint(x: 2_000, y: 206),
            control1: CGPoint(x: 520, y: 320),
            control2: CGPoint(x: 1_340, y: -40)
        )
        for (offset, color) in [(0.0, cyan), (14.0, blue), (-14.0, violet)] {
            var translation = CGAffineTransform(translationX: 0, y: offset)
            let ribbon = CAShapeLayer()
            ribbon.path = path.copy(using: &translation)
            ribbon.strokeColor = color.withAlphaComponent(0.20).cgColor
            ribbon.fillColor = NSColor.clear.cgColor
            ribbon.lineWidth = 1.5
            ribbon.lineDashPattern = [9, 22]
            parent.addSublayer(ribbon)
            let phase = CABasicAnimation(keyPath: "lineDashPhase")
            phase.fromValue = 0
            phase.toValue = -420
            phase.beginTime = AVCoreAnimationBeginTimeAtZero
            phase.duration = duration
            phase.fillMode = .both
            phase.isRemovedOnCompletion = false
            ribbon.add(phase, forKey: "travel")
        }
    }

    private static func addDragBackdrop(
        to parent: CALayer,
        accent: NSColor,
        start: Double,
        duration: Double,
        completed: Bool
    ) {
        let field = CALayer()
        field.frame = parent.bounds
        field.opacity = 0
        parent.addSublayer(field)

        let cutoutPath = CGMutablePath()
        cutoutPath.addRect(parent.bounds)
        cutoutPath.addRoundedRect(
            in: CGRect(x: 660, y: 360, width: 600, height: 360),
            cornerWidth: 78,
            cornerHeight: 78
        )
        let cutout = CAShapeLayer()
        cutout.frame = parent.bounds
        cutout.path = cutoutPath
        cutout.fillRule = .evenOdd
        cutout.fillColor = NSColor.white.cgColor
        field.mask = cutout

        let presence = CAKeyframeAnimation(keyPath: "opacity")
        presence.values = [0, 1, 1, 0]
        presence.keyTimes = [0, 0.08, 0.90, 1]
        presence.beginTime = AVCoreAnimationBeginTimeAtZero + start
        presence.duration = duration
        presence.fillMode = .both
        presence.isRemovedOnCompletion = false
        field.add(presence, forKey: "scene")

        let halo = CAGradientLayer()
        halo.type = .radial
        halo.frame = CGRect(x: 430, y: 170, width: 1_060, height: 720)
        halo.colors = [
            accent.withAlphaComponent(completed ? 0.21 : 0.17).cgColor,
            blue.withAlphaComponent(0.06).cgColor,
            NSColor.clear.cgColor,
        ]
        halo.locations = [0, 0.50, 1]
        field.addSublayer(halo)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 220, y: 535))
        path.addCurve(
            to: CGPoint(x: 1_700, y: 535),
            control1: CGPoint(x: 590, y: 665),
            control2: CGPoint(x: 1_330, y: 405)
        )

        let glow = CAShapeLayer()
        glow.path = path
        glow.fillColor = NSColor.clear.cgColor
        glow.strokeColor = accent.withAlphaComponent(0.17).cgColor
        glow.lineWidth = 16
        glow.lineCap = .round
        glow.shadowColor = accent.cgColor
        glow.shadowOpacity = 0.34
        glow.shadowRadius = 22
        field.addSublayer(glow)

        let mask = CAShapeLayer()
        mask.path = path
        mask.fillColor = NSColor.clear.cgColor
        mask.strokeColor = NSColor.white.cgColor
        mask.lineWidth = 4
        mask.lineCap = .round

        let ribbon = CAGradientLayer()
        ribbon.frame = parent.bounds
        ribbon.colors = [cyan.cgColor, blue.cgColor, violet.cgColor, accent.cgColor]
        ribbon.locations = [0, 0.36, 0.72, 1]
        ribbon.startPoint = CGPoint(x: 0.08, y: 0.5)
        ribbon.endPoint = CGPoint(x: 0.92, y: 0.5)
        ribbon.mask = mask
        field.addSublayer(ribbon)

        let reveal = CABasicAnimation(keyPath: "strokeEnd")
        reveal.fromValue = 0.12
        reveal.toValue = 1
        reveal.beginTime = AVCoreAnimationBeginTimeAtZero + start + 0.04
        reveal.duration = min(0.72, duration * 0.22)
        reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        reveal.fillMode = .both
        reveal.isRemovedOnCompletion = false
        mask.add(reveal, forKey: "reveal")

        for (index, rect) in [
            CGRect(x: 610, y: 348, width: 700, height: 382),
            CGRect(x: 520, y: 296, width: 880, height: 486),
            CGRect(x: 432, y: 244, width: 1_056, height: 590),
        ].enumerated() {
            let ring = CAShapeLayer()
            ring.path = CGPath(
                roundedRect: rect,
                cornerWidth: rect.height / 2,
                cornerHeight: rect.height / 2,
                transform: nil
            )
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = accent.withAlphaComponent(index == 0 ? 0.27 : 0.14).cgColor
            ring.lineWidth = index == 0 ? 1.6 : 1
            ring.lineDashPattern = index == 0 ? [3, 12] : [2, 20]
            field.addSublayer(ring)

            let orbit = CABasicAnimation(keyPath: "lineDashPhase")
            orbit.fromValue = CGFloat(index * 10)
            orbit.toValue = CGFloat(index * 10 - 90)
            orbit.beginTime = AVCoreAnimationBeginTimeAtZero + start
            orbit.duration = duration
            orbit.fillMode = .both
            orbit.isRemovedOnCompletion = false
            ring.add(orbit, forKey: "orbit")
        }

        let markerText = completed
            ? [("DROP RECEIVED", 236.0), ("HANDOFF READY", 1_454.0)]
            : [("FILE IN MOTION", 236.0), ("TARGET READY", 1_454.0)]
        for (label, x) in markerText {
            let marker = CALayer()
            marker.frame = CGRect(x: x, y: 502, width: 230, height: 68)
            marker.cornerRadius = 22
            marker.backgroundColor = deepNavy.withAlphaComponent(0.76).cgColor
            marker.borderWidth = 1
            marker.borderColor = accent.withAlphaComponent(0.30).cgColor
            marker.addSublayer(textLayer(
                label,
                frame: CGRect(x: 14, y: 21, width: 202, height: 26),
                size: 13,
                weight: .bold,
                color: accent,
                tracking: 2.0,
                alignment: .center
            ))
            field.addSublayer(marker)
        }

        for delay in [0.16, 1.36] where delay < duration - 0.30 {
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
            particle.cornerRadius = 5.5
            particle.backgroundColor = accent.cgColor
            particle.shadowColor = accent.cgColor
            particle.shadowOpacity = 0.9
            particle.shadowRadius = 8
            field.addSublayer(particle)

            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = path
            travel.calculationMode = .paced
            travel.beginTime = AVCoreAnimationBeginTimeAtZero + start + delay
            travel.duration = max(1.6, duration - delay - 0.12)
            travel.fillMode = .both
            travel.isRemovedOnCompletion = false
            particle.add(travel, forKey: "travel")
        }
    }

    private static func addLabel(to parent: CALayer, segment: PreviewSegment, start: Double, duration: Double) {
        let card = CALayer()
        card.frame = segment.labelFrame
        card.cornerRadius = 30
        card.backgroundColor = deepNavy.withAlphaComponent(0.88).cgColor
        card.borderWidth = 1
        card.borderColor = segment.accent.withAlphaComponent(0.24).cgColor
        card.opacity = 0
        addPresence(to: card, start: start, duration: duration, travel: CGPoint(x: 22, y: 0))
        parent.addSublayer(card)

        let centered = segment.labelFrame.minY > 700
        let alignment: NSTextAlignment = centered ? .center : .left
        let inset: CGFloat = centered ? 30 : 28
        card.addSublayer(textLayer(
            segment.number,
            frame: CGRect(x: inset, y: 138, width: segment.labelFrame.width - inset * 2, height: 22),
            size: 13,
            weight: .bold,
            color: segment.accent,
            tracking: 3.4,
            alignment: alignment
        ))
        card.addSublayer(textLayer(
            segment.title,
            frame: CGRect(x: inset, y: 72, width: segment.labelFrame.width - inset * 2, height: 58),
            size: centered ? 42 : 38,
            weight: .bold,
            color: .white,
            alignment: alignment
        ))
        card.addSublayer(textLayer(
            segment.detail,
            frame: CGRect(x: inset, y: 25, width: segment.labelFrame.width - inset * 2, height: 36),
            size: 19,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.72, alpha: 1),
            alignment: alignment
        ))
    }

    private static func addMenu(to parent: CALayer, imageURL: URL, start: Double, duration: Double) {
        guard let image = NSImage(contentsOf: imageURL) else { return }
        let menu = CALayer()
        menu.frame = CGRect(x: 1_030, y: 105, width: 790, height: 815)
        menu.contents = image
        menu.contentsGravity = .resizeAspect
        menu.contentsScale = 2
        menu.opacity = 0
        menu.shadowColor = violet.withAlphaComponent(0.25).cgColor
        menu.shadowOpacity = 0.40
        menu.shadowRadius = 24
        menu.shadowOffset = CGSize(width: 0, height: -8)
        addPresence(to: menu, start: start + 0.04, duration: duration - 0.04, travel: CGPoint(x: 30, y: 0))

        let settle = CAKeyframeAnimation(keyPath: "transform.scale")
        settle.values = [0.96, 1.008, 1]
        settle.keyTimes = [0, 0.74, 1]
        settle.beginTime = AVCoreAnimationBeginTimeAtZero + start + 0.04
        settle.duration = 0.54
        settle.fillMode = .both
        settle.isRemovedOnCompletion = false
        menu.add(settle, forKey: "settle")
        parent.addSublayer(menu)
    }

    private static func addProgress(to parent: CALayer, duration: Double) {
        let track = CALayer()
        track.frame = CGRect(x: 62, y: 28, width: 1_796, height: 3)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        track.cornerRadius = 1.5
        parent.addSublayer(track)

        let progress = CAGradientLayer()
        progress.frame = track.bounds
        progress.colors = [cyan.cgColor, blue.cgColor, violet.cgColor]
        progress.startPoint = CGPoint(x: 0, y: 0.5)
        progress.endPoint = CGPoint(x: 1, y: 0.5)
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.position = CGPoint(x: 0, y: 1.5)
        progress.transform = CATransform3DMakeScale(0.001, 1, 1)
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0.001
        grow.toValue = 1
        grow.beginTime = AVCoreAnimationBeginTimeAtZero
        grow.duration = duration
        grow.fillMode = .both
        grow.isRemovedOnCompletion = false
        progress.add(grow, forKey: "grow")
        track.addSublayer(progress)
    }

    private static func addPresence(to layer: CALayer, start: Double, duration: Double, travel: CGPoint) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.10, 0.88, 1]
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacity.duration = duration
        opacity.fillMode = .both
        opacity.isRemovedOnCompletion = false
        layer.add(opacity, forKey: "presence")

        let move = CABasicAnimation(keyPath: "transform.translation")
        move.fromValue = NSValue(point: travel)
        move.toValue = NSValue(point: .zero)
        move.beginTime = AVCoreAnimationBeginTimeAtZero + start
        move.duration = min(0.48, duration * 0.18)
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        move.fillMode = .both
        move.isRemovedOnCompletion = false
        layer.add(move, forKey: "move")
    }

    private static func textLayer(
        _ text: String,
        frame: CGRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        tracking: CGFloat = 0,
        alignment: NSTextAlignment = .left
    ) -> CALayer {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        let scale: CGFloat = 2
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(frame.width * scale))),
            pixelsHigh: max(1, Int(ceil(frame.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = frame.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: frame.size).fill()
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
        ]).draw(with: CGRect(origin: .zero, size: frame.size), options: [], context: nil)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: frame.size)
        image.addRepresentation(bitmap)
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resizeAspect
        return layer
    }
}
