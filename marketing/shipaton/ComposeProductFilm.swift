import AppKit
import AVFoundation
import CoreMedia
import QuartzCore

private enum FilmError: Error {
    case missingTrack(String)
    case missingAsset(String)
    case exportFailed(String)
}

private enum Stage {
    case fill
    case centered(CGSize)
    case left(CGSize)
    case right(CGSize)
}

private struct Segment {
    let file: String
    let sourceStart: Double
    let sourceDuration: Double
    let outputDuration: Double
    let crop: NSEdgeInsets
    let stage: Stage
    let kicker: String
    let title: String
    let subtitle: String
    let accent: NSColor
    let copyFrame: CGRect?
    let dimVideo: Bool
    let menuOverlay: Bool
    let voiceoverMarker: String
}

@main
struct ComposeProductFilm {
    private static let renderSize = CGSize(width: 1_920, height: 1_080)
    private static let frameRate: CMTimeScale = 60
    private static let deepNavy = NSColor(calibratedRed: 0.009, green: 0.022, blue: 0.066, alpha: 1)
    private static let cyan = NSColor(calibratedRed: 0.13, green: 0.80, blue: 1.00, alpha: 1)
    private static let blue = NSColor(calibratedRed: 0.12, green: 0.48, blue: 1.00, alpha: 1)
    private static let violet = NSColor(calibratedRed: 0.49, green: 0.25, blue: 1.00, alpha: 1)

    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let raw = root.appendingPathComponent("marketing/shipaton/video/raw", isDirectory: true)
        let iconURL = root.appendingPathComponent("marketing/shipaton/assets/airfliq-icon-1024.png")
        let menuURL = root.appendingPathComponent("marketing/app-store/native/menu-panel.png")
        let output = root.appendingPathComponent("marketing/shipaton/video/airfliq-product-film-silent.mp4")

        for url in [iconURL, menuURL] where !FileManager.default.fileExists(atPath: url.path) {
            throw FilmError.missingAsset(url.path)
        }

