import Foundation

// MARK: - Codec

/// The video codec to encode with. Both options are Apple VideoToolbox hardware encoders.
enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case hevc
    case h264

    var displayName: String {
        switch self {
        case .hevc: "HEVC / H.265"
        case .h264: "H.264"
        }
    }

    var encoderName: String {
        switch self {
        case .hevc: "hevc_videotoolbox"
        case .h264: "h264_videotoolbox"
        }
    }

    /// `ffprobe` reports this name for the produced stream, used to verify the output.
    var probeCodecName: String {
        switch self {
        case .hevc: "hevc"
        case .h264: "h264"
        }
    }

    /// `hvc1` keeps QuickTime, Safari and Finder previews happy with HEVC.
    var containerTag: String? { self == .hevc ? "hvc1" : nil }

    var pixelFormats: [PixelFormatOption] {
        self == .hevc ? PixelFormatOption.allCases : [.eightBit]
    }
}

enum PixelFormatOption: String, CaseIterable, Codable, Sendable {
    case eightBit = "yuv420p"
    case tenBit = "p010le"

    var displayName: String {
        switch self {
        case .eightBit: "8-bit"
        case .tenBit: "10-bit"
        }
    }

    var detail: String {
        switch self {
        case .eightBit: "Widest player support"
        case .tenBit: "Fewer bits for the same look, better gradients"
        }
    }

    /// 10-bit HEVC needs the Main10 profile, otherwise VideoToolbox rejects the session.
    var requiredProfile: VideoProfile? {
        switch self {
        case .tenBit: .hevcMain10
        case .eightBit: nil
        }
    }
}

enum VideoProfile: String, CaseIterable, Codable, Sendable {
    case automatic
    case hevcMain
    case hevcMain10
    case h264Baseline
    case h264Main
    case h264High

    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .hevcMain, .h264Main: "Main"
        case .hevcMain10: "Main10"
        case .h264Baseline: "Baseline"
        case .h264High: "High"
        }
    }

    var ffmpegValue: String? {
        switch self {
        case .automatic: nil
        case .hevcMain, .h264Main: "main"
        case .hevcMain10: "main10"
        case .h264Baseline: "baseline"
        case .h264High: "high"
        }
    }

    var codec: VideoCodec {
        switch self {
        case .automatic, .hevcMain, .hevcMain10: .hevc
        case .h264Baseline, .h264Main, .h264High: .h264
        }
    }

    static func options(for codec: VideoCodec) -> [VideoProfile] {
        switch codec {
        case .hevc: [.automatic, .hevcMain, .hevcMain10]
        case .h264: [.automatic, .h264Baseline, .h264Main, .h264High]
        }
    }
}

// MARK: - Quality control

enum VideoQualityMode: String, CaseIterable, Codable, Sendable {
    case constantQuality
    case targetBitrate

    var displayName: String {
        switch self {
        case .constantQuality: "Constant Quality"
        case .targetBitrate: "Target Bitrate"
        }
    }
}

/// A bitrate target for target-bitrate mode. `automatic` means "no bitrate target",
/// which only makes sense with constant quality; see `CompressionConfiguration.coerced()`.
enum VideoBitrate: Hashable, Codable, Sendable {
    case automatic
    case kbps(Int)

    /// Menu choices. Any other `.kbps` value is treated as a custom entry.
    static let choices: [VideoBitrate] = [
        .automatic, .kbps(250), .kbps(500), .kbps(750), .kbps(1000),
        .kbps(1500), .kbps(2000), .kbps(3000), .kbps(5000)
    ]

    /// Custom bitrate entry point used by the "Custom…" menu item.
    static func custom(_ kbps: Int) -> VideoBitrate { .kbps(kbps) }

    var kbps: Int? {
        if case .kbps(let value) = self { return value }
        return nil
    }

    var isCustom: Bool { kbps != nil && !Self.choices.contains(self) }

    var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .kbps(let value):
            guard value >= 1000 else { return "\(value) kbps" }
            let megabits = Double(value) / 1000
            return value % 1000 == 0
                ? "\(value / 1000) Mbps"
                : String(format: "%.1f Mbps", megabits)
        }
    }
}

/// Peak bitrate allowance applied on top of the target bitrate.
enum BitrateCeiling: String, CaseIterable, Codable, Sendable {
    case automatic
    case oneAndHalf
    case twoTimes
    case threeTimes

    var multiplier: Double? {
        switch self {
        case .automatic: nil
        case .oneAndHalf: 1.5
        case .twoTimes: 2
        case .threeTimes: 3
        }
    }

    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .oneAndHalf: "1.5×"
        case .twoTimes: "2×"
        case .threeTimes: "3×"
        }
    }
}

enum FrameRateOption: Hashable, Codable, Sendable {
    case source
    case fps(Int)

    static let choices: [FrameRateOption] = [.source, .fps(60), .fps(30), .fps(24), .fps(15)]

