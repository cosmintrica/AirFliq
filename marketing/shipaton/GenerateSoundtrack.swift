import Foundation

private let sampleRate = 48_000
private let durationSeconds = 49.98
private let frameCount = Int(durationSeconds * Double(sampleRate))

private struct Scene {
    let start: Double
    let end: Double
    let notes: [Int]
    let root: Int
    let padLevel: Double
    let pulseEvery: Double
}

private struct NoiseGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let unit = Double(state & 0x00FF_FFFF) / Double(0x00FF_FFFF)
        return unit * 2.0 - 1.0
    }
}

private func midiFrequency(_ note: Int) -> Double {
    440.0 * pow(2.0, Double(note - 69) / 12.0)
}

private func smoothstep(_ value: Double) -> Double {
    let x = min(1.0, max(0.0, value))
    return x * x * (3.0 - 2.0 * x)
}

private func equalPowerPan(_ pan: Double) -> (left: Double, right: Double) {
    let normalized = min(1.0, max(-1.0, pan))
    let angle = (normalized + 1.0) * Double.pi / 4.0
    return (cos(angle), sin(angle))
}

private final class Soundtrack {
    var left = [Double](repeating: 0.0, count: frameCount)
    var right = [Double](repeating: 0.0, count: frameCount)

    private func frameRange(start: Double, end: Double) -> Range<Int> {
        let first = max(0, Int(floor(start * Double(sampleRate))))
        let last = min(frameCount, Int(ceil(end * Double(sampleRate))))
        return first..<max(first, last)
    }

    func addPad(start: Double, end: Double, notes: [Int], level: Double, sceneIndex: Int) {
        let attack = start == 0 ? 2.2 : 1.15
        let release = end >= durationSeconds ? 1.6 : 1.55
        let tailEnd = min(durationSeconds, end + release)
        let voiceScale = 1.0 / sqrt(Double(notes.count))

        for (voiceIndex, note) in notes.enumerated() {
            let frequency = midiFrequency(note)
            let detune = 0.00035 + Double(voiceIndex) * 0.00008
            let leftFrequency = frequency * (1.0 - detune)
            let rightFrequency = frequency * (1.0 + detune)
            let phase = Double((sceneIndex * 5 + voiceIndex * 3) % 13) * 0.37
            let pan = Double(voiceIndex) / Double(max(1, notes.count - 1)) * 1.15 - 0.575
            let stereo = equalPowerPan(pan)

            for frame in frameRange(start: start, end: tailEnd) {
                let absoluteTime = Double(frame) / Double(sampleRate)
                let localTime = absoluteTime - start
                let rise = smoothstep(localTime / attack)
                let fall: Double
                if absoluteTime <= end {
                    fall = 1.0
                } else {
                    fall = 1.0 - smoothstep((absoluteTime - end) / release)
                }
                let envelope = rise * fall
                let breath = 0.925
                    + 0.045 * sin(2.0 * Double.pi * (0.047 + Double(voiceIndex) * 0.006) * absoluteTime + phase)
                    + 0.030 * sin(2.0 * Double.pi * 0.013 * absoluteTime + phase * 0.7)
                let leftPhase = 2.0 * Double.pi * leftFrequency * localTime + phase
                let rightPhase = 2.0 * Double.pi * rightFrequency * localTime + phase + 0.11
                let leftTone = sin(leftPhase)
                    + 0.105 * sin(leftPhase * 2.0 + 0.4)
                    + 0.032 * sin(leftPhase * 3.0 + 1.1)
                let rightTone = sin(rightPhase)
                    + 0.105 * sin(rightPhase * 2.0 + 0.6)
                    + 0.032 * sin(rightPhase * 3.0 + 1.3)
                let amount = level * voiceScale * envelope * breath
                left[frame] += leftTone * amount * (0.74 + stereo.left * 0.26)
                right[frame] += rightTone * amount * (0.74 + stereo.right * 0.26)
            }
        }
    }

    func addPulse(at start: Double, root: Int, strength: Double, index: Int) {
        let length = 0.74
        let frequency = midiFrequency(root)
        let pan = sin(Double(index) * 1.7) * 0.22
        let stereo = equalPowerPan(pan)

        for frame in frameRange(start: start, end: start + length) {
            let time = Double(frame) / Double(sampleRate) - start
            let attack = smoothstep(time / 0.018)
            let decay = exp(-time * 5.4)
            let pitchGlide = 1.0 + 0.018 * exp(-time * 13.0)
            let phase = 2.0 * Double.pi * frequency * pitchGlide * time
            let body = sin(phase) + 0.17 * sin(phase * 2.0 + 0.35)
            let air = 0.065 * sin(2.0 * Double.pi * frequency * 4.0 * time + 0.8) * exp(-time * 10.0)
            let value = (body + air) * attack * decay * strength
            left[frame] += value * stereo.left
            right[frame] += value * stereo.right
        }
    }

