import Foundation
import Darwin

@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pendingScan: DispatchWorkItem?
    private var active = false

    func start(directory: URL, debounce: TimeInterval = 0.5,
               onChange: @escaping @Sendable () -> Void) throws {
        stop()
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        active = true
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.active == true else { return }
                self?.pendingScan?.cancel()
                let work = DispatchWorkItem(block: onChange)
                self?.pendingScan = work
                DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
            }
        }
        let opened = descriptor
        watcher.setCancelHandler { close(opened) }
        source = watcher
        watcher.resume()
    }

    func stop() {
        active = false
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