    var framesPerSecond: Int? {
        if case .fps(let value) = self { return value }
        return nil
    }

    var displayName: String {
        switch self {
        case .source: "Same as Source"
        case .fps(let value): "\(value) fps"
        }
    }
}

enum ResolutionOption: Hashable, Codable, Sendable {
    /// Vertical resolution is scaled, width follows the source aspect ratio.
    case source
    case height(Int)

    static let choices: [ResolutionOption] = [.source, .height(1440), .height(1080), .height(720), .height(480)]

    var heightValue: Int? {
        if case .height(let value) = self { return value }
        return nil
    }

    var displayName: String {
        switch self {
        case .source: "Same as Source"
        case .height(let value): "\(value)p"
        }
    }
}

/// Distance between keyframes.
///
/// This is the single biggest lever for screen recordings. Left to itself, VideoToolbox emits a
/// keyframe roughly every fifth of a second, which costs several times more bits than the
/// content needs. An explicit interval is therefore always sent.
enum KeyframeInterval: String, CaseIterable, Codable, Sendable {
    case everySecond
    case everyTwoSeconds
    case everyFiveSeconds
    case everyTenSeconds

    /// Frame rate assumed when the source frame rate could not be probed. Erring towards a
    /// higher rate keeps the interval shorter than requested rather than much longer.
    static let fallbackFrameRate: Double = 60

    var seconds: Double {
        switch self {
        case .everySecond: 1
        case .everyTwoSeconds: 2
        case .everyFiveSeconds: 5
        case .everyTenSeconds: 10
        }
    }

    var displayName: String {
        switch self {
        case .everySecond: "1s"
        case .everyTwoSeconds: "2s"
        case .everyFiveSeconds: "5s"
        case .everyTenSeconds: "10s"
        }
    }

    func frameCount(forFramesPerSecond frameRate: Double?) -> Int {
        let rate = frameRate.flatMap { $0 > 0 ? $0 : nil } ?? Self.fallbackFrameRate
        return max(1, Int((seconds * rate).rounded()))
    }
}

enum ScalingQuality: String, CaseIterable, Codable, Sendable {
    case lanczos
    case bicubic
    case bilinear

    var displayName: String {
        switch self {
        case .lanczos: "Lanczos"
        case .bicubic: "Bicubic"
        case .bilinear: "Bilinear"
        }
    }

    var detail: String {
        switch self {
        case .lanczos: "Sharpest text, slowest"
        case .bicubic: "Balanced"
        case .bilinear: "Softest, fastest"
        }
    }
}

// MARK: - Audio

enum AudioCodec: String, CaseIterable, Codable, Sendable {
    case aac
    case none

    var displayName: String {
        switch self {
        case .aac: "AAC"
        case .none: "No Audio"
        }
    }
}

enum AudioBitrateOption: Int, CaseIterable, Codable, Sendable {
    case kbps64 = 64
    case kbps96 = 96
    case kbps128 = 128
    case kbps192 = 192
    case kbps256 = 256

    var displayName: String { "\(rawValue) kbps" }
}

// MARK: - Configuration

/// Everything the encoder needs. Settings are snapshotted when a job starts, so editing
/// them never changes an encode that is already running.
///
/// The declared defaults are the Balanced preset. `testDefaultConfigurationMatchesBalanced`
/// keeps the two in step.
struct CompressionConfiguration: Codable, Equatable, Sendable {
    var preset: CompressionPreset = .balanced
    var codec: VideoCodec = .hevc
    var qualityMode: VideoQualityMode = .constantQuality
    var quality: Int = 45
    var bitrate: VideoBitrate = .automatic
    var bitrateCeiling: BitrateCeiling = .automatic
    var constantBitRate = false
    var frameRate: FrameRateOption = .fps(30)
    var resolution: ResolutionOption = .source
    var pixelFormat: PixelFormatOption = .tenBit
    var keyframeInterval: KeyframeInterval = .everyTenSeconds
    var profile: VideoProfile = .hevcMain10
    var audioCodec: AudioCodec = .aac
    var audioBitrate: AudioBitrateOption = .kbps128
    var scalingQuality: ScalingQuality = .lanczos

    /// VideoToolbox quality scale: higher keeps more detail and produces a larger file.
    static let qualityRange = 0...100
    static let defaultBitrateKbps = 2000

    /// Repairs combinations VideoToolbox cannot express, without touching `preset`.
    func coerced() -> CompressionConfiguration {
        var copy = self
        copy.quality = min(max(copy.quality, Self.qualityRange.lowerBound), Self.qualityRange.upperBound)
        if !copy.codec.pixelFormats.contains(copy.pixelFormat) { copy.pixelFormat = .eightBit }
        if !VideoProfile.options(for: copy.codec).contains(copy.profile) { copy.profile = .automatic }
        if let required = copy.pixelFormat.requiredProfile, copy.profile == .automatic {
            copy.profile = required
        }
        // "Auto" bitrate means "no bitrate target", which is only meaningful with
        // constant quality. Treat the combination as constant quality instead of
        // silently inventing a target the user never chose.
        if copy.qualityMode == .targetBitrate, copy.bitrate.kbps == nil {
            copy.qualityMode = .constantQuality
        }
        if copy.qualityMode == .constantQuality { copy.constantBitRate = false }
        return copy
    }

