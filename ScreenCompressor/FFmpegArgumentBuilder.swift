import Foundation

/// Media facts about the source file that influence encoder arguments.
struct VideoSourceInfo: Equatable, Sendable {
    var duration: Double?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var bitRate: Double?

    init(duration: Double? = nil, width: Int? = nil, height: Int? = nil,
         frameRate: Double? = nil, bitRate: Double? = nil) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitRate = bitRate
    }

    static let unknown = VideoSourceInfo()

    /// Frame rate the output will have: the configured target if any, otherwise the source.
    func effectiveFrameRate(_ option: FrameRateOption) -> Double? {
        if let target = option.framesPerSecond { return Double(target) }
        return frameRate
    }
}

/// Translates a `CompressionConfiguration` into ffmpeg arguments.
///
/// Arguments are always passed as an array through `Process`, never as a shell string,
/// so filenames cannot be interpreted as shell syntax.
struct FFmpegArgumentBuilder: Sendable {
    func arguments(
        configuration: CompressionConfiguration,
        source: URL,
        sourceInfo: VideoSourceInfo,
        destination: URL
    ) -> [String] {
        var arguments = ["-y", "-hide_banner", "-hwaccel", "videotoolbox", "-i", source.path]
        let filters = videoFilters(configuration: configuration, sourceInfo: sourceInfo)
        if !filters.isEmpty { arguments += ["-vf", filters.joined(separator: ",")] }
        arguments += videoArguments(configuration: configuration, sourceInfo: sourceInfo)
        arguments += audioArguments(configuration: configuration)
        arguments += ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", destination.path]
        return arguments
    }

    /// Only ever downscales and only ever drops frames. Asking for a larger resolution or a
    /// higher frame rate than the source has would mean inventing pixels or duplicate frames.
    func videoFilters(configuration: CompressionConfiguration, sourceInfo: VideoSourceInfo) -> [String] {
        let configuration = configuration.coerced()
        var filters: [String] = []
        if let target = configuration.frameRate.framesPerSecond,
           let sourceRate = sourceInfo.frameRate, sourceRate > 0,
           Double(target) < sourceRate - 0.5 {
            filters.append("fps=\(target)")
        }
        if let targetHeight = configuration.resolution.heightValue,
           let sourceHeight = sourceInfo.height, sourceHeight > targetHeight {
            filters.append("scale=-2:\(targetHeight):flags=\(configuration.scalingQuality.rawValue)")
        }
        return filters
    }

    func videoArguments(configuration: CompressionConfiguration, sourceInfo: VideoSourceInfo) -> [String] {
        let configuration = configuration.coerced()
        var arguments = ["-c:v", configuration.codec.encoderName]

        switch configuration.qualityMode {
        case .constantQuality:
            arguments += ["-q:v", "\(configuration.quality)"]
        case .targetBitrate:
            let kbps = configuration.bitrate.kbps ?? CompressionConfiguration.defaultBitrateKbps
            arguments += ["-b:v", "\(kbps)k"]
            if let multiplier = configuration.bitrateCeiling.multiplier {
                // DataRateLimits: a short window at the peak rate keeps the average honest.
                arguments += ["-maxrate", "\(Int(Double(kbps) * multiplier))k",
                              "-bufsize", "\(Int(Double(kbps) * multiplier * 2))k"]
            }
            if configuration.constantBitRate { arguments += ["-constant_bit_rate", "1"] }
        }

        if let profile = configuration.profile.ffmpegValue { arguments += ["-profile:v", profile] }
        arguments += ["-pix_fmt", configuration.pixelFormat.rawValue]

        let frameRate = sourceInfo.effectiveFrameRate(configuration.frameRate)
        arguments += ["-g", "\(configuration.keyframeInterval.frameCount(forFramesPerSecond: frameRate))"]

        // `-spatial_aq` and `-prio_speed` are deliberately not set: measured byte for byte, this
        // VideoToolbox encoder produced identical output with them on and off, so they would
        // only add arguments that do nothing.

        if let tag = configuration.codec.containerTag { arguments += ["-tag:v", tag] }
        return arguments
    }

    func audioArguments(configuration: CompressionConfiguration) -> [String] {
        switch configuration.audioCodec {
        case .none: ["-an"]
        case .aac: ["-c:a", "aac", "-b:a", "\(configuration.audioBitrate.rawValue)k"]
        }
    }
}