        // The score is exactly 49.98 seconds. The picture is cut to the same duration so
        // narration can be added later without retiming the product beats.
        let segments = [
            Segment(
                file: "01-ready.mov", sourceStart: 0, sourceDuration: 3.5, outputDuration: 3.5,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .centered(CGSize(width: 1_180, height: 1_000)),
                kicker: "AIRFLIQ FOR MACOS", title: "AirDrop. One move.",
                subtitle: "Four ways. One native panel.", accent: cyan,
                copyFrame: CGRect(x: 260, y: 270, width: 1_400, height: 470),
                dimVideo: true, menuOverlay: false,
                voiceoverMarker: "AirDrop, in one move. Meet AirFliq for macOS."
            ),
            Segment(
                file: "01-ready.mov", sourceStart: 1.0, sourceDuration: 5.5, outputDuration: 5.5,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .centered(CGSize(width: 1_180, height: 1_000)),
                kicker: "ONE SETUP", title: "Ready when\nyou are.",
                subtitle: "Choose access once. Keep every send native.", accent: cyan,
                copyFrame: CGRect(x: 58, y: 326, width: 540, height: 410),
                dimVideo: false, menuOverlay: false,
                voiceoverMarker: "A short, transparent setup keeps you in control."
            ),
            Segment(
                file: "02-shortcut.mov", sourceStart: 2.0, sourceDuration: 9.0, outputDuration: 9.0,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .right(CGSize(width: 1_160, height: 1_000)),
                kicker: "GLOBAL SHORTCUT", title: "Your shortcut.\nYour way.",
                subtitle: "Pick a preset or record your own combination.", accent: violet,
                copyFrame: CGRect(x: 76, y: 338, width: 540, height: 390),
                dimVideo: false, menuOverlay: false,
                voiceoverMarker: "Launch AirDrop with a preset or any safe global shortcut."
            ),
            Segment(
                file: "03-drag-hover.mov", sourceStart: 0, sourceDuration: 6.0, outputDuration: 6.0,
                crop: NSEdgeInsets(top: 4, left: 6, bottom: 8, right: 6),
                // The capture is 452 by 240 pixels. Keep its rendered scale below
                // 1.25x so the real hover interaction stays crisp at 1080p.
                stage: .centered(CGSize(width: 540, height: 280)),
                kicker: "MAGNETIC DRAG", title: "Pick up any file.",
                subtitle: "AirFliq meets your cursor.", accent: cyan,
                copyFrame: CGRect(x: 320, y: 790, width: 1_280, height: 260),
                dimVideo: false, menuOverlay: false,
                voiceoverMarker: "Or simply drag. The send target appears beside your cursor."
            ),
            Segment(
                file: "04-drag-complete.mov", sourceStart: 0, sourceDuration: 5.95, outputDuration: 5.95,
                crop: NSEdgeInsets(top: 3, left: 4, bottom: 6, right: 4),
                // 530 by 260 keeps the 440 by 220 capture under 1.25x even at
                // the end of the subtle camera move.
                stage: .centered(CGSize(width: 530, height: 260)),
                kicker: "DROP FEEDBACK", title: "Drop. Confirmed.",
                subtitle: "Clear feedback, then the native AirDrop handoff.", accent: NSColor.systemGreen,
                copyFrame: CGRect(x: 320, y: 790, width: 1_280, height: 260),
                dimVideo: false, menuOverlay: false,
                voiceoverMarker: "Drop, get immediate feedback, then continue in native AirDrop."
            ),
            Segment(
                file: "01-ready.mov", sourceStart: 0, sourceDuration: 4.5, outputDuration: 4.5,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .fill,
                kicker: "MENU BAR", title: "Everything close.\nNothing in the way.",
                subtitle: "Send, configure and restore from one focused menu.", accent: violet,
                copyFrame: CGRect(x: 100, y: 320, width: 700, height: 400),
                dimVideo: true, menuOverlay: true,
                voiceoverMarker: "Shortcut, right-click, menu bar, or drag. Pick the path that fits."
            ),
            Segment(
                file: "05-paywall.mov", sourceStart: 1.0, sourceDuration: 8.0, outputDuration: 8.0,
                crop: NSEdgeInsets(top: 76, left: 70, bottom: 142, right: 70),
                stage: .right(CGSize(width: 1_000, height: 1_010)),
                kicker: "AIRFLIQ PRO", title: "Seven days.\nEvery feature.",
                subtitle: "Then $4.99 once. No subscription. RevenueCat powers Pro access.", accent: cyan,
                copyFrame: CGRect(x: 76, y: 314, width: 690, height: 430),
                dimVideo: false, menuOverlay: false,
                voiceoverMarker: "Try every feature for seven days, then unlock AirFliq once for four ninety-nine."
            ),
            Segment(
                file: "01-ready.mov", sourceStart: 4.0, sourceDuration: 3.98, outputDuration: 7.53,
                crop: NSEdgeInsets(top: 80, left: 105, bottom: 168, right: 105),
                stage: .centered(CGSize(width: 1_180, height: 1_000)),
                kicker: "SELECT. FLIQ. SENT.", title: "Built for the way you work.",
                subtitle: "AirFliq for macOS. Built in public for Shipaton.", accent: violet,
                copyFrame: CGRect(x: 260, y: 270, width: 1_400, height: 470),
                dimVideo: true, menuOverlay: false,
                voiceoverMarker: "AirFliq. Select. Fliq. Sent."
            ),
        ]

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw FilmError.missingTrack("composition") }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)

        var cursor = CMTime.zero
        var sceneRanges: [CMTimeRange] = []
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for segment in segments {
            let sourceURL = segment.file.hasPrefix("/")
                ? URL(fileURLWithPath: segment.file)
                : raw.appendingPathComponent(segment.file)
            let asset = AVURLAsset(url: sourceURL)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw FilmError.missingTrack(segment.file)
            }

            let sourceStart = CMTime(seconds: segment.sourceStart, preferredTimescale: 600)
            let sourceDuration = CMTime(seconds: segment.sourceDuration, preferredTimescale: 600)
            let outputDuration = CMTime(seconds: segment.outputDuration, preferredTimescale: 600)
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
            try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: cursor)
            if sourceDuration != outputDuration {
                compositionTrack.scaleTimeRange(
                    CMTimeRange(start: cursor, duration: sourceDuration),
                    toDuration: outputDuration
                )
            }

            let timeRange = CMTimeRange(start: cursor, duration: outputDuration)
            sceneRanges.append(timeRange)

            let natural = try await sourceTrack.load(.naturalSize)
            let preferred = try await sourceTrack.load(.preferredTransform)
            let oriented = CGRect(origin: .zero, size: natural).applying(preferred).standardized.size
            let crop = CGRect(
                x: segment.crop.left,
                y: segment.crop.bottom,
                width: max(1, oriented.width - segment.crop.left - segment.crop.right),
                height: max(1, oriented.height - segment.crop.top - segment.crop.bottom)
            )
            let target = targetRect(for: segment.stage, content: crop.size)
            let startTransform = transform(crop: crop, target: target, zoom: 0.988)
            let endTransform = transform(crop: crop, target: target, zoom: 1.018)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            instruction.backgroundColor = NSColor.clear.cgColor

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setCropRectangle(crop, at: cursor)
            layer.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: timeRange)

            let fade = min(0.32, segment.outputDuration * 0.08)
            let fadeIn = CMTimeRange(
                start: cursor,
                duration: CMTime(seconds: fade, preferredTimescale: 600)
            )
            let fadeOut = CMTimeRange(
                start: CMTimeSubtract(CMTimeRangeGetEnd(timeRange), fadeIn.duration),
                duration: fadeIn.duration
            )
            let targetOpacity: Float = segment.dimVideo ? (segment.menuOverlay ? 0.08 : 0.24) : 1.0
            layer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: targetOpacity, timeRange: fadeIn)
            layer.setOpacityRamp(fromStartOpacity: targetOpacity, toEndOpacity: 0, timeRange: fadeOut)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = CMTimeRangeGetEnd(timeRange)
        }

        videoComposition.instructions = instructions
        let totalDuration = CMTimeGetSeconds(cursor)

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        parent.backgroundColor = deepNavy.cgColor
        parent.masksToBounds = true

        addBackground(to: parent, duration: totalDuration)

        let videoLayer = CALayer()
        videoLayer.frame = parent.bounds
        parent.addSublayer(videoLayer)

        // The composited source contributes opaque black outside its crop, so
        // the magnetic field is placed above it with a cutout over the real
        // capture. This keeps every source pixel untouched and crisp.
        let dragBackdrops = CALayer()
        dragBackdrops.frame = parent.bounds
        parent.addSublayer(dragBackdrops)
        for index in [3, 4] {
            let range = sceneRanges[index]
            addDragBackdrop(
                to: dragBackdrops,
                accent: segments[index].accent,
                start: CMTimeGetSeconds(range.start),
                duration: CMTimeGetSeconds(range.duration),
                completed: index == 4
            )
        }

        for (index, range) in sceneRanges.enumerated() {
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            let segment = segments[index]
            if let copyFrame = segment.copyFrame {
                addSceneCopy(
                    to: parent,
                    segment: segment,
                    sceneNumber: index + 1,
                    frame: copyFrame,
                    start: start,
                    duration: duration
                )
            }
            if segment.menuOverlay {
                addMenuMoment(to: parent, menuURL: menuURL, start: start, duration: duration)
            }
        }

        addBrandBug(to: parent, iconURL: iconURL, duration: totalDuration)
        addProgress(to: parent, duration: totalDuration)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parent
        )

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            throw FilmError.exportFailed("Could not create the export session")
        }
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: output, as: .mp4)

        print("Created \(output.path)")
        print(String(format: "Picture duration: %.2f seconds at 60 fps", totalDuration))
        print("Voiceover timeline:")
        for (index, range) in sceneRanges.enumerated() {
            let start = CMTimeGetSeconds(range.start)
            print(String(format: "  %05.2f  %@", start, segments[index].voiceoverMarker))
        }
    }

    private static func targetRect(for stage: Stage, content: CGSize) -> CGRect {
        switch stage {
        case .fill:
            return CGRect(origin: .zero, size: renderSize)
        case .centered(let maximum):
            let size = aspectFit(content, in: maximum)
            return CGRect(
                x: (renderSize.width - size.width) / 2,
                y: (renderSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        case .left(let maximum):
            let size = aspectFit(content, in: maximum)
            return CGRect(x: 92, y: (renderSize.height - size.height) / 2, width: size.width, height: size.height)
        case .right(let maximum):
            let size = aspectFit(content, in: maximum)
            return CGRect(
                x: renderSize.width - size.width - 72,
                y: (renderSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func aspectFit(_ source: CGSize, in maximum: CGSize) -> CGSize {
        let scale = min(maximum.width / source.width, maximum.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private static func transform(crop: CGRect, target: CGRect, zoom: CGFloat) -> CGAffineTransform {
        let scale = min(target.width / crop.width, target.height / crop.height) * zoom
        let scaled = CGSize(width: crop.width * scale, height: crop.height * scale)
        let x = target.midX - scaled.width / 2
        let y = target.midY - scaled.height / 2
        return CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: x - crop.minX * scale,
            ty: y - crop.minY * scale
        )
    }

    private static func addBackground(to parent: CALayer, duration: Double) {
        let gradient = CAGradientLayer()
        gradient.frame = parent.bounds
        gradient.colors = [
            NSColor(calibratedRed: 0.015, green: 0.052, blue: 0.14, alpha: 1).cgColor,
            deepNavy.cgColor,
            NSColor(calibratedRed: 0.075, green: 0.020, blue: 0.135, alpha: 1).cgColor,
        ]
        gradient.locations = [0, 0.54, 1]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        parent.addSublayer(gradient)

        addOrb(
            to: parent,
            frame: CGRect(x: -260, y: 520, width: 820, height: 820),
            color: blue.withAlphaComponent(0.15),
            drift: CGPoint(x: 170, y: -70),
            duration: duration
        )
        addOrb(
            to: parent,
            frame: CGRect(x: 1_400, y: -230, width: 760, height: 760),
            color: violet.withAlphaComponent(0.14),
            drift: CGPoint(x: -140, y: 90),
            duration: duration
        )

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -120, y: 170))
        path.addCurve(
            to: CGPoint(x: 2_020, y: 280),
            control1: CGPoint(x: 520, y: 430),
            control2: CGPoint(x: 1_250, y: -60)
        )
        for (offset, color, width) in [(0.0, cyan, 2.0), (14.0, blue, 1.4), (-16.0, violet, 1.6)] {
            let ribbon = CAShapeLayer()
            var translation = CGAffineTransform(translationX: 0, y: offset)
            let shifted = path.copy(using: &translation) ?? path
            ribbon.path = shifted
            ribbon.fillColor = NSColor.clear.cgColor
            ribbon.strokeColor = color.withAlphaComponent(0.24).cgColor
            ribbon.lineWidth = width
            ribbon.lineCap = .round
            ribbon.lineDashPattern = [10, 24]
            parent.addSublayer(ribbon)

            let phase = CABasicAnimation(keyPath: "lineDashPhase")
            phase.fromValue = 0
            phase.toValue = -680
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
        presence.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]
        presence.fillMode = .both
        presence.isRemovedOnCompletion = false
        field.add(presence, forKey: "scene")

        let halo = CAGradientLayer()
        halo.type = .radial
        halo.frame = CGRect(x: 410, y: 155, width: 1_100, height: 760)
        halo.colors = [
            accent.withAlphaComponent(completed ? 0.22 : 0.18).cgColor,
            blue.withAlphaComponent(0.07).cgColor,
            NSColor.clear.cgColor,
        ]
        halo.locations = [0, 0.52, 1]
        field.addSublayer(halo)

        let haloBreath = CAKeyframeAnimation(keyPath: "transform.scale")
        haloBreath.values = [0.94, 1.035, 0.985]
        haloBreath.keyTimes = [0, 0.55, 1]
        haloBreath.beginTime = AVCoreAnimationBeginTimeAtZero + start
        haloBreath.duration = duration
        haloBreath.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        haloBreath.fillMode = .both
        haloBreath.isRemovedOnCompletion = false
        halo.add(haloBreath, forKey: "breath")

        let flowPath = CGMutablePath()
        flowPath.move(to: CGPoint(x: 210, y: 540))
        flowPath.addCurve(
            to: CGPoint(x: 1_710, y: 540),
            control1: CGPoint(x: 580, y: 675),
            control2: CGPoint(x: 1_330, y: 405)
        )

        let glow = CAShapeLayer()
        glow.path = flowPath
        glow.fillColor = NSColor.clear.cgColor
        glow.strokeColor = accent.withAlphaComponent(0.18).cgColor
        glow.lineWidth = 18
        glow.lineCap = .round
        glow.shadowColor = accent.cgColor
        glow.shadowOpacity = 0.35
        glow.shadowRadius = 24
        field.addSublayer(glow)

        let ribbonMask = CAShapeLayer()
        ribbonMask.path = flowPath
        ribbonMask.fillColor = NSColor.clear.cgColor
        ribbonMask.strokeColor = NSColor.white.cgColor
        ribbonMask.lineWidth = 4
        ribbonMask.lineCap = .round
        ribbonMask.strokeEnd = 1

        let ribbon = CAGradientLayer()
        ribbon.frame = parent.bounds
        ribbon.colors = [cyan.cgColor, blue.cgColor, violet.cgColor, accent.cgColor]
        ribbon.locations = [0, 0.36, 0.72, 1]
        ribbon.startPoint = CGPoint(x: 0.08, y: 0.5)
        ribbon.endPoint = CGPoint(x: 0.92, y: 0.5)
        ribbon.mask = ribbonMask
        field.addSublayer(ribbon)

        let reveal = CABasicAnimation(keyPath: "strokeEnd")
        reveal.fromValue = 0.12
        reveal.toValue = 1
        reveal.beginTime = AVCoreAnimationBeginTimeAtZero + start + 0.08
        reveal.duration = min(1.05, duration * 0.22)
        reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        reveal.fillMode = .both
        reveal.isRemovedOnCompletion = false
        ribbonMask.add(reveal, forKey: "reveal")

        for (index, rect) in [
            CGRect(x: 602, y: 346, width: 716, height: 388),
            CGRect(x: 520, y: 298, width: 880, height: 484),
            CGRect(x: 436, y: 250, width: 1_048, height: 580),
        ].enumerated() {
            let ring = CAShapeLayer()
            ring.path = CGPath(
                roundedRect: rect,
                cornerWidth: rect.height / 2,
                cornerHeight: rect.height / 2,
                transform: nil
            )
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = accent.withAlphaComponent(index == 0 ? 0.28 : 0.15).cgColor
            ring.lineWidth = index == 0 ? 1.7 : 1.1
            ring.lineDashPattern = index == 0 ? [3, 12] : [2, 20]
            field.addSublayer(ring)

            let phase = CABasicAnimation(keyPath: "lineDashPhase")
            phase.fromValue = CGFloat(index * 12)
            phase.toValue = CGFloat(index * 12 - 120)
            phase.beginTime = AVCoreAnimationBeginTimeAtZero + start
            phase.duration = duration
            phase.fillMode = .both
            phase.isRemovedOnCompletion = false
            ring.add(phase, forKey: "orbit")
        }

        let markerText = completed
            ? [("DROP RECEIVED", 230.0), ("NATIVE HANDOFF", 1_452.0)]
            : [("FILE IN MOTION", 230.0), ("TARGET READY", 1_452.0)]
        for (label, x) in markerText {
            let marker = CALayer()
            marker.frame = CGRect(x: x, y: 500, width: 238, height: 80)
            marker.cornerRadius = 25
            marker.backgroundColor = deepNavy.withAlphaComponent(0.72).cgColor
            marker.borderWidth = 1
            marker.borderColor = accent.withAlphaComponent(0.30).cgColor
            marker.addSublayer(renderedText(
                label,
                frame: CGRect(x: 16, y: 26, width: 206, height: 28),
                size: 14,
                weight: .bold,
                color: accent,
                tracking: 2.2,
                alignment: .center
            ))
            field.addSublayer(marker)
        }

        for delay in [0.22, 1.48, 2.72] where delay < duration - 0.4 {
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
            particle.cornerRadius = 6
            particle.backgroundColor = accent.cgColor
            particle.shadowColor = accent.cgColor
            particle.shadowOpacity = 0.9
            particle.shadowRadius = 9
            field.addSublayer(particle)

            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = flowPath
            travel.calculationMode = .paced
            travel.beginTime = AVCoreAnimationBeginTimeAtZero + start + delay
            travel.duration = max(1.7, duration - delay - 0.16)
            travel.fillMode = .both
            travel.isRemovedOnCompletion = false
            particle.add(travel, forKey: "travel")
        }
    }

    private static func addOrb(
        to parent: CALayer,
        frame: CGRect,
        color: NSColor,
        drift: CGPoint,
        duration: Double
    ) {
        let orb = CAGradientLayer()
        orb.type = .radial
        orb.frame = frame
        orb.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
        orb.locations = [0, 1]
        parent.addSublayer(orb)

        let motion = CABasicAnimation(keyPath: "transform.translation")
        motion.fromValue = NSValue(point: .zero)
        motion.toValue = NSValue(point: drift)
        motion.beginTime = AVCoreAnimationBeginTimeAtZero
        motion.duration = duration
        motion.autoreverses = true
        motion.repeatCount = 1
        motion.fillMode = .both
        motion.isRemovedOnCompletion = false
        orb.add(motion, forKey: "drift")
    }

    private static func addSceneCopy(
        to parent: CALayer,
        segment: Segment,
        sceneNumber: Int,
        frame: CGRect,
        start: Double,
        duration: Double
    ) {
        let isHero = sceneNumber == 1 || segment.kicker == "SELECT. FLIQ. SENT."
        let isCompact = frame.height < 300
        let textAlignment: NSTextAlignment = (isHero || isCompact) ? .center : .left
        let plate = CALayer()
        plate.frame = frame.insetBy(dx: -28, dy: -22)
        plate.backgroundColor = deepNavy.withAlphaComponent(isHero ? 0.84 : 0.78).cgColor
        plate.cornerRadius = isHero ? 48 : 38
        plate.borderWidth = 1
        plate.borderColor = segment.accent.withAlphaComponent(0.20).cgColor
        plate.opacity = 0
        animatePresence(plate, start: start, duration: duration, travel: CGPoint(x: -34, y: 0))
        parent.addSublayer(plate)

        let kickerText = isHero ? segment.kicker : String(format: "%02d  %@", sceneNumber, segment.kicker)
        let kickerFrame = CGRect(x: frame.minX, y: frame.maxY - 34, width: frame.width, height: 30)
        let titleFrame: CGRect
        let subtitleFrame: CGRect
        let titleSize: CGFloat
        if isHero {
            titleFrame = CGRect(x: frame.minX, y: frame.minY + 150, width: frame.width, height: 190)
            subtitleFrame = CGRect(x: frame.minX, y: frame.minY + 64, width: frame.width, height: 70)
            titleSize = 92
        } else if isCompact {
            titleFrame = CGRect(x: frame.minX, y: frame.minY + 78, width: frame.width, height: 118)
            subtitleFrame = CGRect(x: frame.minX, y: frame.minY + 18, width: frame.width, height: 52)
            titleSize = 68
        } else {
            titleFrame = CGRect(x: frame.minX, y: frame.minY + 130, width: frame.width, height: frame.height - 190)
            subtitleFrame = CGRect(x: frame.minX, y: frame.minY + 20, width: frame.width, height: 90)
            titleSize = frame.width < 600 ? 68 : 72
        }

        let kicker = renderedText(
            kickerText,
            frame: kickerFrame,
            size: 16,
            weight: .bold,
            color: segment.accent,
            tracking: 3.6,
            alignment: textAlignment
        )
        let title = renderedText(
            segment.title,
            frame: titleFrame,
            size: titleSize,
            weight: .heavy,
            color: .white,
            wrapped: true,
            alignment: textAlignment
        )
        let subtitle = renderedText(
            segment.subtitle,
            frame: subtitleFrame,
            size: isHero ? 30 : 25,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.75, alpha: 1),
            wrapped: true,
            alignment: textAlignment
        )

        for (index, layer) in [kicker, title, subtitle].enumerated() {
            layer.opacity = 0
            animatePresence(
                layer,
                start: start + 0.10 + Double(index) * 0.07,
                duration: max(0.4, duration - 0.10 - Double(index) * 0.07),
                travel: CGPoint(x: 24, y: 0)
            )
            parent.addSublayer(layer)
        }
    }

    private static func addMenuMoment(to parent: CALayer, menuURL: URL, start: Double, duration: Double) {
        guard let image = NSImage(contentsOf: menuURL) else { return }
        let panel = CALayer()
        panel.frame = CGRect(x: 980, y: 100, width: 840, height: 865)
        panel.contents = image
        panel.contentsGravity = .resizeAspect
        panel.contentsScale = 2
        panel.opacity = 0
        panel.shadowColor = cyan.withAlphaComponent(0.22).cgColor
        panel.shadowOpacity = 0.45
        panel.shadowRadius = 32
        panel.shadowOffset = CGSize(width: 0, height: -10)

        animatePresence(panel, start: start + 0.08, duration: duration - 0.08, travel: CGPoint(x: 42, y: 0))

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.94, 1.012, 1.0]
        scale.keyTimes = [0, 0.72, 1]
        scale.beginTime = AVCoreAnimationBeginTimeAtZero + start + 0.08
        scale.duration = 0.72
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        scale.fillMode = .both
        scale.isRemovedOnCompletion = false
        panel.add(scale, forKey: "settle")
        parent.addSublayer(panel)
    }

    private static func addBrandBug(to parent: CALayer, iconURL: URL, duration: Double) {
        let capsule = CALayer()
        capsule.frame = CGRect(x: 72, y: 956, width: 276, height: 72)
        capsule.backgroundColor = deepNavy.withAlphaComponent(0.68).cgColor
        capsule.cornerRadius = 25
        capsule.borderWidth = 1
        capsule.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        parent.addSublayer(capsule)

        if let image = NSImage(contentsOf: iconURL) {
            let icon = CALayer()
            icon.frame = CGRect(x: 12, y: 10, width: 52, height: 52)
            icon.contents = image
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = 2
            capsule.addSublayer(icon)
        }
        capsule.addSublayer(renderedText(
            "AIRFLIQ",
            frame: CGRect(x: 78, y: 31, width: 180, height: 25),
            size: 17,
            weight: .bold,
            color: .white,
            tracking: 3.2
        ))
        capsule.addSublayer(renderedText(
            "SELECT. FLIQ. SENT.",
            frame: CGRect(x: 78, y: 11, width: 190, height: 18),
            size: 10,
            weight: .semibold,
            color: NSColor(calibratedWhite: 0.62, alpha: 1),
            tracking: 1.15
        ))

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.025, 0.95, 1]
        fade.beginTime = AVCoreAnimationBeginTimeAtZero
        fade.duration = duration
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        capsule.add(fade, forKey: "film")
    }

    private static func addProgress(to parent: CALayer, duration: Double) {
        let track = CALayer()
        track.frame = CGRect(x: 72, y: 38, width: 1_776, height: 3)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        track.cornerRadius = 1.5
        parent.addSublayer(track)

        let progress = CAGradientLayer()
        progress.frame = track.bounds
        progress.colors = [cyan.cgColor, blue.cgColor, violet.cgColor]
        progress.locations = [0, 0.55, 1]
        progress.startPoint = CGPoint(x: 0, y: 0.5)
        progress.endPoint = CGPoint(x: 1, y: 0.5)
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.position = CGPoint(x: 0, y: 1.5)
        progress.cornerRadius = 1.5
        progress.transform = CATransform3DMakeScale(0.001, 1, 1)

        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0.001
        grow.toValue = 1
        grow.beginTime = AVCoreAnimationBeginTimeAtZero
        grow.duration = duration
        grow.fillMode = .both
        grow.isRemovedOnCompletion = false
        progress.add(grow, forKey: "progress")
        track.addSublayer(progress)
    }

    private static func animatePresence(
        _ layer: CALayer,
        start: Double,
        duration: Double,
        travel: CGPoint
    ) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.11, 0.86, 1]
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
        opacity.duration = duration
        opacity.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]
        opacity.fillMode = .both
        opacity.isRemovedOnCompletion = false
        layer.add(opacity, forKey: "opacity")

        let move = CABasicAnimation(keyPath: "transform.translation")
        move.fromValue = NSValue(point: travel)
        move.toValue = NSValue(point: .zero)
        move.beginTime = AVCoreAnimationBeginTimeAtZero + start
        move.duration = min(0.68, duration * 0.20)
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        move.fillMode = .both
        move.isRemovedOnCompletion = false
        layer.add(move, forKey: "move")
    }

    private static func renderedText(
        _ text: String,
        frame: CGRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        tracking: CGFloat = 0,
        wrapped: Bool = false,
        alignment: NSTextAlignment = .left
    ) -> CALayer {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = wrapped ? .byWordWrapping : .byClipping
        paragraph.minimumLineHeight = size * 1.04
        paragraph.maximumLineHeight = size * 1.08

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
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph,
        ]).draw(
            with: CGRect(origin: .zero, size: frame.size),
            options: wrapped ? [.usesLineFragmentOrigin, .usesFontLeading] : [],
            context: nil
        )
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
