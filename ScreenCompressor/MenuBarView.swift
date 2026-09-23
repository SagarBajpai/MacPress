import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let file = model.currentFile {
                currentJob(file)
                    .padding(.top, 14)
            }

            if let error = model.errorMessage {
                failure(error)
                    .padding(.top, 12)
            }

            qualitySection
                .padding(.top, 14)

            watchedFolderSection
                .padding(.top, 14)

            recentJobs.padding(.top, 14)

            secondaryActions
                .padding(.top, 14)
        }
        .padding(14)
        .frame(width: 336)
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacPress")
                    .font(.headline)
                Text("Automatically compresses your Mac screen recordings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(model.state)
                .font(.caption)
                .foregroundStyle(model.isCompressing ? .primary : .secondary)
                .padding(.top, 2)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("QUALITY")
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("Compression Quality")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Picker("Compression Quality", selection: Binding(
                    get: { model.compressionConfiguration.preset },
                    set: { model.applyPreset($0) }
                )) {
                    ForEach(CompressionPreset.selectable, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(model.isCompressing)
                .help(model.isCompressing ? "Quality can't be changed while compressing." : model.compressionConfiguration.preset.detail)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .help(model.isCompressing ? "Quality can't be changed while compressing." : "Choose the compression quality")
        }
    }

    private var secondaryActions: some View {
        VStack(alignment: .leading, spacing: 1) {
            Divider()
                .padding(.bottom, 5)
            MenuActionRow(title: "Advanced Settings…", symbol: "slider.horizontal.3") {
                model.openAdvancedSettings()
            }
            MenuActionRow(title: "View Logs", symbol: "doc.text") { openLogs() }
            Toggle(isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            )) {
                Label("Launch at Login", systemImage: "arrow.clockwise.circle")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
                .padding(.vertical, 5)
            MenuActionRow(title: "Quit", symbol: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private var watchedFolderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("WATCHING")
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.watchedFolder?.lastPathComponent ?? "No folder selected")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let folder = model.watchedFolder {
                        Text(folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.path)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .help("MacPress watches this folder for new .mov recordings and saves the compressed video in the same folder.")
            }
            HStack(spacing: 14) {
                Button("Open in Finder") {
                    if let folder = model.watchedFolder { NSWorkspace.shared.open(folder) }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.watchedFolder == nil)
                Button("Change…") { model.presentFolderPicker() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(model.isCompressing)
                    .help(model.isCompressing ? "Folder changes are unavailable while compressing." : "Choose a different folder")
            }
        }
    }

    @ViewBuilder
    private func currentJob(_ file: URL) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let position = model.batchPositionLabel {
                Text(position)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(file.lastPathComponent)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if model.state == "Preparing" {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for recording to finish")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Compressing")
                    Spacer()
                    if let fraction = model.progress?.fractionCompleted {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                    } else {
                        Text("Estimating…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let fraction = model.progress?.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                if model.isBatchActive, let overall = model.batch.fraction {
                    overallProgress(overall)
                }

                Text(sizeSummary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                HStack {
                    if let started = model.processingStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text("Elapsed \(elapsedTime(from: started, to: context.date))")
                        }
                    }
                    Spacer()
                    if let speed = model.progress?.speed, speed.isFinite, speed > 0 {
                        Text(String(format: "%.2fx", speed))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func overallProgress(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Overall")
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: fraction)

            if let remaining = model.remainingLabel {
                Text(remaining)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 3)
    }

    private var sizeSummary: String {
        let source = model.progress?.sourceSize.map(FileSizeFormatter.string) ?? "—"
        let output = model.progress?.currentOutputSize.map(FileSizeFormatter.string) ?? "—"
        return "\(source) → \(output)"
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(model.failedFile == nil ? "Needs attention" : "Couldn’t finish",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            if let file = model.failedFile {
                Text(file.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openLogs) {
                Label("View Logs", systemImage: "doc.text")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.top, 2)
            if model.failedFile == nil && model.watchedFolder == nil {
                Button("Choose Watched Folder…") { model.presentFolderPicker() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var recentJobs: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            if model.recent.isEmpty {
                Text("Completed recordings will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.recent) { result in
                    if result.outputURL == nil {
                        // Nothing to reveal, and the row should not look disabled.
                        RecentJobRow(result: result, reveal: nil)
                    } else {
                        RecentJobRow(result: result) { model.revealInFinder(result) }
                    }
                }
            }
        }
    }

    private func elapsedTime(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func openLogs() {
        let log = model.appConfiguration.logDirectory.appendingPathComponent("screen-compressor.log")
        let destination = FileManager.default.fileExists(atPath: log.path) ? log : model.appConfiguration.logDirectory
        NSWorkspace.shared.open(destination)
    }
}

/// One recent job. Successful jobs are clickable so the compressed file can be revealed
/// in Finder; failed jobs have nothing to reveal.
private struct RecentJobRow: View {
    let result: CompressionResult
    var reveal: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Button(action: { reveal?() }) {
            row
        }
        .buttonStyle(.plain)
        .disabled(reveal == nil)
        .help(reveal == nil ? "No output file" : "Show in Finder")
        .onHover { isHovered = $0 && reveal != nil }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.failureReason == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.failureReason == nil ? Color.green : Color.orange)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.outputURL?.lastPathComponent ?? result.sourceURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                details
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var details: some View {
        if let outputSize = result.outputSize {
            HStack(spacing: 4) {
                Text("\(FileSizeFormatter.string(result.sourceSize)) → \(FileSizeFormatter.string(outputSize))")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let saved = result.savedPercentage {
                    let percentage = abs(saved).formatted(.number.precision(.fractionLength(0)))
                    Text(saved >= 0 ? "• \(percentage)% saved" : "• \(percentage)% larger")
                        .fixedSize()
                }
            }
        } else {
            Text("Failed")
        }
    }
}

private struct MenuActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
