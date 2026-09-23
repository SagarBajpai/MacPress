import Foundation

actor JobQueue {
    private let directory: URL
    private let stabilization: FileStabilizationService
    private let compressor: CompressionService
    private let settings: CompressionSettingsStore
    private let logger: LoggingService
    private let onEvent: @Sendable (JobEvent) async -> Void
    private var pending: [URL] = []
    private var seen: Set<URL> = []
    private var worker: Task<Void, Never>?
    private var workerScheduled = false
    private var stopping = false
    private var batch = BatchProgressTracker()

    init(directory: URL, stabilization: FileStabilizationService, compressor: CompressionService,
         settings: CompressionSettingsStore, logger: LoggingService,
         onEvent: @escaping @Sendable (JobEvent) async -> Void) {
        self.directory = directory
        self.stabilization = stabilization
        self.compressor = compressor
        self.settings = settings
        self.logger = logger
        self.onEvent = onEvent
    }

    func scan() async {
        guard !stopping else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files where file.pathExtension.lowercased() == "mov" {
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]) else {
                    await logger.log("File metadata unavailable: \(file.path)")
                    continue
                }
                let name = file.lastPathComponent.lowercased()
                guard values.isRegularFile == true, values.isHidden != true,
                      values.isSymbolicLink != true, !name.hasPrefix("."),
                      !name.hasSuffix(".tmp.mov"), !name.hasSuffix(".partial.mov"),
                      !name.hasSuffix(".processing.mov") else { continue }
                await enqueue(file)
            }
        } catch {
            await logger.log("Directory scan failed: \(error)")
            await onEvent(.monitoringError("The watched folder could not be scanned. Choose another folder if it is unavailable."))
        }
    }

    func enqueue(_ file: URL) async {
        guard !stopping else { return }
        let canonical = file.standardizedFileURL
        guard seen.insert(canonical).inserted else { return }
        pending.append(canonical)
        let shouldStart = !workerScheduled
        if shouldStart { workerScheduled = true }
        await logger.log("File detected: \(canonical.path)")
        await logger.log("Job queued: \(canonical.path)")
        // The batch grows as recordings are queued but never shrinks while it runs.
        batch.add(canonical)
        await onEvent(.queued(canonical))
        await onEvent(.batch(batch.progress))
        if shouldStart, !stopping { worker = Task { await drain() } }
    }

    func shutdown() async {
        stopping = true
        pending.removeAll()
        let running = worker
        running?.cancel()
        await running?.value
        worker = nil
    }

    private func drain() async {
        while !pending.isEmpty, !Task.isCancelled {
            let file = pending.removeFirst()
            await onEvent(.stabilizing(file))
            await logger.log("Stabilizing: \(file.path)")
            do {
                try await stabilization.waitUntilStable(file)
                await logger.log("Stabilized: \(file.path)")
                // Snapshot the settings here so editing them mid-batch only affects
                // recordings that have not started yet.
                let configuration = await settings.configuration
                batch.begin(file)
                await onEvent(.batch(batch.progress))
                await onEvent(.processing(file, CompressionProgress(fractionCompleted: nil, processedDuration: nil, speed: nil)))
                let result = try await compressor.compress(source: file, configuration: configuration) { progress in
                    await self.handle(progress, for: file)
                }
                await logger.finishProgress(for: file)
                await onEvent(.completed(result))
            } catch {
                await logger.finishProgress(for: file)
                await logger.log("Job failed: \(file.path), \(error)")
                if !Task.isCancelled {
                    let result = CompressionResult(sourceURL: file, outputURL: nil,
                                                   sourceSize: 0, outputSize: nil,
                                                   completedAt: Date(), failureReason: error.localizedDescription)
                    await onEvent(.failed(result))
                }
            }
            // A failed job finishes its slot too: progress has to be able to reach the end of
            // the batch rather than stalling on a recording that could not be compressed.
            batch.finish(file)
            await onEvent(.batch(batch.progress))
        }
        worker = nil
        workerScheduled = false
        // The completed state is the last thing the UI sees before the batch is cleared.
        if !stopping {
            batch.reset()
            await onEvent(.batch(.idle))
        }
    }

    private func handle(_ progress: CompressionProgress, for file: URL) async {
        let previous = batch.progress
        await logger.progress(progress.fractionCompleted, for: file)
        batch.report(fraction: progress.fractionCompleted, for: file)
        await onEvent(.processing(file, progress))
        let updated = batch.progress
        if updated != previous { await onEvent(.batch(updated)) }
    }
}
