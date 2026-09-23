import Foundation
import XCTest
@testable import ScreenCompressor

final class UtilitiesTests: XCTestCase {
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

    func testRatio() {
        XCTAssertEqual(CompressionRatio.savedPercentage(source: 100, output: 25), 75)
        XCTAssertNil(CompressionRatio.savedPercentage(source: 0, output: 1))
        XCTAssertEqual(CompressionRatio.savedPercentage(source: 100, output: 120) ?? 0, -20, accuracy: 0.001)
    }
}

private enum FakeMode: Sendable { case success, encodeFailure, invalidOutput, probeFailure, changedSource, cancelled }

private struct FakeRunner: MediaProcessRunning {
    let mode: FakeMode

    func run(executable: URL, arguments: [String],
             onStdoutLine: @escaping @Sendable (String) async -> Void) async throws -> ProcessOutput {
        if arguments.first == "-v" {
            if arguments.contains("stream=codec_name") {
                return ProcessOutput(status: mode == .probeFailure ? 1 : 0, stdout: "hevc\n", stderr: "")
            }
            return ProcessOutput(status: 0, stdout: "10.0\n", stderr: "")
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
            tools: FFmpegService(configuration: CompressionConfiguration(),
                                 executables: executables),
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
            _ = try await service.compress(source: source) { _ in }
            XCTFail("Expected encode failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testInvalidOutputKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.invalidOutput)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source) { _ in }
            XCTFail("Expected output verification failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testProbeFailureKeepsSourceAndRemovesPartial() async throws {
        let (directory, source, service) = try setup(.probeFailure)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source) { _ in }
            XCTFail("Expected ffprobe verification failure")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)) }
        XCTAssertTrue(try partialOutputs(in: directory).isEmpty)
    }

    func testSourceChangeKeepsOriginal() async throws {
        let (directory, source, service) = try setup(.changedSource)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await service.compress(source: source) { _ in }
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
        let result = try await service.compress(source: source) { _ in }
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
            _ = try await service.compress(source: source) { _ in }
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
        let job = Task { try await service.compress(source: source) { _ in } }
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
        let result = try await service.compress(source: source) { progress in
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
        var configuration = CompressionConfiguration()
        configuration.stabilizationInterval = .milliseconds(1)
        configuration.stabilizationTimeout = .seconds(1)
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

final class RealPipelineTests: XCTestCase {
    func testHEVCConversionInTemporaryDirectory() async throws {
        guard ProcessInfo.processInfo.environment["SCREEN_COMPRESSOR_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 to run the hardware encoder test")
        }
        let tools = FFmpegService(configuration: CompressionConfiguration())
        guard let ffmpeg = tools.executable(named: "ffmpeg"), tools.executable(named: "ffprobe") != nil else {
            throw XCTSkip("ffmpeg and ffprobe are required for the integration test")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.mov")
        let fixture = try await ProcessRunner().run(
            executable: ffmpeg,
            arguments: ["-y", "-f", "lavfi", "-i", "testsrc2=size=128x128:rate=10",
                        "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", source.path],
            onStdoutLine: { _ in }
        )
        XCTAssertEqual(fixture.status, 0, fixture.stderr)
        let fakeTrash = directory.appendingPathComponent("test-trash.mov")
        let cleanup = FileCleanupService(trash: { try FileManager.default.moveItem(at: $0, to: fakeTrash) })
        let app = AppConfiguration(watchDirectory: directory, logDirectory: directory.appendingPathComponent("logs"))
        let service = CompressionService(tools: tools, runner: ProcessRunner(),
                                         logger: LoggingService(configuration: app), cleanup: cleanup)
        let result = try await service.compress(source: source) { _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertGreaterThan(result.outputSize ?? 0, 0)
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
            return ProcessOutput(status: 0, stdout: arguments.contains("stream=codec_name") ? "hevc\n" : "1.0\n", stderr: "")
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
        var compressionConfiguration = CompressionConfiguration()
        compressionConfiguration.stabilizationInterval = .milliseconds(1)
        compressionConfiguration.stabilizationTimeout = .seconds(1)
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        let counter = EncodeCounter()
        let compressor = CompressionService(
            tools: FFmpegService(configuration: compressionConfiguration,
                                 executables: ["ffmpeg": executable, "ffprobe": executable]),
            runner: SerialRunner(counter: counter), logger: logger,
            cleanup: FileCleanupService(trash: { source in
                try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
            })
        )
        let done = expectation(description: "two jobs completed")
        done.expectedFulfillmentCount = 2
        let queue = JobQueue(directory: directory,
                             stabilization: FileStabilizationService(configuration: compressionConfiguration),
                             compressor: compressor, logger: logger) { event in
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

final class FolderWatcherTests: XCTestCase {
    @MainActor
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
