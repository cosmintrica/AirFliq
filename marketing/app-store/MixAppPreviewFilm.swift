import AVFoundation
import Foundation

private enum PreviewMixError: Error {
    case missingTrack(String)
    case exportFailed(String)
    case transcodeFailed(Int32)
}

@main
struct MixAppPreviewFilm {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let silentURL = root.appendingPathComponent("marketing/app-store/final/airfliq-app-preview-29s-silent.mp4")
        let scoreURL = root.appendingPathComponent("marketing/shipaton/audio/airfliq-original-score.wav")
        let intermediateURL = root.appendingPathComponent("marketing/app-store/final/airfliq-app-preview-29s-mixed.mov")
        let outputURL = root.appendingPathComponent("marketing/app-store/final/airfliq-app-preview-29s.mp4")
        let narrationURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        let hasNarration = narrationURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        let videoAsset = AVURLAsset(url: silentURL)
        let scoreAsset = AVURLAsset(url: scoreURL)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceScore = try await scoreAsset.loadTracks(withMediaType: .audio).first else {
            throw PreviewMixError.missingTrack("preview picture or score")
        }
        let duration = try await videoAsset.load(.duration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let scoreTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw PreviewMixError.missingTrack("composition") }

        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        try scoreTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceScore, at: .zero)

        let audioMix = AVMutableAudioMix()
        let scoreParameters = AVMutableAudioMixInputParameters(track: scoreTrack)
        let scoreLevel: Float = hasNarration ? 0.34 : 1
        scoreParameters.setVolumeRamp(
            fromStartVolume: 0,
            toEndVolume: scoreLevel,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 0.8, preferredTimescale: 600))
        )
        scoreParameters.setVolume(scoreLevel, at: CMTime(seconds: 0.8, preferredTimescale: 600))
        scoreParameters.setVolumeRamp(
            fromStartVolume: scoreLevel,
            toEndVolume: 0,
            timeRange: CMTimeRange(
                start: CMTimeSubtract(duration, CMTime(seconds: 1.3, preferredTimescale: 600)),
                duration: CMTime(seconds: 1.3, preferredTimescale: 600)
            )
        )

        var parameters: [AVAudioMixInputParameters] = [scoreParameters]
        if let narrationURL, hasNarration {
            let narrationAsset = AVURLAsset(url: narrationURL)
            guard let sourceNarration = try await narrationAsset.loadTracks(withMediaType: .audio).first,
                  let narrationTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { throw PreviewMixError.missingTrack("narration") }
            let narrationDuration = CMTimeMinimum(duration, try await narrationAsset.load(.duration))
            try narrationTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: narrationDuration),
                of: sourceNarration,
                at: .zero
            )
            let narrationParameters = AVMutableAudioMixInputParameters(track: narrationTrack)
            narrationParameters.setVolume(0.96, at: .zero)
            parameters.append(narrationParameters)
        }
        audioMix.inputParameters = parameters

        try? FileManager.default.removeItem(at: intermediateURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PreviewMixError.exportFailed("Could not create audio mix export")
        }
        exporter.audioMix = audioMix
        try await exporter.export(to: intermediateURL, as: .mov)

        try? FileManager.default.removeItem(at: outputURL)
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", intermediateURL.path,
            "-map", "0:v:0", "-map", "0:a:0",
            "-c:v", "libx264", "-preset", "slow",
            "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "22M",
            "-x264-params", "nal-hrd=cbr:force-cfr=1",
            "-r", "30", "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.1",
            "-af", "loudnorm=I=-16:LRA=7:TP=-1.5",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
            "-movflags", "+faststart",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PreviewMixError.transcodeFailed(process.terminationStatus)
        }

        print("Created \(outputURL.path)")
        print(hasNarration ? "Mixed score and supplied narration." : "Mixed score with narration headroom.")
        print("Encoded H.264 at 11 Mbps target and loudness-normalized AAC stereo at 48 kHz.")
    }
}
