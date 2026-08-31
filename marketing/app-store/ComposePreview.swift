import AVFoundation
import CoreImage
import Foundation

private let width = 1_920
private let height = 1_080
private let fps: Int32 = 30
private let secondsPerScene = 4.0
private let transitionDuration = 0.65

private let fileManager = FileManager.default
private let scriptURL = URL(fileURLWithPath: #filePath)
private let rootURL = scriptURL.deletingLastPathComponent()
private let finalURL = rootURL.appendingPathComponent("final", isDirectory: true)
private let outputURL = finalURL.appendingPathComponent("airfliq-app-preview.mov")

private let preferredNames = [
    "01-airdrop-one-move.png",
    "02-drag-drop-fliq.png",
    "03-four-ways.png",
    "04-your-shortcut.png",
    "05-seven-day-trial.png",
]

private let sceneURLs = preferredNames
    .map { finalURL.appendingPathComponent($0) }
    .filter { fileManager.fileExists(atPath: $0.path) }

guard sceneURLs.count >= 4 else {
    fputs("Need at least four native App Store screenshots before composing the preview.\n", stderr)
    exit(1)
}

try? fileManager.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 12_000_000,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps * 2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
]

let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
)

guard writer.canAdd(input) else {
    fputs("AVAssetWriter cannot add the video input.\n", stderr)
    exit(1)
}
writer.add(input)

let images = sceneURLs.compactMap { CIImage(contentsOf: $0, options: [.applyOrientationProperty: true]) }
guard images.count == sceneURLs.count else {
    fputs("Could not decode every native screenshot.\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
let context = CIContext(options: [
    .workingColorSpace: colorSpace,
    .outputColorSpace: colorSpace,
    .cacheIntermediates: true,
])
let frameBounds = CGRect(x: 0, y: 0, width: width, height: height)

func smoothstep(_ value: Double) -> Double {
    let x = min(max(value, 0), 1)
    return x * x * (3 - 2 * x)
}

func preparedImage(_ image: CIImage, progress: Double, direction: Double) -> CIImage {
    let source = image.extent
    let fillScale = max(CGFloat(width) / source.width, CGFloat(height) / source.height)
    let zoom = CGFloat(1.0 + 0.028 * smoothstep(progress))
    let scale = fillScale * zoom
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let drift = CGFloat(direction * 22.0 * (smoothstep(progress) - 0.5))
    let x = (CGFloat(width) - scaled.extent.width) / 2 + drift
    let y = (CGFloat(height) - scaled.extent.height) / 2
    return scaled
        .transformed(by: CGAffineTransform(translationX: x - scaled.extent.minX, y: y - scaled.extent.minY))
        .cropped(to: frameBounds)
}

func opacity(_ image: CIImage, _ value: Double) -> CIImage {
    image.applyingFilter("CIColorMatrix", parameters: [
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(value)),
    ])
}

guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "AirFliqPreview", code: 1)
}
writer.startSession(atSourceTime: .zero)

let totalSeconds = secondsPerScene * Double(images.count)
let totalFrames = Int(totalSeconds * Double(fps))
let queue = DispatchQueue(label: "com.airfliq.preview-writer")
let finished = DispatchSemaphore(value: 0)
var frameIndex = 0
var renderingError: Error?

input.requestMediaDataWhenReady(on: queue) {
    while input.isReadyForMoreMediaData && frameIndex < totalFrames {
        autoreleasepool {
            let time = Double(frameIndex) / Double(fps)
            let scenePosition = time / secondsPerScene
            let sceneIndex = min(Int(scenePosition), images.count - 1)
            let localProgress = scenePosition - Double(sceneIndex)
            let direction = sceneIndex.isMultiple(of: 2) ? 1.0 : -1.0
            var frame = preparedImage(images[sceneIndex], progress: localProgress, direction: direction)

            let transitionStart = 1.0 - transitionDuration / secondsPerScene
            if localProgress > transitionStart && sceneIndex + 1 < images.count {
                let transition = smoothstep((localProgress - transitionStart) / (1.0 - transitionStart))
                let next = preparedImage(images[sceneIndex + 1], progress: 0, direction: -direction)
                frame = opacity(next, transition).composited(over: opacity(frame, 1.0 - transition))
            }

            guard let pool = adaptor.pixelBufferPool else {
                renderingError = NSError(domain: "AirFliqPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Pixel buffer pool is unavailable."])
                return
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else {
                renderingError = NSError(domain: "AirFliqPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not allocate a video frame."])
                return
            }

            context.render(frame, to: pixelBuffer, bounds: frameBounds, colorSpace: colorSpace)
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                renderingError = writer.error ?? NSError(domain: "AirFliqPreview", code: 4)
                return
            }
            frameIndex += 1
        }

        if renderingError != nil {
            input.markAsFinished()
            writer.cancelWriting()
            finished.signal()
            return
        }
    }

    if frameIndex >= totalFrames {
        input.markAsFinished()
        writer.finishWriting {
            finished.signal()
        }
    }
}

finished.wait()

if let renderingError {
    throw renderingError
}
guard writer.status == .completed else {
    throw writer.error ?? NSError(domain: "AirFliqPreview", code: 5)
}

print("Created \(outputURL.path) from \(images.count) native Retina scenes, \(Int(totalSeconds)) seconds at \(fps) fps.")