    /// `coerced()` plus a re-derived preset label, so manual edits surface as Custom and
    /// returning the controls to a preset's exact values shows that preset again.
    func normalized() -> CompressionConfiguration {
        var copy = coerced()
        copy.preset = CompressionPreset.matching(copy)
        return copy
    }

    func applying(_ preset: CompressionPreset) -> CompressionConfiguration {
        guard let definition = preset.definition else {
            var custom = self
            custom.preset = .custom
            return custom
        }
        return definition.normalized()
    }

    /// Compact description used in log lines.
    var summary: String {
        var parts = [preset.displayName, codec.displayName]
        switch qualityMode {
        case .constantQuality: parts.append("quality \(quality)")
        case .targetBitrate: parts.append("bitrate \(bitrate.displayName)")
        }
        parts.append(frameRate.displayName)
        parts.append(resolution.displayName)
        parts.append(pixelFormat.displayName)
        parts.append(audioCodec == .none ? "no audio" : "AAC \(audioBitrate.displayName)")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Presets

enum CompressionPreset: String, CaseIterable, Codable, Sendable {
    case high
    case balanced
    case medium
    case low
    case custom

    /// Presets a user can pick. `custom` is only ever derived from manual edits.
    static var selectable: [CompressionPreset] { [.high, .balanced, .medium, .low, .custom] }

    var displayName: String {
        switch self {
        case .high: "High"
        case .balanced: "Balanced"
        case .medium: "Medium"
        case .low: "Low"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .high: "Keeps the most detail, largest files"
        case .balanced: "Near-lossless screen quality, smallest practical file"
        case .medium: "Smaller files, text stays comfortably readable"
        case .low: "Smallest files, visible quality loss"
        case .custom: "Manually tuned"
        }
    }

    /// The configuration a preset maps to, or nil for `custom`.
    var definition: CompressionConfiguration? {
        switch self {
        case .high: .highQuality
        case .balanced: .balanced
        case .medium: .medium
        case .low: .low
        case .custom: nil
        }
    }

    /// The preset whose definition exactly equals `configuration`, else `.custom`.
    static func matching(_ configuration: CompressionConfiguration) -> CompressionPreset {
        for preset in CompressionPreset.allCases where preset != .custom {
            guard var definition = preset.definition else { continue }
            // The preset label itself is not part of the comparison.
            definition.preset = configuration.preset
            if definition == configuration { return preset }
        }
        return .custom
    }
}

extension CompressionConfiguration {
    /// Highest fidelity. Keeps the source frame rate and resolution, so only the quality
    /// setting changes what the original looked like.
    static let highQuality = CompressionConfiguration(
        preset: .high, codec: .hevc, qualityMode: .constantQuality, quality: 55,
        frameRate: .source, resolution: .source, pixelFormat: .tenBit,
        keyframeInterval: .everyTenSeconds, profile: .hevcMain10,
        audioCodec: .aac, audioBitrate: .kbps192, scalingQuality: .lanczos
    )

    /// The recommended default. Screen recordings are usually watched for their content, not
    /// for their motion, so halving the frame rate of a 60 fps recording frees enough bits to
    /// keep the quality setting high and text sharp.
    static let balanced = CompressionConfiguration(
        preset: .balanced, codec: .hevc, qualityMode: .constantQuality, quality: 45,
        frameRate: .fps(30), resolution: .source, pixelFormat: .tenBit,
        keyframeInterval: .everyTenSeconds, profile: .hevcMain10,
        audioCodec: .aac, audioBitrate: .kbps128, scalingQuality: .lanczos
    )

    /// Smaller again: the quality setting does the work here, motion stays at 30 fps.
    static let medium = CompressionConfiguration(
        preset: .medium, codec: .hevc, qualityMode: .constantQuality, quality: 32,
        frameRate: .fps(30), resolution: .source, pixelFormat: .tenBit,
        keyframeInterval: .everyTenSeconds, profile: .hevcMain10,
        audioCodec: .aac, audioBitrate: .kbps96, scalingQuality: .lanczos
    )

    /// For when file size matters more than fidelity. 8-bit and a 1080p cap, so 1440p and
    /// 4K recordings get smaller as well as thinner.
    static let low = CompressionConfiguration(
        preset: .low, codec: .hevc, qualityMode: .constantQuality, quality: 18,
        frameRate: .fps(30), resolution: .height(1080), pixelFormat: .eightBit,
        keyframeInterval: .everyTenSeconds, profile: .automatic,
        audioCodec: .aac, audioBitrate: .kbps64, scalingQuality: .lanczos
    )
}
