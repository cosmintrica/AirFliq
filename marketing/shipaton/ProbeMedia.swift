import AVFoundation
import Foundation

@main
struct ProbeMedia {
    static func main() async throws {
        for argument in CommandLine.arguments.dropFirst() {
            let asset = AVURLAsset(url: URL(fileURLWithPath: argument))
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                print("\(argument)\tno video track")
                continue
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: size).applying(transform).standardized
            let fps = try await track.load(.nominalFrameRate)
            print("\(argument)\t\(CMTimeGetSeconds(duration))s\t\(Int(transformed.width))x\(Int(transformed.height))\t\(fps)fps")
        }
    }
}
