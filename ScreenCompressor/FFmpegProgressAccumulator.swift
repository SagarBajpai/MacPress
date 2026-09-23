import Foundation

actor FFmpegProgressAccumulator {
    private let totalDuration: Double?
    private let sourceSize: Int64
    private var processedDuration: Double?
    private var speed: Double?

    init(totalDuration: Double?, sourceSize: Int64) {
        self.totalDuration = totalDuration
        self.sourceSize = sourceSize
    }

    func update(_ parsed: ParsedFFmpegProgress, currentOutputSize: Int64?) -> CompressionProgress {
        if let outputTime = parsed.outputTime { processedDuration = outputTime }
        if let currentSpeed = parsed.speed { speed = currentSpeed }

        let fraction = totalDuration.flatMap { duration -> Double? in
            guard duration > 0, let processedDuration else { return nil }
            return min(1, max(0, processedDuration / duration))
        }

        return CompressionProgress(
            fractionCompleted: parsed.isComplete && totalDuration != nil ? 1 : fraction,
            processedDuration: processedDuration,
            speed: speed,
            sourceSize: sourceSize,
            currentOutputSize: currentOutputSize
        )
    }
}
