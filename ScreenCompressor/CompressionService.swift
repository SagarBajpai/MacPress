import Foundation
import Darwin

struct CompressionService: Sendable {
    let tools: FFmpegService
    let runner: any MediaProcessRunning
    let logger: LoggingService
    var cleanup = FileCleanupService()
    let filenames = FileNameGenerator()
    let parser = FFmpegProgressParser()

    func compress(
        source: URL,
        onProgress: @escaping @Sendable (CompressionProgress) async -> Void
    ) async throws -> CompressionResult {
        guard let ffmpeg = tools.executable(named: "ffmpeg") else { throw CompressionError.ffmpegNotFound }
        guard FileManager.default.fileExists(atPath: source.path) else { throw CompressionError.sourceMissing }
        let sourceSize = try fileSize(source)
        let originalIdentity = try SourceIdentity(url: source)
        let duration = await mediaDuration(source)
        let progressState = FFmpegProgressAccumulator(totalDuration: duration, sourceSize: sourceSize)
        let directory = source.deletingLastPathComponent()
        let partial = directory.appendingPathComponent(".\(UUID().uuidString).processing.mp4")
        let descriptor = open(partial.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CompressionError.processLaunchFailed("Could not reserve temporary output: \(errno)") }
        close(descriptor)

        var finalized: URL?
        do {
            await logger.log("Compression started: \(source.path)")
            await onProgress(CompressionProgress(fractionCompleted: nil, processedDuration: nil,
                                                 speed: nil, sourceSize: sourceSize, currentOutputSize: 0))
            let result = try await runner.run(
                executable: ffmpeg,
                arguments: tools.arguments(source: source, destination: partial)
            ) { line in
                guard let parsed = parser.parse(line) else { return }
                guard parsed.outputTime != nil || parsed.speed != nil || parsed.isComplete else { return }
                let currentSize = try? fileSize(partial)
                let progress = await progressState.update(parsed, currentOutputSize: currentSize)
                await onProgress(progress)
            }
            guard result.status == 0 else {
                await logger.log("ffmpeg failed (\(result.status)): \(result.stderr)")
                throw CompressionError.compressionFailed(result.stderr)
            }
            let outputSize = try fileSize(partial)
            guard outputSize > 0 else { throw CompressionError.invalidOutput }
            if let ffprobe = tools.executable(named: "ffprobe") {
                guard let outputDuration = await mediaDuration(partial), outputDuration > 0,
                      await hasHEVCVideo(partial, ffprobe: ffprobe) else {
                    throw CompressionError.invalidOutput
                }
            }
            await logger.log("Output verified: \(partial.path)")
            try Task.checkCancellation()
            finalized = try finalize(partial, in: directory, date: recordingDate(source))
            guard let finalized else { throw CompressionError.invalidOutput }
            guard try SourceIdentity(url: source) == originalIdentity else { throw CompressionError.sourceChanged }
            try Task.checkCancellation()
            do {
                try cleanup.trashSource(source)
            } catch {
                await logger.log("Source Trash failed: \(source.path), output: \(finalized.path), \(error)")
                throw CompressionError.cleanupFailed(error.localizedDescription)
            }
            await logger.log("Source trashed: \(source.path); completed: \(finalized.path)")
            return CompressionResult(sourceURL: source, outputURL: finalized, sourceSize: sourceSize,
                                     outputSize: outputSize, completedAt: Date(), failureReason: nil)
        } catch {
            // This UUID path is exclusively created for this attempt. Never remove a final output.
            if FileManager.default.fileExists(atPath: partial.path) {
                do { try FileManager.default.removeItem(at: partial) }
                catch { await logger.log("Partial cleanup failed: \(partial.path), \(error)") }
            }
            throw error
        }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        guard let value = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw CompressionError.invalidOutput
        }
        return value.int64Value
    }

    private func recordingDate(_ url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.creationDate] as? Date) ?? Date()
    }

    private func mediaDuration(_ url: URL) async -> Double? {
        guard let ffprobe = tools.executable(named: "ffprobe") else { return nil }
        let args = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        guard let result = try? await runner.run(executable: ffprobe, arguments: args, onStdoutLine: { _ in }), result.status == 0 else { return nil }
        return Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func hasHEVCVideo(_ url: URL, ffprobe: URL) async -> Bool {
        let args = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name",
                    "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        guard let result = try? await runner.run(executable: ffprobe, arguments: args, onStdoutLine: { _ in }),
              result.status == 0 else { return false }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hevc"
    }

    private func finalize(_ partial: URL, in directory: URL, date: Date) throws -> URL {
        var candidate = filenames.outputURL(for: date, in: directory)
        for _ in 0..<10_000 {
            // Hard-link creation is atomic and fails if another process owns the final name.
            if link(partial.path, candidate.path) == 0 {
                try FileManager.default.removeItem(at: partial)
                return candidate
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            candidate = filenames.outputURL(for: date, in: directory)
        }
        throw CompressionError.invalidOutput
    }
}

private struct SourceIdentity: Equatable {
    let size: Int64
    let modified: Date
    let fileNumber: UInt64

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            throw CompressionError.sourceMissing
        }
        self.size = size.int64Value
        self.modified = modified
        self.fileNumber = fileNumber.uint64Value
    }
}
