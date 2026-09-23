import Foundation
import XCTest
@testable import ScreenCompressor

/// Isolated defaults so tests never read or write the user's real configuration.
func testDefaults() -> UserDefaults {
    let suite = "ScreenCompressorTests"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

final class UtilitiesTests: XCTestCase {
    func testBundledToolsTakePriorityOverInstalledTools() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = directory.appendingPathComponent("Test.app")
        let bin = bundle.appendingPathComponent("Contents/Resources/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["ffmpeg", "ffprobe"] {
            let executable = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        let service = FFmpegService(bundleURL: bundle)
        XCTAssertEqual(service.executable(named: "ffmpeg"), bin.appendingPathComponent("ffmpeg"))
        XCTAssertEqual(service.executable(named: "ffprobe"), bin.appendingPathComponent("ffprobe"))
    }

    func testFilenameCollisionsAndExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 0)
        let generator = FileNameGenerator()
        let first = generator.outputURL(for: date, in: directory)
        XCTAssertEqual(first.pathExtension, "mp4")
        XCTAssertFalse(first.lastPathComponent.contains(".mov"))
        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data()))
        let second = generator.outputURL(for: date, in: directory)
        XCTAssertTrue(second.lastPathComponent.hasSuffix(" 23.mp4"))
        XCTAssertTrue(FileManager.default.createFile(atPath: second.path, contents: Data()))
        XCTAssertTrue(generator.outputURL(for: date, in: directory).lastPathComponent.hasSuffix(" 24.mp4"))
    }

    func testProgressParsing() {
        let parser = FFmpegProgressParser()
        XCTAssertEqual(parser.parse("out_time_us=4821000")?.outputTime, 4.821)
        XCTAssertEqual(parser.parse("out_time_ms=4821000")?.outputTime, 4.821)
        XCTAssertEqual(parser.parse("out_time=00:01:02.500000")?.outputTime, 62.5)
        XCTAssertEqual(parser.parse("speed=3.14x")?.speed, 3.14)
        XCTAssertFalse(parser.parse("progress=continue")?.isComplete ?? true)
        XCTAssertTrue(parser.parse("progress=end")?.isComplete == true)
        XCTAssertNil(parser.parse("out_time_us=bad")?.outputTime)
        XCTAssertNil(parser.parse("out_time=bad")?.outputTime)
        XCTAssertNil(parser.parse("unknown=value"))
    }

    func testProgressAccumulatorKeepsLatestTimeSpeedAndSizes() async throws {
        let parser = FFmpegProgressParser()
        let accumulator = FFmpegProgressAccumulator(totalDuration: 10, sourceSize: 1_000)
        let time = try XCTUnwrap(parser.parse("out_time_us=5000000"))
        let first = await accumulator.update(time, currentOutputSize: 200)
        XCTAssertEqual(first.fractionCompleted, 0.5)
        XCTAssertEqual(first.sourceSize, 1_000)
        XCTAssertEqual(first.currentOutputSize, 200)
        XCTAssertNil(first.speed)

        let speed = try XCTUnwrap(parser.parse("speed=2.5x"))
        let second = await accumulator.update(speed, currentOutputSize: 300)
        XCTAssertEqual(second.fractionCompleted, 0.5)
        XCTAssertEqual(second.speed, 2.5)
        XCTAssertEqual(second.currentOutputSize, 300)

        let completion = try XCTUnwrap(parser.parse("progress=end"))
        let final = await accumulator.update(completion, currentOutputSize: 400)
        XCTAssertEqual(final.fractionCompleted, 1)
        XCTAssertEqual(final.speed, 2.5)
    }

    func testProgressWithoutDurationStaysIndeterminate() async throws {
        let accumulator = FFmpegProgressAccumulator(totalDuration: nil, sourceSize: 1_000)
        let completion = try XCTUnwrap(FFmpegProgressParser().parse("progress=end"))
        let progress = await accumulator.update(completion, currentOutputSize: 300)
        XCTAssertNil(progress.fractionCompleted)
    }

    func testRatio() {
        XCTAssertEqual(CompressionRatio.savedPercentage(source: 100, output: 25), 75)
        XCTAssertNil(CompressionRatio.savedPercentage(source: 0, output: 1))
        XCTAssertEqual(CompressionRatio.savedPercentage(source: 100, output: 120) ?? 0, -20, accuracy: 0.001)
    }

    func testExtremeReductionReportsNinetyNinePercentSaved() throws {
        let source: Int64 = 100_000_000
        let output: Int64 = 900_000
        let saved = try XCTUnwrap(CompressionRatio.savedPercentage(source: source, output: output))
        XCTAssertEqual(saved, 99.1, accuracy: 0.01)
        XCTAssertEqual(saved.formatted(.number.precision(.fractionLength(0))), "99")
        XCTAssertEqual(FileSizeFormatter.string(output), "900 KB")
    }
}

