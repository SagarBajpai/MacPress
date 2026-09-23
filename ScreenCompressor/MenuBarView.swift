import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Screen Compressor").font(.headline)
                Spacer()
                Text(model.state).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            if let file = model.currentFile {
                Divider()
                currentJob(file).padding(.vertical, 11)
            }

            if model.waitingCount > 0 {
                Divider()
                Label(waitingLabel, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 9)
            }

            if let error = model.errorMessage {
                Divider()
                failure(error).padding(.vertical, 11)
            }

            if !model.recent.isEmpty {
                Divider()
                recentJobs.padding(.vertical, 10)
            }

            Divider().padding(.bottom, 6)
            MenuActionRow(title: "Open Screenshots Folder", symbol: "folder") {
                NSWorkspace.shared.open(model.configuration.watchDirectory)
            }
            MenuActionRow(title: "View Logs", symbol: "doc.text") { openLogs() }

            Toggle(isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().padding(.vertical, 6)
            MenuActionRow(title: "Quit", symbol: "xmark.circle") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private var waitingLabel: String {
        let count = model.waitingCount
        return count == 1 ? "1 recording waiting" : "\(count) recordings waiting"
    }

    @ViewBuilder
    private func currentJob(_ file: URL) -> some View {
        VStack(alignment: .leading, spacing: 7) {
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
        }
    }

    private var recentJobs: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.recent) { result in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: result.failureReason == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.failureReason == nil ? Color.green : Color.orange)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.outputURL?.lastPathComponent ?? result.sourceURL.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        recentDetails(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentDetails(_ result: CompressionResult) -> some View {
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

    private func elapsedTime(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func openLogs() {
        let log = model.configuration.logDirectory.appendingPathComponent("screen-compressor.log")
        let destination = FileManager.default.fileExists(atPath: log.path) ? log : model.configuration.logDirectory
        NSWorkspace.shared.open(destination)
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
