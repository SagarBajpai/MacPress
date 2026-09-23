import Foundation

struct FileStabilizationService: Sendable {
    let configuration: CompressionConfiguration
    var size: @Sendable (URL) throws -> Int64 = { url in
        guard let value = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw CompressionError.sourceMissing
        }
        return value.int64Value
    }
    var pause: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func waitUntilStable(_ url: URL) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.stabilizationTimeout)
        var previous: Int64?
        var unchanged = 0
        while clock.now < deadline {
            try Task.checkCancellation()
            let current = try size(url)
            if current > 0, current == previous { unchanged += 1 } else { unchanged = 0 }
            if unchanged >= configuration.stabilizationChecks - 1 { return }
            previous = current
            try await pause(configuration.stabilizationInterval)
        }
        throw CompressionError.stabilizationTimeout
    }
}

struct FFmpegService: Sendable {
    let configuration: CompressionConfiguration
    var executables: [String: URL]? = nil
    var bundleURL: URL = Bundle.main.bundleURL

    func executable(named name: String) -> URL? {
        if let executables { return executables[name] }
        let bundled = bundleURL.appendingPathComponent("Contents/Resources/bin", isDirectory: true)
            .appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in defaults + pathDirectories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    func arguments(source: URL, destination: URL) -> [String] {
        ["-y", "-hwaccel", "videotoolbox", "-i", source.path,
         "-c:v", "hevc_videotoolbox", "-q:v", "\(configuration.videoQuality)",
         "-c:a", "aac", "-b:a", configuration.audioBitrate, "-tag:v", "hvc1",
         "-progress", "pipe:1", "-nostats", destination.path]
    }
}

struct FileCleanupService: Sendable {
    var trash: @Sendable (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }

    func trashSource(_ url: URL) throws {
        try trash(url)
    }
}