private enum FakeMode: Sendable { case success, encodeFailure, invalidOutput, probeFailure, changedSource, cancelled }

/// ffprobe answers as JSON, the way `MediaProbe` expects them.
private func probeJSON(codec: String = "hevc", width: Int = 1920, height: Int = 1080,
                       frameRate: String = "60/1", duration: String = "10.000000") -> String {
    """
    {"streams":[{"codec_name":"\(codec)","width":\(width),"height":\(height),
    "avg_frame_rate":"\(frameRate)","r_frame_rate":"\(frameRate)","bit_rate":"6000000"}],
    "format":{"duration":"\(duration)","bit_rate":"6000000"}}
    """
}

private struct FakeRunner: MediaProcessRunning {
    let mode: FakeMode

    func run(executable: URL, arguments: [String],
             onStdoutLine: @escaping @Sendable (String) async -> Void) async throws -> ProcessOutput {
        if arguments.first == "-v" {
            // Source probes point at the .mov, output verification points at the .mp4.
            let target = arguments.last ?? ""
            if target.hasSuffix(".mp4"), mode == .probeFailure {
                return ProcessOutput(status: 1, stdout: "", stderr: "probe failed")
            }
            return ProcessOutput(status: 0, stdout: probeJSON(), stderr: "")
        }
        guard let destinationPath = arguments.last else { throw CompressionError.invalidOutput }
        if mode == .cancelled {
            try await Task.sleep(for: .seconds(10))
            return ProcessOutput(status: 1, stdout: "", stderr: "cancelled")
        }
        if mode == .encodeFailure { return ProcessOutput(status: 1, stdout: "", stderr: "synthetic failure") }
        if mode == .changedSource, let inputIndex = arguments.firstIndex(of: "-i"), arguments.indices.contains(inputIndex + 1) {
            let source = URL(fileURLWithPath: arguments[inputIndex + 1])
            let handle = try FileHandle(forWritingTo: source)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("changed".utf8))
            try handle.close()
        }
        if mode != .invalidOutput { try Data("compressed".utf8).write(to: URL(fileURLWithPath: destinationPath)) }
        await onStdoutLine("out_time_us=5000000")
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }
}

