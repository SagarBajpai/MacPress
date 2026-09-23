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

enum CompressionRatio {
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
