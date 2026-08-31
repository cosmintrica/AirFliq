import AVFoundation
import Foundation

private enum MixError: Error {
    case missingTrack(String)
    case exportFailed(String)
    case transcodeFailed(Int32)
}

@main
struct MixProductFilm {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let silentURL = root.appendingPathComponent("marketing/shipaton/video/airfliq-product-film-silent.mp4")
        let scoreURL = root.appendingPathComponent("marketing/shipaton/audio/airfliq-original-score.wav")
        let intermediateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airfliq-product-film-mixed.mov")
        let outputURL = root.appendingPathComponent("marketing/shipaton/video/airfliq-shipaton-product-film.mp4")
        let narrationURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }

        let videoAsset = AVURLAsset(url: silentURL)
        let scoreAsset = AVURLAsset(url: scoreURL)
        let duration = try await videoAsset.load(.duration)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw MixError.missingTrack("silent product film")
        }
        guard let sourceScore = try await scoreAsset.loadTracks(withMediaType: .audio).first else {
            throw MixError.missingTrack("original score")
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let scoreTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw MixError.missingTrack("composition") }

        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideo,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        let scoreDuration = try await scoreAsset.load(.duration)
        let usableScoreDuration = CMTimeMinimum(duration, scoreDuration)
        try scoreTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: usableScoreDuration),
            of: sourceScore,
            at: .zero
        )

        let audioMix = AVMutableAudioMix()
        let scoreParameters = AVMutableAudioMixInputParameters(track: scoreTrack)
        let hasNarration = narrationURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let scoreLevel: Float = hasNarration ? 0.36 : 1.0
        scoreParameters.setVolumeRamp(
            fromStartVolume: 0,
            toEndVolume: scoreLevel,
            timeRange: CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 1.15, preferredTimescale: 600)
            )
        )
        scoreParameters.setVolume(scoreLevel, at: CMTime(seconds: 1.15, preferredTimescale: 600))
        scoreParameters.setVolumeRamp(
            fromStartVolume: scoreLevel,
            toEndVolume: 0,
            timeRange: CMTimeRange(
                start: CMTimeSubtract(duration, CMTime(seconds: 2.25, preferredTimescale: 600)),
                duration: CMTime(seconds: 2.25, preferredTimescale: 600)
            )
        )

        var mixParameters: [AVAudioMixInputParameters] = [scoreParameters]
        if let narrationURL, hasNarration {
            let narrationAsset = AVURLAsset(url: narrationURL)
            guard let sourceNarration = try await narrationAsset.loadTracks(withMediaType: .audio).first,
                  let narrationTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { throw MixError.missingTrack("narration") }
            let narrationDuration = try await narrationAsset.load(.duration)
            try narrationTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, narrationDuration)),
                of: sourceNarration,
                at: .zero
            )
            let narrationParameters = AVMutableAudioMixInputParameters(track: narrationTrack)
            narrationParameters.setVolume(0.96, at: .zero)
            mixParameters.append(narrationParameters)
        }
        audioMix.inputParameters = mixParameters

        try? FileManager.default.removeItem(at: intermediateURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MixError.exportFailed("Could not create the export session")
        }
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: intermediateURL, as: .mov)

        try? FileManager.default.removeItem(at: outputURL)
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", intermediateURL.path,
            "-map", "0:v:0", "-map", "0:a:0",
            "-c:v", "copy",
            "-af", "loudnorm=I=-16:LRA=7:TP=-1.5",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
            "-movflags", "+faststart",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: intermediateURL)
        guard process.terminationStatus == 0 else {
            throw MixError.transcodeFailed(process.terminationStatus)
        }

        print("Created \(outputURL.path)")
        print(hasNarration ? "Mixed original score and supplied narration." : "Mixed original score with voiceover headroom preserved.")
        print("Normalized final audio to -16 LUFS with a -1.5 dB true-peak ceiling.")
    }
}