final class CompressionSafetyTests: XCTestCase {
    private func setup(_ mode: FakeMode, cleanup: FileCleanupService = FileCleanupService(),
                       probeAvailable: Bool = true) throws -> (URL, URL, CompressionService) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Screen Recording.mov")
        try Data("original recording".utf8).write(to: source)
        let config = AppConfiguration(watchDirectory: directory, logDirectory: directory.appendingPathComponent("logs"))
        let fakeExecutable = URL(fileURLWithPath: "/usr/bin/true")
        var executables = ["ffmpeg": fakeExecutable]
        if probeAvailable { executables["ffprobe"] = fakeExecutable }
        let service = CompressionService(
            tools: FFmpegService(executables: executables),
            runner: FakeRunner(mode: mode), logger: LoggingService(configuration: config), cleanup: cleanup
        )
        return (directory, source, service)
    }

    private func partialOutputs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".processing.mp4") }
    }

    func testEncodeFailureKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.encodeFailure)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source, configuration: .balanced) { _ in }
            XCTFail("Expected encode failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testInvalidOutputKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.invalidOutput)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source, configuration: .balanced) { _ in }
            XCTFail("Expected output verification failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testProbeFailureKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.probeFailure)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source, configuration: .balanced) { _ in }
            XCTFail("Expected ffprobe verification failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testSourceChangeKeepsOriginal() async throws {
        let (directory, source, service) = try setup(.changedSource)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source, configuration: .balanced) { _ in }
            XCTFail("Expected changed source rejection")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testCollisionAndSafeTrashAfterVerification() async throws {
        let (directory, source, basicService) = try setup(.success)
        defer { try? FileManager.default.removeItem(at: directory) }
        let created = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: source.path)[.creationDate] as? Date)
        let existing = FileNameGenerator().outputURL(for: created, in: directory)
        try Data("user output".utf8).write(to: existing)
        let trash = directory.appendingPathComponent("test-trash.mov")
        var service = basicService
        service.cleanup = FileCleanupService(trash: { try FileManager.default.moveItem(at: $0, to: trash) })
        let result = try await service.compress(source: source, configuration: .balanced) { _ in }
        XCTAssertNotEqual(result.outputURL, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data("user output".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(result.savedPercentage, (1 - Double("compressed".utf8.count) / Double("original recording".utf8.count)) * 100)
    }

    func testTrashFailureLeavesSourceAndFinalOutput() async throws {
        let cleanup = FileCleanupService(trash: { _ in throw CompressionError.cleanupFailed("synthetic") })
        let (directory, source, service) = try setup(.success, cleanup: cleanup)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source, configuration: .balanced) { _ in }
            XCTFail("Expected Trash failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        let outputs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" && !$0.lastPathComponent.contains("processing") }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testCancellationKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.cancelled)
        defer { try? FileManager.default.removeItem(at: directory) }
        let job = Task { try await service.compress(source: source, configuration: .balanced) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        job.cancel()
        do {
            _ = try await job.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testMissingProbeUsesIndeterminateProgress() async throws {
        let (directory, source, basicService) = try setup(.success, probeAvailable: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trash = directory.appendingPathComponent("test-trash.mov")
        var service = basicService
        service.cleanup = FileCleanupService(trash: { try FileManager.default.moveItem(at: $0, to: trash) })
        let result = try await service.compress(source: source, configuration: .balanced) { progress in
            XCTAssertNil(progress.fractionCompleted)
        }
        XCTAssertNotNil(result.outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }
}

final class ProcessAndStabilizationTests: XCTestCase {
    func testProcessRunnerStreamsAndExits() async throws {
        let output = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["out_time_us=5000000"],
            onStdoutLine: { _ in }
        )
        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(output.stdout.contains("out_time_us=5000000"))
    }

    func testStableFileCompletesWithShortTestIntervals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recording.mov")
        try Data("video".utf8).write(to: file)
        var configuration = StabilizationConfiguration()
        configuration.interval = .milliseconds(1)
        configuration.timeout = .seconds(1)
        try await FileStabilizationService(configuration: configuration).waitUntilStable(file)
    }

    func testCancelledProcessTerminates() async throws {
        let task = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                          arguments: ["10"], onStdoutLine: { _ in })
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // ProcessRunner waits for termination before returning cancellation.
        }
    }
}

private actor ProgressSamples {
    private(set) var values: [CompressionProgress] = []

    func append(_ progress: CompressionProgress) {
        values.append(progress)
    }
}

