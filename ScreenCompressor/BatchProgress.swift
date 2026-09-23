import Foundation

/// Progress of the batch of recordings currently being worked through.
///
/// Completed jobs count as 1, queued jobs count as 0, and the running job contributes its
/// real encoder progress. The denominator is the size of the batch, which never shrinks
/// while the batch is running.
struct BatchProgress: Equatable, Sendable {
    var totalJobs: Int = 0
    var completedJobs: Int = 0
    /// 1-based position of the job being compressed, when one is running.
    var currentJobNumber: Int?
    /// `nil` while the running job's total duration is unknown.
    var currentFraction: Double?
    /// Recordings left to finish, including the one being compressed.
    var remainingJobs: Int = 0

    static let idle = BatchProgress()

    var isActive: Bool { totalJobs > 0 }

    var fraction: Double? {
        guard totalJobs > 0 else { return nil }
        let finished = Double(completedJobs)
        let running = currentFraction ?? 0
        return min(1, max(0, (finished + running) / Double(totalJobs)))
    }

    /// A single job with no known duration cannot fill a ring meaningfully, so the caller
    /// shows an indeterminate state instead of a ring that sits at zero.
    var isDeterminate: Bool {
        guard totalJobs > 0 else { return false }
        return currentFraction != nil || completedJobs > 0 || totalJobs > 1
    }

    var isComplete: Bool { totalJobs > 0 && completedJobs >= totalJobs }
}

/// Bookkeeping for the jobs in the current batch. Batching is order based rather than
/// count based so that a job completing cannot silently change the denominator.
struct BatchProgressTracker: Equatable, Sendable {
    private(set) var jobs: [URL] = []
    private(set) var finished: Set<URL> = []
    private(set) var active: URL?
    private(set) var activeFraction: Double?

    mutating func add(_ url: URL) {
        guard !jobs.contains(url) else { return }
        jobs.append(url)
    }

    mutating func begin(_ url: URL) {
        add(url)
        active = url
        activeFraction = nil
    }

    mutating func report(fraction: Double?, for url: URL) {
        guard active == url else { return }
        activeFraction = fraction
    }

    /// Failures finish their job too: the batch has to be able to reach 100% even when a
    /// recording could not be compressed.
    mutating func finish(_ url: URL) {
        finished.insert(url)
        if active == url {
            active = nil
            activeFraction = nil
        }
    }

    mutating func reset() {
        self = BatchProgressTracker()
    }

    var progress: BatchProgress {
        let completed = finished.count
        let currentNumber = active.flatMap { job in jobs.firstIndex(of: job).map { $0 + 1 } }
        return BatchProgress(
            totalJobs: jobs.count,
            completedJobs: completed,
            currentJobNumber: currentNumber,
            currentFraction: active == nil ? nil : activeFraction,
            remainingJobs: max(0, jobs.count - completed)
        )
    }
}
