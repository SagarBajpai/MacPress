import Foundation

struct AppConfiguration: Sendable {
    let watchDirectory: URL
    let logDirectory: URL
    let recentJobLimit = 5
    let maximumLogBytes: UInt64 = 1_000_000
    let watcherDebounce: TimeInterval = 0.5

    static let live = AppConfiguration(
        watchDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots"),
        logDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ScreenCompressor")
    )
}

struct CompressionConfiguration: Sendable {
    var videoQuality = 28
    var audioBitrate = "128k"
    var stabilizationInterval: Duration = .seconds(2)
    var stabilizationChecks = 3
    var stabilizationTimeout: Duration = .seconds(30)
}

struct CompressionProgress: Sendable, Equatable {
    let fractionCompleted: Double?
    let processedDuration: Double?
    let speed: Double?
}

struct CompressionResult: Sendable, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL?
    let sourceSize: Int64
    let outputSize: Int64?
    let completedAt: Date
    let failureReason: String?

    var savedPercentage: Double? {
        guard let outputSize else { return nil }
        return CompressionRatio.savedPercentage(source: sourceSize, output: outputSize)
    }
}

enum JobEvent: Sendable {
    case queued(URL, Int)
    case stabilizing(URL)
    case processing(URL, CompressionProgress)
    case completed(CompressionResult)
    case failed(CompressionResult)
    case monitoringError(String)
}

enum CompressionError: LocalizedError {
    case ffmpegNotFound
    case sourceMissing
    case stabilizationTimeout
    case processLaunchFailed(String)
    case compressionFailed(String)
    case invalidOutput
    case sourceChanged
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound: "ffmpeg is unavailable. Install it and relaunch the app."
        case .sourceMissing: "The recording is no longer available."
        case .stabilizationTimeout: "The recording is still being written."
        case .processLaunchFailed: "The video tool could not start."
        case .compressionFailed: "Compression failed. The original was kept."
        case .invalidOutput: "The compressed video could not be verified. The original was kept."
        case .sourceChanged: "The recording changed during compression. The original was kept."
        case .cleanupFailed: "The compressed video is ready, but the original could not be moved to Trash."
        }
    }
}

struct ParsedFFmpegProgress: Sendable, Equatable {
    var outputTime: Double?
    var speed: Double?
    var isComplete = false
}