final class RealPipelineTests: XCTestCase {
    func testHEVCConversionInTemporaryDirectory() async throws {
        guard ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 to run the hardware encoder test")
        }
        let bundlePath = ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_TEST_APP"]
        let bundleURL = bundlePath.map { URL(fileURLWithPath: $0) } ?? Bundle.main.bundleURL
        let tools = FFmpegService(bundleURL: bundleURL)
        guard let ffmpeg = tools.executable(named: "ffmpeg"), tools.executable(named: "ffprobe") != nil else {
            throw XCTSkip("ffmpeg and ffprobe are required for the integration test")
        }
        if bundlePath != nil {
            XCTAssertEqual(ffmpeg, bundleURL.appendingPathComponent("Contents/Resources/bin/ffmpeg"))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.mov")
        let fixture = try await ProcessRunner().run(
            executable: ffmpeg,
            arguments: ["-y", "-f", "lavfi", "-i", "testsrc2=size=128x128:rate=10",
                        "-t", "1", "-c:v", "h264_videotoolbox", "-pix_fmt", "yuv420p", source.path],
            onStdoutLine: { _ in }
        )
        XCTAssertEqual(fixture.status, 0, fixture.stderr)
        let fakeTrash = directory.appendingPathComponent("test-trash.mov")
        let cleanup = FileCleanupService(trash: { try FileManager.default.moveItem(at: $0, to: fakeTrash) })
        let app = AppConfiguration(watchDirectory: directory, logDirectory: directory.appendingPathComponent("logs"))
        let service = CompressionService(tools: tools, runner: ProcessRunner(),
                                         logger: LoggingService(configuration: app), cleanup: cleanup)
        let samples = ProgressSamples()
        let result = try await service.compress(source: source, configuration: .balanced) { await samples.append($0) }
        let progress = await samples.values
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertGreaterThan(result.outputSize ?? 0, 0)
        XCTAssertTrue(progress.contains { ($0.sourceSize ?? 0) > 0 })
        XCTAssertTrue(progress.contains { ($0.currentOutputSize ?? 0) > 0 })
        XCTAssertTrue(progress.contains { $0.fractionCompleted == 1 })
    }
}

private actor EncodeCounter {
    private(set) var active = 0
    private(set) var maximum = 0
    private(set) var completed = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
        completed += 1
    }
}

private struct SerialRunner: MediaProcessRunning {
    let counter: EncodeCounter

    func run(executable: URL, arguments: [String],
             onStdoutLine: @escaping @Sendable (String) async -> Void) async throws -> ProcessOutput {
        if arguments.first == "-v" {
            return ProcessOutput(status: 0, stdout: probeJSON(), stderr: "")
        }
        await counter.begin()
        try await Task.sleep(for: .milliseconds(40))
        guard let output = arguments.last else { throw CompressionError.invalidOutput }
        try Data("compressed".utf8).write(to: URL(fileURLWithPath: output))
        await counter.end()
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }
}