    func addGlassPluck(at start: Double, note: Int, strength: Double, pan: Double) {
        let length = 1.45
        let frequency = midiFrequency(note)
        let stereo = equalPowerPan(pan)

        for frame in frameRange(start: start, end: start + length) {
            let time = Double(frame) / Double(sampleRate) - start
            let attack = smoothstep(time / 0.009)
            let envelope = attack * exp(-time * 4.15)
            let fundamental = sin(2.0 * Double.pi * frequency * time)
            let overtone = 0.28 * sin(2.0 * Double.pi * frequency * 2.01 * time + 0.4) * exp(-time * 1.9)
            let shimmer = 0.105 * sin(2.0 * Double.pi * frequency * 3.98 * time + 0.9) * exp(-time * 3.4)
            let value = (fundamental + overtone + shimmer) * envelope * strength
            left[frame] += value * stereo.left
            right[frame] += value * stereo.right
        }
    }

    func addChime(at start: Double, notes: [Int], strength: Double) {
        for (index, note) in notes.enumerated() {
            let noteStart = start + Double(index) * 0.065
            let length = 2.75 - Double(index) * 0.18
            let frequency = midiFrequency(note)
            let stereo = equalPowerPan(index.isMultiple(of: 2) ? -0.44 : 0.44)

            for frame in frameRange(start: noteStart, end: noteStart + length) {
                let time = Double(frame) / Double(sampleRate) - noteStart
                let attack = smoothstep(time / 0.014)
                let envelope = attack * exp(-time * (1.42 + Double(index) * 0.12))
                let tone = sin(2.0 * Double.pi * frequency * time)
                    + 0.34 * sin(2.0 * Double.pi * frequency * 2.003 * time + 0.35) * exp(-time * 0.7)
                    + 0.16 * sin(2.0 * Double.pi * frequency * 3.997 * time + 1.05) * exp(-time * 1.1)
                let value = tone * envelope * strength
                left[frame] += value * stereo.left
                right[frame] += value * stereo.right
            }
        }
    }

    func addWhoosh(center: Double, strength: Double, seed: UInt64) {
        let start = max(0.0, center - 0.82)
        let end = min(durationSeconds, center + 0.72)
        let length = end - start
        var noise = NoiseGenerator(seed: seed)
        var slowState = 0.0
        var fastState = 0.0

        for frame in frameRange(start: start, end: end) {
            let time = Double(frame) / Double(sampleRate) - start
            let progress = min(1.0, max(0.0, time / length))
            let raw = noise.next()
            let sweep = 0.006 + 0.12 * progress * progress
            slowState += sweep * (raw - slowState)
            fastState += min(0.36, sweep * 3.2) * (raw - fastState)
            let band = fastState - slowState
            let envelope = pow(sin(Double.pi * progress), 1.55)
            let pan = -0.72 + progress * 1.44
            let stereo = equalPowerPan(pan)
            let value = band * envelope * strength
            left[frame] += value * stereo.left
            right[frame] += value * stereo.right
        }
    }

    func addBloom(at start: Double, root: Int, strength: Double) {
        let length = 1.12
        let rootFrequency = midiFrequency(root)
        for frame in frameRange(start: start, end: start + length) {
            let time = Double(frame) / Double(sampleRate) - start
            let attack = smoothstep(time / 0.045)
            let envelope = attack * exp(-time * 3.7)
            let low = sin(2.0 * Double.pi * rootFrequency * 0.5 * time) * exp(-time * 1.8)
            let glow = sin(2.0 * Double.pi * rootFrequency * 2.0 * time + 0.7)
            let value = (low * 0.72 + glow * 0.28) * envelope * strength
            left[frame] += value * 0.78
            right[frame] += value * 0.78
        }
    }

