import AVFoundation
import Foundation

@main
enum MixNarration {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let videoURL = root.appendingPathComponent("marketing/shipaton/video/airfliq-demo-draft.mp4")
        let audioURL = root.appendingPathComponent("marketing/shipaton/audio/airfliq-shipaton-voiceover-openai.m4a")
        let outputURL = root.appendingPathComponent("marketing/shipaton/video/airfliq-shipaton-final.mp4")

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AirFliqVideo", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing video or narration track"])
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "AirFliqVideo", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create composition tracks"])
        }

        let duration = try await videoAsset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                       of: sourceVideo, at: .zero)
        let audioDuration = min(duration, try await audioAsset.load(.duration))
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration),
                                       of: sourceAudio, at: .zero)

        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "AirFliqVideo", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)
        print(outputURL.path)
    }
}
