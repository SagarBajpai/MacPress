import Foundation
import XCTest
@testable import ScreenCompressor

/// Not part of the normal suite. This measures what each preset actually produces so the
/// preset values can be tuned against real screen recordings instead of guesses.
///
///     ./scripts/build.sh
///     SCREEN_COMPRESSOR_BENCHMARK_SOURCE="$HOME/Screenshots/recording.mov" \
///     SCREEN_COMPRESSOR_TEST_APP=./dist/ScreenCompressor.app \
///     swift test --filter PresetBenchmarks
///
/// The original recording is copied before every run and the copy is trashed into the test
/// directory, so the source file is never modified.
final class PresetBenchmarks: XCTestCase {
    private static let presets: [CompressionPreset] = [.high, .balanced, .medium, .low]

    /// Repeats every line to this file as it is produced, so an interrupted run still reports
    /// the presets it managed to finish.
    private var reportURL: URL? {
        ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_BENCHMARK_REPORT"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    private func record(_ text: String) {
        print(text)
        guard let reportURL else { return }
        let data = Data((text + "\n").utf8)
        guard let handle = try? FileHandle(forWritingTo: reportURL) else {
            try? data.write(to: reportURL)
            return
        }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    func testPresetOutputSizes() async throws {
        guard let sourcePath = ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_BENCHMARK_SOURCE"] else {
            throw XCTSkip("Set SCREEN_COMPRESSOR_BENCHMARK_SOURCE to a .mov to benchmark presets")
        }
        FileManager.default.createFile(atPath: reportURL?.path ?? "/dev/null", contents: nil)
        let bundleURL = ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_TEST_APP"]
            .map { URL(fileURLWithPath: $0) } ?? Bundle.main.bundleURL
        let tools = FFmpegService(bundleURL: bundleURL)
        guard let ffmpeg = tools.executable(named: "ffmpeg"), let ffprobe = tools.executable(named: "ffprobe") else {
            throw XCTSkip("ffmpeg and ffprobe are required for the preset benchmark")
        }

        let source = URL(fileURLWithPath: (sourcePath as NSString).expandingTildeInPath)
        let sourceBytes = try fileSize(source)
        let sourceMedia = try await probe(source, ffprobe: ffprobe)
        record("""

        === PRESET BENCHMARK ===
        source:      \(source.lastPathComponent) (\(FileSizeFormatter.string(sourceBytes)))
        geometry:    \(sourceMedia.info.width ?? 0)x\(sourceMedia.info.height ?? 0) \
        @ \(String(format: "%.2f", sourceMedia.info.frameRate ?? 0)) fps, \
        \(String(format: "%.1f", sourceMedia.info.duration ?? 0)) s
        """)

        for preset in Self.presets {
            let configuration = try XCTUnwrap(preset.definition, "preset \(preset) has no definition")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let copy = directory.appendingPathComponent("source.mov")
            try FileManager.default.copyItem(at: source, to: copy)

            let builder = FFmpegArgumentBuilder()
            record("""

            \(preset.displayName.uppercased()) [\(configuration.summary)]
            \(destinationArgumentsDescription(builder.arguments(
                configuration: configuration,
                source: copy,
                sourceInfo: sourceMedia.info,
                destination: directory.appendingPathComponent("out.mp4")
            )))
            """)

            let start = Date()
            let service = CompressionService(
                tools: tools,
                runner: ProcessRunner(),
                logger: LoggingService(configuration: AppConfiguration(
                    watchDirectory: directory,
                    logDirectory: directory.appendingPathComponent("logs")
                )),
                cleanup: FileCleanupService(trash: { url in
                    try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("trashed-\(url.lastPathComponent)"))
                })
            )
            let result = try await service.compress(source: copy, configuration: configuration) { _ in }
            let elapsed = Date().timeIntervalSince(start)

            guard let output = result.outputURL, let outputBytes = result.outputSize else {
                XCTFail("preset \(preset) produced no output")
                continue
            }
            keep(output, named: "\(preset.rawValue).mp4")
            let saved = result.savedPercentage ?? 0
            let ssim = try await similarity(reference: source, encoded: output, directory: directory,
                                           ffmpeg: ffmpeg, ffprobe: ffprobe)
            record(String(format: "  -> %@  %@  %.1f%% saved  SSIM %@  %.0fs",
                          FileSizeFormatter.string(outputBytes),
                          "from \(FileSizeFormatter.string(sourceBytes))",
                          saved, ssim, elapsed))
            XCTAssertGreaterThan(outputBytes, 0)
            XCTAssertLessThan(outputBytes, sourceBytes, "preset \(preset) made the file larger")
        }
    }

    /// Copies an encoded file out of the temporary directory so frames can be inspected later.
    private func keep(_ url: URL, named name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_BENCHMARK_OUTPUT"] else { return }
        let destination = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
            .appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) throws -> Int64 {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw CompressionError.sourceMissing
        }
        return size.int64Value
    }

    private func probe(_ url: URL, ffprobe: URL) async throws -> ProbedMedia {
        let result = try await ProcessRunner().run(executable: ffprobe, arguments: [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height,avg_frame_rate,r_frame_rate,bit_rate",
            "-show_entries", "format=duration,bit_rate", "-of", "json", url.path
        ], onStdoutLine: { _ in })
        return MediaProbe.parse(Data(result.stdout.utf8)) ?? ProbedMedia(info: .unknown, videoCodecName: nil)
    }

    /// SSIM against the source, with the reference frame rate and geometry matched to the
    /// encoded file so a frame-rate or resolution reduction is not counted as distortion.
    private func similarity(reference: URL, encoded: URL, directory: URL,
                            ffmpeg: URL, ffprobe: URL) async throws -> String {
        let encodedMedia = try await probe(encoded, ffprobe: ffprobe)
        let width = encodedMedia.info.width ?? 0
        let height = encodedMedia.info.height ?? 0
        let frameRate = encodedMedia.info.frameRate ?? 0
        guard width > 0, height > 0, frameRate > 0 else { return "n/a" }
        // A fixed name: the finalized output keeps the recording's timestamp, and spaces in a
        // filter argument would truncate the path.
        let stats = directory.appendingPathComponent("ssim-stats.log")
        let filter = "[0:v]setsar=1[enc];"
            + "[1:v]fps=\(String(format: "%.6f", frameRate)),scale=\(width):\(height):flags=lanczos,setsar=1[ref];"
            + "[enc][ref]ssim=stats_file=\(stats.path)"
        _ = try await ProcessRunner().run(executable: ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-i", encoded.path, "-i", reference.path,
            "-lavfi", filter, "-f", "null", "-"
        ], onStdoutLine: { _ in })
        guard let contents = try? String(contentsOf: stats, encoding: .utf8) else { return "n/a" }
        let last = contents.split(separator: "\n").last { $0.contains("All:") }
        guard let last,
              let range = last.range(of: "All:"),
              let value = last[range.upperBound...].split(separator: " ").first else { return "n/a" }
        return String(value.prefix(8))
    }

    /// Drops the process-launch plumbing so the printed line is the interesting part.
    private func destinationArgumentsDescription(_ arguments: [String]) -> String {
        let trimmed = arguments.dropFirst(2).dropLast(3)
        return "ffmpeg " + trimmed.joined(separator: " ")
    }
}
