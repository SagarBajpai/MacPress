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
    @Published private(set) var recent: [CompressionResult] = []
    @Published private(set) var errorMessage: String?
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
        do {
            try login.setEnabled(enabled)
            launchAtLoginEnabled = login.isEnabled
            errorMessage = nil
        } catch {
            launchAtLoginEnabled = login.isEnabled
            errorMessage = "Launch at Login could not be changed."
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
            state = "Preparing"; currentFile = file; progress = nil; errorMessage = nil
        case .processing(let file, let value):
            state = "Compressing"; currentFile = file; progress = value; errorMessage = nil
        case .completed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(configuration.recentJobLimit))
            currentFile = nil; progress = nil; state = "Idle"; queuedCount = max(0, queuedCount - 1)
        case .failed(let result):
            recent.insert(result, at: 0)
            recent = Array(recent.prefix(configuration.recentJobLimit))
            errorMessage = result.failureReason
            currentFile = nil; progress = nil; state = "Error"; queuedCount = max(0, queuedCount - 1)
        case .monitoringError(let message):
            errorMessage = message; state = "Error"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Screen Compressor", systemImage: model.menuSymbol).font(.headline)
                Spacer()
                Text(model.state).foregroundStyle(.secondary)
            }
            if let file = model.currentFile {
                Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                if let fraction = model.progress?.fractionCompleted {
                    ProgressView(value: fraction)
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(model.state == "Preparing" ? "Waiting for recording to finish" : "Compressing")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.queuedCount > 1 { Text("\(model.queuedCount - 1) queued").font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if !model.recent.isEmpty {
                Divider()
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                ForEach(model.recent) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(result.outputURL?.lastPathComponent ?? result.sourceURL.lastPathComponent,
                              systemImage: result.failureReason == nil ? "checkmark.circle" : "xmark.circle")
                            .lineLimit(1).truncationMode(.middle)
                        if let output = result.outputSize {
                            Text("\(FileSizeFormatter.string(result.sourceSize)) → \(FileSizeFormatter.string(output))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Button("Open Screenshots Folder") { NSWorkspace.shared.open(model.configuration.watchDirectory) }
            Button("View Logs") {
                let log = model.configuration.logDirectory.appendingPathComponent("screen-compressor.log")
                NSWorkspace.shared.open(FileManager.default.fileExists(atPath: log.path) ? log : model.configuration.logDirectory)
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { model.refreshLaunchAtLogin() }
    }
}
