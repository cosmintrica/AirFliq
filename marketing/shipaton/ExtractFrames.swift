import AppKit
import AVFoundation
import Foundation

@main
struct ExtractFrames {
    static func main() async throws {
        guard CommandLine.arguments.count >= 4 else {
            throw NSError(domain: "ExtractFrames", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "usage: ExtractFrames VIDEO OUTPUT_DIR SECOND..."])
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for value in CommandLine.arguments.dropFirst(3) {
            guard let second = Double(value) else { continue }
            let time = CMTime(seconds: second, preferredTimescale: 600)
            let image = try await generator.image(at: time).image
            let bitmap = NSBitmapImageRep(cgImage: image)
            let data = bitmap.representation(using: .png, properties: [:])!
            let name = String(format: "frame-%05.1f.png", second)
            try data.write(to: output.appendingPathComponent(name), options: .atomic)
        }
    }
}
