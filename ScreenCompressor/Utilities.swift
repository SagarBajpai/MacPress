import Foundation

struct FileNameGenerator: Sendable {
    func outputURL(for date: Date, in directory: URL, fileManager: FileManager = .default) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM h:mma"
        let base = formatter.string(from: date)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("mp4")
        var suffix = 23
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix)").appendingPathExtension("mp4")
            suffix += 1
        }
        return candidate
    }
}

struct FFmpegProgressParser: Sendable {
    func parse(_ line: String) -> ParsedFFmpegProgress? {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        var result = ParsedFFmpegProgress()
        switch parts[0] {
        case "out_time_us", "out_time_ms":
            // ffmpeg's out_time_ms field is historically microseconds despite its name.
            result.outputTime = Double(parts[1]).map { $0 / 1_000_000 }
        case "out_time":
            let components = parts[1].split(separator: ":")
            if components.count == 3, let hours = Double(components[0]), let minutes = Double(components[1]), let seconds = Double(components[2]) {
                result.outputTime = hours * 3600 + minutes * 60 + seconds
            }
        case "speed": result.speed = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "x")))
        case "progress": result.isComplete = parts[1] == "end"
        default: return nil
        }
        return result
    }
}

/// Facts reported by ffprobe about a media file.
struct ProbedMedia: Equatable, Sendable {
    var info: VideoSourceInfo
    var videoCodecName: String?
}

/// Parses `ffprobe -of json` output. Unknown or malformed fields degrade to `nil` rather
/// than failing, so a missing bitrate never stops a job.
struct MediaProbe: Sendable {
    struct Output: Decodable {
        struct Stream: Decodable {
            let codecName: String?
            let width: Int?
            let height: Int?
            let averageFrameRate: String?
            let rawFrameRate: String?
            let bitRate: String?

            enum CodingKeys: String, CodingKey {
                case codecName = "codec_name"
                case width
                case height
                case averageFrameRate = "avg_frame_rate"
                case rawFrameRate = "r_frame_rate"
                case bitRate = "bit_rate"
            }
        }

        struct Format: Decodable {
            let duration: String?
            let bitRate: String?

            enum CodingKeys: String, CodingKey {
                case duration
                case bitRate = "bit_rate"
            }
        }

        let streams: [Stream]?
        let format: Format?
    }

    static func parse(_ data: Data) -> ProbedMedia? {
        guard let output = try? JSONDecoder().decode(Output.self, from: data) else { return nil }
        guard let stream = output.streams?.first else {
            return ProbedMedia(info: VideoSourceInfo(duration: output.format?.duration.flatMap(Double.init)), videoCodecName: nil)
        }
        return ProbedMedia(
            info: VideoSourceInfo(
                duration: output.format?.duration.flatMap(Double.init),
                width: stream.width,
                height: stream.height,
                frameRate: frameRate(stream.averageFrameRate) ?? frameRate(stream.rawFrameRate),
                bitRate: stream.bitRate.flatMap(Double.init) ?? output.format?.bitRate.flatMap(Double.init)
            ),
            videoCodecName: stream.codecName
        )
    }

    /// ffprobe reports frame rates as rationals such as `79940/1343`. `0/0` means unknown.
    static func frameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 1 { return Double(parts[0]).flatMap { $0 > 0 ? $0 : nil } }
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              numerator > 0, denominator > 0 else { return nil }
        return numerator / denominator
    }
}

enum CompressionRatio {
    /// Percentage of the source size that was saved. `nil` when the source size is unknown,
    /// which also keeps malformed or zero-byte sources from dividing by zero.
    static func savedPercentage(source: Int64, output: Int64) -> Double? {
        guard source > 0 else { return nil }
        return (1 - Double(output) / Double(source)) * 100
    }
}

enum FileSizeFormatter {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