final class JobQueueTests: XCTestCase {
    func testConcurrentScansDeduplicateAndEncodeSerially() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("one".utf8).write(to: directory.appendingPathComponent("one.mov"))
        try Data("two".utf8).write(to: directory.appendingPathComponent("two.MOV"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("ignored.mp4"))
        let trash = directory.appendingPathComponent(".test-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let configuration = AppConfiguration(watchDirectory: directory, logDirectory: directory.appendingPathComponent("logs"))
        let logger = LoggingService(configuration: configuration)
        var stabilization = StabilizationConfiguration()
        stabilization.interval = .milliseconds(1)
        stabilization.timeout = .seconds(1)
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        let counter = EncodeCounter()
        let compressor = CompressionService(
            tools: FFmpegService(executables: ["ffmpeg": executable, "ffprobe": executable]),
            runner: SerialRunner(counter: counter), logger: logger,
            cleanup: FileCleanupService(trash: { source in
                try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
            })
        )
        let settings = CompressionSettingsStore(defaults: ConfigurationDefaults(storage: testDefaults()))
        let done = expectation(description: "two jobs completed")
        done.expectedFulfillmentCount = 2
        let queue = JobQueue(directory: directory,
                             stabilization: FileStabilizationService(configuration: stabilization),
                             compressor: compressor, settings: settings, logger: logger) { event in
            if case .completed = event { done.fulfill() }
        }
        async let first: Void = queue.scan()
        async let second: Void = queue.scan()
        _ = await (first, second)
        await fulfillment(of: [done], timeout: 5)
        await queue.shutdown()
        let maximum = await counter.maximum
        let completed = await counter.completed
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(completed, 2)
    }
}

private actor BatchRecorder {
    private(set) var events: [BatchProgress] = []

    func append(_ progress: BatchProgress) {
        events.append(progress)
    }
}

private struct HalfwayRunner: MediaProcessRunning {
    func run(executable: URL, arguments: [String],
             onStdoutLine: @escaping @Sendable (String) async -> Void) async throws -> ProcessOutput {
        if arguments.first == "-v" {
            return ProcessOutput(status: 0, stdout: probeJSON(), stderr: "")
        }
        guard let output = arguments.last else { throw CompressionError.invalidOutput }
        try Data("compressed".utf8).write(to: URL(fileURLWithPath: output))
        // Half of the ten second duration the probe reports.
        await onStdoutLine("out_time_us=5000000")
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }
}

/// Drives the real queue with several recordings and checks the overall progress it reports.
final class BatchProgressIntegrationTests: XCTestCase {
    func testQueueReportsOverallProgressAcrossThreeFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["a.mov", "b.mov", "c.mov"] {
            try Data("recording".utf8).write(to: directory.appendingPathComponent(name))
        }
        let trash = directory.appendingPathComponent("trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        var stabilization = StabilizationConfiguration()
        stabilization.interval = .milliseconds(1)
        stabilization.timeout = .seconds(1)
        let settingsConfiguration = AppConfiguration(watchDirectory: directory,
                                                     logDirectory: directory.appendingPathComponent("logs"))
        let logger = LoggingService(configuration: settingsConfiguration)
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        let compressor = CompressionService(
            tools: FFmpegService(executables: ["ffmpeg": executable, "ffprobe": executable]),
            runner: HalfwayRunner(), logger: logger,
            cleanup: FileCleanupService(trash: { source in
                try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
            })
        )

        let recorder = BatchRecorder()
        let done = expectation(description: "batch complete")
        done.assertForOverFulfill = false
        let queue = JobQueue(directory: directory,
                             stabilization: FileStabilizationService(configuration: stabilization),
                             compressor: compressor,
                             settings: CompressionSettingsStore(defaults: ConfigurationDefaults(storage: testDefaults())),
                             logger: logger) { event in
            guard case .batch(let progress) = event else { return }
            await recorder.append(progress)
            if progress.isComplete { done.fulfill() }
        }

        await queue.scan()
        await fulfillment(of: [done], timeout: 10)
        await queue.shutdown()

        let events = await recorder.events
        // The batch grows as recordings are found during the scan, but while it is running it
        // never shrinks, so the ring cannot jump backwards because a job finished. The trailing
        // idle event is what clears the batch once all of it is done.
        let totals = events.filter(\.isActive).map(\.totalJobs)
        XCTAssertEqual(totals.first, 1)
        XCTAssertEqual(totals.max(), 3)
        XCTAssertEqual(totals, totals.sorted(), "the batch size went backwards: \(totals)")
        XCTAssertEqual(events.first?.completedJobs, 0)

        // One recording finished, the next is half encoded, the third has not started:
        // (1 + 0.5 + 0) / 3.
        let halfway = try XCTUnwrap(events.first { $0.completedJobs == 1 && $0.currentFraction == 0.5 })
        XCTAssertEqual(halfway.currentJobNumber, 2)
        XCTAssertEqual(halfway.remainingJobs, 2)
        XCTAssertEqual(halfway.fraction ?? 0, 0.5, accuracy: 0.0001)

        let finished = try XCTUnwrap(events.last { $0.isComplete })
        XCTAssertEqual(finished.completedJobs, 3)
        XCTAssertEqual(finished.fraction, 1)
        XCTAssertEqual(finished.remainingJobs, 0)

        // The queue clears itself once the batch is drained.
        XCTAssertEqual(events.last, .idle)

        // Every recording was compressed and its original moved to Trash.
        for name in ["a.mov", "b.mov", "c.mov"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(name).path))
        }
        let outputs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(outputs.count, 3)
    }
}

final class FolderWatcherTests: XCTestCase {    @MainActor
    func testNativeWatcherNoticesNewFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = expectation(description: "directory write event")
        event.assertForOverFulfill = false
        let watcher = FolderWatcher()
        try watcher.start(directory: directory) { event.fulfill() }
        defer { watcher.stop() }
        try Data("video".utf8).write(to: directory.appendingPathComponent("new.mov"))
        await fulfillment(of: [event], timeout: 3)
    }
}
