import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

protocol MediaProcessRunning: Sendable {
    func run(executable: URL, arguments: [String],
             onStdoutLine: @escaping @Sendable (String) async -> Void) async throws -> ProcessOutput
}

private final class ActiveProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let running = process
        lock.unlock()
        if running?.isRunning == true { running?.terminate() }
    }
}

struct ProcessRunner: MediaProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        onStdoutLine: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let active = ActiveProcess()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            active.set(process)
            do {
                try process.run()
            } catch {
                active.clear()
                throw CompressionError.processLaunchFailed(error.localizedDescription)
            }
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            if Task.isCancelled { active.terminate() }

            async let outputText = Self.read(stdout.fileHandleForReading, onLine: onStdoutLine)
            async let errorText = Self.read(stderr.fileHandleForReading, onLine: { _ in })
            let status = await Task.detached(priority: .utility) {
                process.waitUntilExit()
                return process.terminationStatus
            }.value
            let result = ProcessOutput(status: status, stdout: await outputText, stderr: await errorText)
            active.clear()
            try Task.checkCancellation()
            return result
        } onCancel: {
            active.terminate()
        }
    }

    private static func read(
        _ handle: FileHandle,
        onLine: @escaping @Sendable (String) async -> Void
    ) async -> String {
        await Task.detached(priority: .utility) {
            var buffer = Data()
            var captured = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if captured.count < 65_536 { captured.append(chunk.prefix(65_536 - captured.count)) }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = String(decoding: buffer[..<newline], as: UTF8.self)
                    buffer.removeSubrange(...newline)
                    await onLine(line)
                }
                if buffer.count > 16_384 { buffer.removeFirst(buffer.count - 16_384) }
            }
            if !buffer.isEmpty { await onLine(String(decoding: buffer, as: UTF8.self)) }
            return String(decoding: captured, as: UTF8.self)
        }.value
    }
}
