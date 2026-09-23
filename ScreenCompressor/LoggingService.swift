import Foundation

actor LoggingService {
    private let configuration: AppConfiguration
    private let fileManager = FileManager.default
    private var progressMilestones: [URL: Set<Int>] = [:]

    init(configuration: AppConfiguration) { self.configuration = configuration }

    var logURL: URL { configuration.logDirectory.appendingPathComponent("screen-compressor.log") }

    func progress(_ fraction: Double?, for source: URL) {
        guard let fraction else { return }
        for threshold in [10, 25, 50, 75, 100] where fraction >= Double(threshold) / 100 {
            if progressMilestones[source, default: []].insert(threshold).inserted {
                log("Compression progress \(threshold)%: \(source.path)")
            }
        }
    }

    func finishProgress(for source: URL) {
        progressMilestones.removeValue(forKey: source)
    }

    func log(_ message: String) {
        do {
            try fileManager.createDirectory(at: configuration.logDirectory, withIntermediateDirectories: true)
            let url = logURL
            if let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value,
               size >= configuration.maximumLogBytes {
                let previous = configuration.logDirectory.appendingPathComponent("screen-compressor.previous.log")
                if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
                try fileManager.moveItem(at: url, to: previous)
            }
            let line = "\(Date().formatted(.iso8601)) \(message)\n"
            if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            NSLog("ScreenCompressor logging failed: %@", error.localizedDescription)
        }
    }
}
