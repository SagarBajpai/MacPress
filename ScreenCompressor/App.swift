import SwiftUI
import AppKit

@main
struct ScreenCompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MenuBarViewModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: model.menuBarImage)
                .renderingMode(.original)
                .accessibilityLabel("Screen Compressor")
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
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var batch = BatchProgress.idle
    @Published private(set) var compressionConfiguration = CompressionConfiguration.balanced
    @Published private(set) var isShowingCompletion = false
    @Published private(set) var menuBarImage = MenuBarIcon.idle

    let appConfiguration = AppConfiguration.live
    private let login = LaunchAtLoginService()
    private let settingsStore = CompressionSettingsStore()
    private var watcher: FolderWatcher?
    private var queue: JobQueue?
    private var started = false
    private var completionFlash: Task<Void, Never>?
    private var renderedIcon: RenderedIcon?
    private var savedConfigurations: [CompressionPreset: CompressionConfiguration] = [:]

    /// What the menu-bar icon is currently showing. The ring reflects overall batch progress.
    private enum RenderedIcon: Equatable {
        case idle
        case indeterminate
        case completed
        case progress(Double)
    }

    /// True when more than one recording is being worked through.
    var isBatchActive: Bool { batch.totalJobs > 1 }

    var batchPositionLabel: String? {
        guard isBatchActive, let number = batch.currentJobNumber else { return nil }
        return "Compressing \(number) of \(batch.totalJobs)"
    }

    var remainingLabel: String? {
        guard isBatchActive, batch.remainingJobs > 0 else { return nil }
        return batch.remainingJobs == 1
            ? "1 recording remaining"
            : "\(batch.remainingJobs) recordings remaining"
    }

    func start() async {
        guard !started else { return }
        started = true
        launchAtLoginEnabled = login.isEnabled
        let configuration = await settingsStore.configuration
        compressionConfiguration = configuration
        savedConfigurations = await settingsStore.configurations()
        let logger = LoggingService(configuration: appConfiguration)
        await logger.log("Application startup [settings: \(configuration.summary)]")
        do {
            try FileManager.default.createDirectory(at: appConfiguration.watchDirectory, withIntermediateDirectories: true)
            let compressor = CompressionService(tools: FFmpegService(), runner: ProcessRunner(), logger: logger)
            let queue = JobQueue(directory: appConfiguration.watchDirectory,
                                 stabilization: FileStabilizationService(configuration: appConfiguration.stabilization),
                                 compressor: compressor, settings: settingsStore, logger: logger) { [weak self] event in
                await self?.receive(event)
            }
            self.queue = queue
            let watcher = FolderWatcher()
            try watcher.start(directory: appConfiguration.watchDirectory,
                              debounce: appConfiguration.watcherDebounce) { [weak queue] in
                guard let queue else { return }
                Task { await queue.scan() }
            }
            self.watcher = watcher
            await logger.log("Watcher started: \(appConfiguration.watchDirectory.path)")
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
        completionFlash?.cancel()
        completionFlash = nil
        await queue?.shutdown()
        queue = nil
        await LoggingService(configuration: appConfiguration).log("Application shutdown")
    }

    // MARK: - Compression settings

    /// Applies a preset to every underlying control.
    func applyPreset(_ preset: CompressionPreset) {
        if preset == .custom {
            var custom = compressionConfiguration
            custom.preset = .custom
            compressionConfiguration = custom
            savedConfigurations[.custom] = custom
            Task { await settingsStore.update(custom, for: .custom) }
            return
        }
        let configuration = savedConfigurations[preset] ?? compressionConfiguration.applying(preset)
        store(configuration)
    }

    func configuration(for preset: CompressionPreset) -> CompressionConfiguration {
        savedConfigurations[preset] ?? (preset.definition ?? compressionConfiguration)
    }

    func saveConfiguration(_ configuration: CompressionConfiguration, for preset: CompressionPreset) {
        let normalized = configuration.normalized()
        savedConfigurations[preset] = normalized
        compressionConfiguration = normalized
        Task { await settingsStore.update(normalized, for: preset) }
    }

    func resetConfiguration(for preset: CompressionPreset) -> CompressionConfiguration {
        let reset = preset.definition ?? .balanced
        savedConfigurations[preset] = reset
        if compressionConfiguration.preset == preset { compressionConfiguration = reset }
        Task { await settingsStore.reset(preset) }
        return reset
    }

    /// Applies a manual edit. Settings that no longer match a preset become Custom, and
    /// returning them to a preset's exact values shows that preset again.
    func updateConfiguration(_ edit: (inout CompressionConfiguration) -> Void) {
        var updated = compressionConfiguration
        edit(&updated)
        store(updated)
    }

    private func store(_ configuration: CompressionConfiguration) {
        let normalized = configuration.normalized()
        guard normalized != compressionConfiguration else { return }
        compressionConfiguration = normalized
        savedConfigurations[normalized.preset] = normalized
        Task { await settingsStore.update(normalized) }
    }

    func resetConfiguration() {
        store(CompressionConfiguration.balanced)
    }

    func openAdvancedSettings() {
        AdvancedSettingsWindow.show(model: self)
    }

    func revealInFinder(_ result: CompressionResult) {
        let url = result.outputURL ?? result.sourceURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Launch at login

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
            Task { await LoggingService(configuration: appConfiguration).log("Launch at Login failed: \(error)") }
        }
    }

    func refreshLaunchAtLogin() {
        launchAtLoginEnabled = login.isEnabled
    }

    // MARK: - Events

    private func receive(_ event: JobEvent) {
        switch event {
        case .queued:
            break
        case .stabilizing(let file):
            state = "Preparing"; currentFile = file; progress = nil
            processingStartedAt = nil; failedFile = nil; errorMessage = nil
        case .processing(let file, let value):
            if state != "Compressing" || currentFile != file { processingStartedAt = Date() }
            state = "Compressing"; currentFile = file; progress = value; errorMessage = nil
        case .completed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(appConfiguration.recentJobLimit))
            currentFile = nil; progress = nil; processingStartedAt = nil
            failedFile = nil; state = "Idle"
        case .failed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(appConfiguration.recentJobLimit))
            errorMessage = result.failureReason
            failedFile = result.sourceURL
            currentFile = nil; progress = nil; processingStartedAt = nil
            state = "Error"
        case .batch(let value):
            update(to: value)
        case .monitoringError(let message):
            failedFile = nil; errorMessage = message
            if currentFile == nil { state = "Error" }
        }
    }

    private func update(to value: BatchProgress) {
        if value.isComplete, !batch.isComplete {
            showCompletionFlash()
        } else if value.isActive, !value.isComplete {
            // A new batch started before the flash finished.
            completionFlash?.cancel()
            completionFlash = nil
            isShowingCompletion = false
        }
        batch = value
        refreshMenuBarIcon()
    }

    /// Holds the full green ring on screen for a moment so the finish is visible.
    private func showCompletionFlash() {
        completionFlash?.cancel()
        isShowingCompletion = true
        refreshMenuBarIcon()
        completionFlash = Task { [weak self] in
            try? await Task.sleep(for: self?.appConfiguration.completionFlashDuration ?? .seconds(1))
            guard !Task.isCancelled else { return }
            self?.isShowingCompletion = false
            self?.refreshMenuBarIcon()
        }
    }

    /// Redraws only when the icon would actually look different. Encoder progress arrives
    /// several times a second and each redraw allocates an image.
    private func refreshMenuBarIcon() {
        let icon: RenderedIcon
        if isShowingCompletion {
            icon = .completed
        } else if !batch.isActive {
            icon = .idle
        } else if let fraction = batch.fraction, batch.isDeterminate {
            // One percent is finer than the ring can show at 18 points.
            icon = .progress((fraction * 100).rounded() / 100)
        } else {
            icon = .indeterminate
        }
        guard icon != renderedIcon else { return }
        renderedIcon = icon
        switch icon {
        case .idle: menuBarImage = MenuBarIcon.idle
        case .indeterminate: menuBarImage = MenuBarIcon.indeterminate
        case .completed: menuBarImage = MenuBarIcon.completed
        case .progress(let fraction): menuBarImage = MenuBarIcon.inProgress(fraction: fraction)
        }
    }
}
