import SwiftUI
import AppKit

@main
struct ScreenCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MenuBarViewModel.shared

    var body: some Scene {
        MenuBarExtra("Screen Compressor", systemImage: model.menuSymbol) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await MenuBarViewModel.shared.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await MenuBarViewModel.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    static let shared = MenuBarViewModel()
    @Published private(set) var state = "Idle"
    @Published private(set) var currentFile: URL?
    @Published private(set) var progress: CompressionProgress?
    @Published private(set) var processingStartedAt: Date?
    @Published private(set) var recent: [CompressionResult] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var failedFile: URL?
    @Published private(set) var queuedCount = 0
    @Published private(set) var launchAtLoginEnabled = false

    let configuration = AppConfiguration.live
    private let login = LaunchAtLoginService()
    private var watcher: FolderWatcher?
    private var queue: JobQueue?
    private var started = false

    var menuSymbol: String {
        if errorMessage != nil { return "exclamationmark.circle" }
        return state == "Compressing" ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    var waitingCount: Int {
        let active = currentFile == nil ? 0 : 1
        return max(0, queuedCount - active)
    }

    func start() async {
        guard !started else { return }
        started = true
        launchAtLoginEnabled = login.isEnabled
        let logger = LoggingService(configuration: configuration)
        await logger.log("Application startup")
        do {
            try FileManager.default.createDirectory(at: configuration.watchDirectory, withIntermediateDirectories: true)
            let compressionConfig = CompressionConfiguration()
            let compressor = CompressionService(tools: FFmpegService(configuration: compressionConfig),
                                                runner: ProcessRunner(), logger: logger)
            let queue = JobQueue(directory: configuration.watchDirectory,
                                 stabilization: FileStabilizationService(configuration: compressionConfig),
                                 compressor: compressor, logger: logger) { [weak self] event in
                await self?.receive(event)
            }
            self.queue = queue
            let watcher = FolderWatcher()
            try watcher.start(directory: configuration.watchDirectory,
                              debounce: configuration.watcherDebounce) { [weak queue] in
                guard let queue else { return }
                Task { await queue.scan() }
            }
            self.watcher = watcher
            await logger.log("Watcher started: \(configuration.watchDirectory.path)")
            await queue.scan()
        } catch {
            state = "Error"
            errorMessage = "The Screenshots folder could not be watched."
            await logger.log("Startup failed: \(error)")
        }
    }

    func stop() async {
        watcher?.stop()
        watcher = nil
        await queue?.shutdown()
        queue = nil
        await LoggingService(configuration: configuration).log("Application shutdown")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let hadLoginError = errorMessage == "Launch at Login could not be changed."
        do {
            try login.setEnabled(enabled)
            launchAtLoginEnabled = login.isEnabled
            if hadLoginError {
                errorMessage = nil
                if currentFile == nil { state = "Idle" }
            }
        } catch {
            launchAtLoginEnabled = login.isEnabled
            failedFile = nil
            errorMessage = "Launch at Login could not be changed."
            if currentFile == nil { state = "Error" }
            Task { await LoggingService(configuration: configuration).log("Launch at Login failed: \(error)") }
        }
    }

    func refreshLaunchAtLogin() {
        launchAtLoginEnabled = login.isEnabled
    }

    private func receive(_ event: JobEvent) {
        switch event {
        case .queued(_, let count): queuedCount = count
        case .stabilizing(let file):
            state = "Preparing"; currentFile = file; progress = nil
            processingStartedAt = nil; failedFile = nil; errorMessage = nil
        case .processing(let file, let value):
            if state != "Compressing" || currentFile != file { processingStartedAt = Date() }
            state = "Compressing"; currentFile = file; progress = value; errorMessage = nil
        case .completed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(configuration.recentJobLimit))
            currentFile = nil; progress = nil; processingStartedAt = nil
            failedFile = nil; state = "Idle"; queuedCount = max(0, queuedCount - 1)
        case .failed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(configuration.recentJobLimit))
            errorMessage = result.failureReason
            failedFile = result.sourceURL
            currentFile = nil; progress = nil; processingStartedAt = nil
            state = "Error"; queuedCount = max(0, queuedCount - 1)
        case .monitoringError(let message):
            failedFile = nil; errorMessage = message
            if currentFile == nil { state = "Error" }
        }
    }
}