    func addAir() {
        var noise = NoiseGenerator(seed: 0xA1F1_1A09)
        var low = 0.0
        var slower = 0.0
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            let raw = noise.next()
            low += 0.025 * (raw - low)
            slower += 0.004 * (raw - slower)
            let texture = (low - slower) * 0.0065
            let movement = 0.62 + 0.38 * sin(2.0 * Double.pi * 0.021 * time + 0.5)
            left[frame] += texture * movement
            right[frame] += texture * (1.0 - 0.12 * sin(2.0 * Double.pi * 0.017 * time))
        }
    }

    func addRoom() {
        let taps: [(seconds: Double, gain: Double, cross: Double)] = [
            (0.071, 0.105, 0.22),
            (0.119, 0.078, 0.44),
            (0.181, 0.057, 0.62),
            (0.269, 0.038, 0.78),
            (0.397, 0.022, 0.91),
        ]
        let dryLeft = left
        let dryRight = right

        for tap in taps {
            let offset = Int(tap.seconds * Double(sampleRate))
            guard offset < frameCount else { continue }
            for frame in offset..<frameCount {
                let source = frame - offset
                let l = dryLeft[source] * (1.0 - tap.cross) + dryRight[source] * tap.cross
                let r = dryRight[source] * (1.0 - tap.cross) + dryLeft[source] * tap.cross
                left[frame] += l * tap.gain
                right[frame] += r * tap.gain
            }
        }
    }

    func finish() -> (interleaved: [Int16], rawPeak: Double, peak: Double, rms: Double) {
        let fadeInFrames = Int(0.06 * Double(sampleRate))
        let fadeOutFrames = Int(0.58 * Double(sampleRate))
        var rawPeak = 0.0

        for frame in 0..<frameCount {
            let fadeIn = smoothstep(Double(frame) / Double(max(1, fadeInFrames)))
            let remaining = frameCount - 1 - frame
            let fadeOut = smoothstep(Double(remaining) / Double(max(1, fadeOutFrames)))
            let fade = min(fadeIn, fadeOut)
            left[frame] *= fade
            right[frame] *= fade
            rawPeak = max(rawPeak, abs(left[frame]), abs(right[frame]))
        }

        let targetPeak = 0.56
        let scale = rawPeak > 0 ? min(1.0, targetPeak / rawPeak) : 1.0
        var interleaved = [Int16]()
        interleaved.reserveCapacity(frameCount * 2)
        var peak = 0.0
        var squareSum = 0.0

        for frame in 0..<frameCount {
            let l = tanh(left[frame] * scale * 1.035) / tanh(1.035)
            let r = tanh(right[frame] * scale * 1.035) / tanh(1.035)
            peak = max(peak, abs(l), abs(r))
            squareSum += l * l + r * r
            interleaved.append(Int16((min(0.999_969, max(-1.0, l)) * 32_767.0).rounded()))
            interleaved.append(Int16((min(0.999_969, max(-1.0, r)) * 32_767.0).rounded()))
        }

        let rms = sqrt(squareSum / Double(frameCount * 2))
        return (interleaved, rawPeak, peak, rms)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func writeWAV(samples: [Int16], to url: URL) throws {
    let channelCount: UInt16 = 2
    let bitsPerSample: UInt16 = 16
    let bytesPerSample = UInt32(bitsPerSample / 8)
    let byteRate = UInt32(sampleRate) * UInt32(channelCount) * bytesPerSample
    let blockAlign = channelCount * (bitsPerSample / 8)
    let dataByteCount = UInt32(samples.count) * bytesPerSample

    var output = Data(capacity: 44 + Int(dataByteCount))
    output.append(contentsOf: "RIFF".utf8)
    output.appendUInt32LE(36 + dataByteCount)
    output.append(contentsOf: "WAVE".utf8)
    output.append(contentsOf: "fmt ".utf8)
    output.appendUInt32LE(16)
    output.appendUInt16LE(1)
    output.appendUInt16LE(channelCount)
    output.appendUInt32LE(UInt32(sampleRate))
    output.appendUInt32LE(byteRate)
    output.appendUInt16LE(blockAlign)
    output.appendUInt16LE(bitsPerSample)
    output.append(contentsOf: "data".utf8)
    output.appendUInt32LE(dataByteCount)

    samples.withUnsafeBytes { bytes in
        output.append(contentsOf: bytes)
    }
    try output.write(to: url, options: .atomic)
}

@main
enum GenerateSoundtrack {
    static func main() throws {
        let scenes = [
            Scene(start: 0.0, end: 8.0, notes: [50, 57, 60, 64], root: 38, padLevel: 0.052, pulseEvery: 1.25),
            Scene(start: 8.0, end: 22.0, notes: [46, 53, 57, 60, 64], root: 34, padLevel: 0.050, pulseEvery: 0.625),
            Scene(start: 22.0, end: 28.0, notes: [43, 50, 58, 62, 69], root: 31, padLevel: 0.054, pulseEvery: 0.625),
            Scene(start: 28.0, end: 34.0, notes: [46, 53, 57, 62, 65], root: 34, padLevel: 0.057, pulseEvery: 0.625),
            Scene(start: 34.0, end: 44.0, notes: [38, 45, 53, 60, 64], root: 38, padLevel: 0.050, pulseEvery: 1.25),
            Scene(start: 44.0, end: durationSeconds, notes: [41, 48, 57, 62, 67], root: 41, padLevel: 0.055, pulseEvery: 1.25),
        ]

        let soundtrack = Soundtrack()
        soundtrack.addAir()

        for (sceneIndex, scene) in scenes.enumerated() {
            soundtrack.addPad(
                start: scene.start,
                end: scene.end,
                notes: scene.notes,
                level: scene.padLevel,
                sceneIndex: sceneIndex
            )

            var beat = scene.start + (sceneIndex == 0 ? 2.0 : 0.28)
            var beatIndex = 0
            while beat < scene.end - 0.25 {
                let accent = beatIndex.isMultiple(of: 4) ? 1.0 : 0.68
                soundtrack.addPulse(
                    at: beat,
                    root: scene.root,
                    strength: 0.034 * accent,
                    index: sceneIndex * 32 + beatIndex
                )
                if beatIndex.isMultiple(of: 4), scene.notes.count > 2 {
                    let pluckNote = scene.notes[(beatIndex / 4 + 2) % scene.notes.count] + 12
                    soundtrack.addGlassPluck(
                        at: beat + 0.08,
                        note: pluckNote,
                        strength: 0.018,
                        pan: beatIndex.isMultiple(of: 8) ? -0.34 : 0.34
                    )
                }
                beat += scene.pulseEvery
                beatIndex += 1
            }
        }

        soundtrack.addBloom(at: 0.0, root: 38, strength: 0.065)
        soundtrack.addChime(at: 0.18, notes: [74, 81, 88], strength: 0.020)

        soundtrack.addWhoosh(center: 8.0, strength: 0.046, seed: 0x0808)
        soundtrack.addBloom(at: 8.0, root: 34, strength: 0.042)

        soundtrack.addWhoosh(center: 22.0, strength: 0.105, seed: 0x2222)
        soundtrack.addBloom(at: 22.0, root: 31, strength: 0.072)
        soundtrack.addChime(at: 22.02, notes: [74, 81, 86], strength: 0.032)

        soundtrack.addWhoosh(center: 28.0, strength: 0.112, seed: 0x2828)
        soundtrack.addBloom(at: 28.0, root: 34, strength: 0.078)
        soundtrack.addChime(at: 28.02, notes: [77, 81, 86], strength: 0.034)

        soundtrack.addWhoosh(center: 34.0, strength: 0.052, seed: 0x3434)
        soundtrack.addBloom(at: 34.0, root: 38, strength: 0.046)

        soundtrack.addWhoosh(center: 44.0, strength: 0.118, seed: 0x4444)
        soundtrack.addBloom(at: 44.0, root: 41, strength: 0.082)
        soundtrack.addChime(at: 44.02, notes: [72, 77, 81, 86], strength: 0.036)

        soundtrack.addRoom()
        let result = soundtrack.finish()

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let defaultURL = root.appendingPathComponent("marketing/shipaton/audio/airfliq-original-score.wav")
        let outputURL = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1])
            : defaultURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeWAV(samples: result.interleaved, to: outputURL)

        let peakDB = result.peak > 0 ? 20.0 * log10(result.peak) : -.infinity
        let rmsDB = result.rms > 0 ? 20.0 * log10(result.rms) : -.infinity
        print("Generated: \(outputURL.path)")
        print(String(format: "Format: 48,000 Hz, stereo, 16-bit PCM WAV"))
        print(String(format: "Duration: %.5f seconds (%d frames)", Double(frameCount) / Double(sampleRate), frameCount))
        print(String(format: "Raw peak: %.6f | Final peak: %.6f (%.2f dBFS)", result.rawPeak, result.peak, peakDB))
        print(String(format: "RMS: %.6f (%.2f dBFS)", result.rms, rmsDB))
    }
}
