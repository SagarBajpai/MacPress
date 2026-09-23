import AppKit
import SwiftUI

/// Advanced encoder controls live in their own window because a menu bar popover cannot
/// hold a dozen settings comfortably. The preset picker stays in the menu.
struct AdvancedSettingsView: View {
    @ObservedObject var model: MenuBarViewModel

    private var configuration: CompressionConfiguration { model.compressionConfiguration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                presetSection
                videoSection
                qualitySection
                audioSection
                footer
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var presetSection: some View {
        SettingsSection(title: "Preset", detail: configuration.preset.detail) {
            Picker("Quality", selection: Binding(
                get: { configuration.preset },
                set: { model.applyPreset($0) }
            )) {
                ForEach(CompressionPreset.selectable, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var videoSection: some View {
        SettingsSection(title: "Video") {
            SettingsRow(title: "Codec") {
                Picker("Codec", selection: binding(\.codec)) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsRow(title: "Quality Mode") {
                Picker("Quality Mode", selection: qualityModeBinding) {
                    ForEach(VideoQualityMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsRow(title: "Resolution") {
                Picker("Resolution", selection: binding(\.resolution)) {
                    ForEach(ResolutionOption.choices, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsRow(title: "Frame Rate") {
                Picker("Frame Rate", selection: binding(\.frameRate)) {
                    ForEach(FrameRateOption.choices, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if configuration.codec.pixelFormats.count > 1 {
                SettingsRow(title: "Colour Depth", detail: configuration.pixelFormat.detail) {
                    Picker("Colour Depth", selection: binding(\.pixelFormat)) {
                        ForEach(configuration.codec.pixelFormats, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            SettingsRow(title: "Profile") {
                Picker("Profile", selection: binding(\.profile)) {
                    ForEach(VideoProfile.options(for: configuration.codec), id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            SettingsRow(title: "Keyframe Interval", detail: "Longer intervals shrink static screens, shorter ones seek faster") {
                Picker("Keyframe Interval", selection: binding(\.keyframeInterval)) {
                    ForEach(KeyframeInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if configuration.resolution.heightValue != nil {
                SettingsRow(title: "Scaling", detail: configuration.scalingQuality.detail) {
                    Picker("Scaling", selection: binding(\.scalingQuality)) {
                        ForEach(ScalingQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var qualitySection: some View {
        SettingsSection(title: configuration.qualityMode == .constantQuality ? "Quality" : "Bitrate") {
            if configuration.qualityMode == .constantQuality {
                SettingsRow(title: "Quality", detail: "Higher keeps more detail and makes larger files") {
                    HStack(spacing: 10) {
                        Slider(value: qualityBinding,
                               in: Double(CompressionConfiguration.qualityRange.lowerBound)...Double(CompressionConfiguration.qualityRange.upperBound),
                               step: 1)
                        Text("\(configuration.quality)")
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            } else {
                SettingsRow(title: "Video Bitrate") {
                    Picker("Video Bitrate", selection: bitrateSelection) {
                        ForEach(VideoBitrate.choices, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                        if configuration.bitrate.isCustom {
                            Text("Custom").tag(configuration.bitrate)
                        }
                        // A value that is deliberately not one of the presets, so choosing it
                        // is what makes the bitrate custom and reveals the stepper.
                        Text("Custom…").tag(VideoBitrate.kbps(1800))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if configuration.bitrate.isCustom, let current = configuration.bitrate.kbps {
                    SettingsRow(title: "Custom Bitrate") {
                        Stepper(value: customBitrateBinding, in: 100...50_000, step: 100) {
                            Text("\(current) kbps")
                                .monospacedDigit()
                        }
                    }
                }

                SettingsRow(title: "Max Bitrate", detail: "Peak allowance above the target") {
                    Picker("Max Bitrate", selection: binding(\.bitrateCeiling)) {
                        ForEach(BitrateCeiling.allCases, id: \.self) { ceiling in
                            Text(ceiling.displayName).tag(ceiling)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                SettingsRow(title: "Constant Bitrate", detail: "Steadier stream, slightly larger file") {
                    Toggle("", isOn: binding(\.constantBitRate))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            SettingsRow(title: "Audio") {
                Picker("Audio", selection: binding(\.audioCodec)) {
                    ForEach(AudioCodec.allCases, id: \.self) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if configuration.audioCodec == .aac {
                SettingsRow(title: "Audio Bitrate") {
                    Picker("Audio Bitrate", selection: binding(\.audioBitrate)) {
                        ForEach(AudioBitrateOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings are saved and apply to recordings that have not started yet. A compression already running keeps the settings it started with.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reset to Balanced") { model.resetConfiguration() }
                .controlSize(.small)
        }
    }

    // MARK: - Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<CompressionConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: { value in model.updateConfiguration { $0[keyPath: keyPath] = value } }
        )
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { Double(configuration.quality) },
            set: { value in model.updateConfiguration { $0.quality = Int(value.rounded()) } }
        )
    }

    /// Switching to a target bitrate needs a concrete value, otherwise the configuration
    /// would collapse straight back to constant quality.
    private var qualityModeBinding: Binding<VideoQualityMode> {
        Binding(
            get: { configuration.qualityMode },
            set: { mode in
                model.updateConfiguration { config in
                    config.qualityMode = mode
                    if mode == .targetBitrate, config.bitrate.kbps == nil {
                        config.bitrate = .kbps(CompressionConfiguration.defaultBitrateKbps)
                    }
                }
            }
        )
    }

    /// A bitrate is only meaningful in target-bitrate mode, and "Auto" means constant quality.
    private var bitrateSelection: Binding<VideoBitrate> {
        Binding(
            get: { configuration.bitrate },
            set: { value in
                model.updateConfiguration { config in
                    config.bitrate = value
                    config.qualityMode = value == .automatic ? .constantQuality : .targetBitrate
                }
            }
        )
    }

    private var customBitrateBinding: Binding<Int> {
        Binding(
            get: { configuration.bitrate.kbps ?? CompressionConfiguration.defaultBitrateKbps },
            set: { value in
                model.updateConfiguration { config in
                    config.bitrate = .kbps(value)
                    config.qualityMode = .targetBitrate
                }
            }
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            content
                .frame(width: 190, alignment: .trailing)
        }
    }
}

/// Hosts the advanced settings in a plain AppKit window. A menu-bar-only app cannot rely on
/// a Dock or app menu to reopen a SwiftUI window scene.
@MainActor
enum AdvancedSettingsWindow {
    private static var window: NSWindow?

    static func show(model: MenuBarViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: AdvancedSettingsView(model: model))
        let frame = NSRect(x: 0, y: 0, width: 470, height: 580)
        hosting.frame = frame
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Compression"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
