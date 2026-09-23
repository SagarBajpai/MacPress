import Foundation
import XCTest
@testable import ScreenCompressor

final class CompressionPresetTests: XCTestCase {
    func testDefaultConfigurationMatchesBalanced() {
        XCTAssertEqual(CompressionConfiguration(), CompressionConfiguration.balanced)
        XCTAssertEqual(CompressionConfiguration().preset, .balanced)
    }

    func testEveryPresetIsItsOwnFixedPoint() throws {
        for preset in CompressionPreset.allCases where preset != .custom {
            let definition = try XCTUnwrap(preset.definition, "\(preset) has no definition")
            XCTAssertEqual(definition.preset, preset)
            XCTAssertEqual(definition.coerced(), definition, "\(preset) is not a valid configuration")
            XCTAssertEqual(definition.normalized(), definition, "\(preset) does not survive normalisation")
            XCTAssertEqual(CompressionPreset.matching(definition), preset)
            XCTAssertEqual(CompressionConfiguration.balanced.applying(preset), definition)
        }
    }

    func testEachPresetHasAnExpectedShape() throws {
        let high = try XCTUnwrap(CompressionPreset.high.definition)
        let balanced = try XCTUnwrap(CompressionPreset.balanced.definition)
        let medium = try XCTUnwrap(CompressionPreset.medium.definition)
        let low = try XCTUnwrap(CompressionPreset.low.definition)

        // Quality drops as presets get more aggressive. The quality number is comparable
        // across presets because the frame rate is the other half of the trade.
        XCTAssertGreaterThan(high.quality, balanced.quality)
        XCTAssertGreaterThan(balanced.quality, medium.quality)
        XCTAssertGreaterThan(medium.quality, low.quality)

        for configuration in [high, balanced, medium, low] {
            XCTAssertEqual(configuration.codec, .hevc)
            XCTAssertEqual(configuration.qualityMode, .constantQuality)
            XCTAssertEqual(configuration.audioCodec, .aac)
        }

        // High keeps the source untouched apart from quality.
        XCTAssertEqual(high.frameRate, .source)
        XCTAssertEqual(high.resolution, .source)
        XCTAssertEqual(high.audioBitrate, .kbps192)

        // Everything below High caps the frame rate, which is where most of the size comes from.
        for configuration in [balanced, medium, low] {
            XCTAssertEqual(configuration.frameRate, .fps(30))
        }

        // Balanced is the recommended default: full resolution, 30 fps.
        XCTAssertEqual(balanced.resolution, .source)

        // Low is the only preset that caps resolution.
        XCTAssertEqual(low.resolution, .height(1080))
        XCTAssertNil(medium.resolution.heightValue)
    }

    func testChangingAnAdvancedSettingBecomesCustom() {
        var configuration = CompressionConfiguration.balanced
        configuration.quality = 17
        XCTAssertEqual(configuration.normalized().preset, .custom)
        XCTAssertEqual(configuration.normalized().quality, 17)
    }

    func testChangingTheAudioBitrateBecomesCustom() {
        var configuration = CompressionConfiguration.medium
        configuration.audioBitrate = .kbps256
        XCTAssertEqual(configuration.normalized().preset, .custom)
    }

    func testRestoringPresetValuesShowsThePresetAgain() {
        var configuration = CompressionConfiguration.low
        configuration.quality = 5
        XCTAssertEqual(configuration.normalized().preset, .custom)

        configuration.quality = CompressionConfiguration.low.quality
        XCTAssertEqual(configuration.normalized().preset, .low)
    }

    func testSelectingAPresetReplacesEveryControl() {
        var configuration = CompressionConfiguration.highQuality
        configuration.frameRate = .fps(15)
        configuration.audioBitrate = .kbps64
        configuration.resolution = .height(480)

        let restored = configuration.applying(.medium)
        XCTAssertEqual(restored, CompressionConfiguration.medium)
        XCTAssertEqual(restored.preset, .medium)
    }

    func testCustomPresetHasNoDefinition() {
        XCTAssertNil(CompressionPreset.custom.definition)
        var configuration = CompressionConfiguration.balanced
        configuration.preset = .custom
        XCTAssertEqual(CompressionConfiguration.balanced.applying(.custom), configuration)
    }

    func testIncompatibleOptionsAreRepaired() {
        var tenBitH264 = CompressionConfiguration.balanced
        tenBitH264.codec = .h264
        XCTAssertEqual(tenBitH264.normalized().pixelFormat, .eightBit)
        XCTAssertEqual(tenBitH264.normalized().profile, .automatic)

        // An H.264 profile on 10-bit HEVC input is replaced by the profile that pixel format needs.
        var wrongProfile = CompressionConfiguration.balanced
        wrongProfile.profile = .h264High
        XCTAssertEqual(wrongProfile.normalized().pixelFormat, .tenBit)
        XCTAssertEqual(wrongProfile.normalized().profile, .hevcMain10)

        // An H.264 profile with 8-bit pixel format falls back to Auto.
        var eightBitWrongProfile = CompressionConfiguration.low
        eightBitWrongProfile.profile = .h264High
        XCTAssertEqual(eightBitWrongProfile.normalized().profile, .automatic)

        // 10-bit HEVC has to be encoded as Main10 or VideoToolbox refuses the session.
        var tenBit = CompressionConfiguration.highQuality
        tenBit.profile = .automatic
        tenBit.pixelFormat = .tenBit
        XCTAssertEqual(tenBit.normalized().profile, .hevcMain10)
    }

    func testQualityIsClampedToItsRange() {
        var configuration = CompressionConfiguration.balanced
        configuration.quality = 900
        XCTAssertEqual(configuration.normalized().quality, CompressionConfiguration.qualityRange.upperBound)
        configuration.quality = -20
        XCTAssertEqual(configuration.normalized().quality, CompressionConfiguration.qualityRange.lowerBound)
    }

    func testBitratePresetNamesReadWell() {
        XCTAssertEqual(VideoBitrate.automatic.displayName, "Auto")
        XCTAssertEqual(VideoBitrate.kbps(750).displayName, "750 kbps")
        XCTAssertEqual(VideoBitrate.kbps(1500).displayName, "1.5 Mbps")
        XCTAssertEqual(VideoBitrate.kbps(5000).displayName, "5 Mbps")
        XCTAssertTrue(VideoBitrate.kbps(1750).isCustom)
        XCTAssertFalse(VideoBitrate.kbps(2000).isCustom)
    }
}

final class CompressionSettingsStoreTests: XCTestCase {
    private func stored(_ store: CompressionSettingsStore) async -> CompressionConfiguration {
        await store.configuration
    }

    func testConfigurationSurvivesAReload() async throws {
        let defaults = ConfigurationDefaults(storage: testDefaults())
        let store = CompressionSettingsStore(defaults: defaults)
        var configuration = CompressionConfiguration.balanced
        configuration.quality = 21
        let expected = configuration.normalized()
        await store.update(configuration)

        let reloaded = CompressionSettingsStore(defaults: defaults)
        let value = await stored(reloaded)
        XCTAssertEqual(value, expected)
        XCTAssertEqual(value.preset, .custom)
    }

    func testUnknownStoredDataFallsBackToBalanced() async {
        let storage = testDefaults()
        storage.set(Data("not a configuration".utf8), forKey: CompressionSettingsStore.defaultKey)
        let value = await stored(CompressionSettingsStore(defaults: ConfigurationDefaults(storage: storage)))
        XCTAssertEqual(value, .balanced)
    }

    func testMissingStoredDataFallsBackToBalanced() async {
        let value = await stored(CompressionSettingsStore(defaults: ConfigurationDefaults(storage: testDefaults())))
        XCTAssertEqual(value, .balanced)
    }

    func testPresetConfigurationsSaveAndResetIndependently() async throws {
        let defaults = ConfigurationDefaults(storage: testDefaults())
        let store = CompressionSettingsStore(defaults: defaults)
        var low = CompressionConfiguration.low
        low.quality = 12
        await store.update(low, for: .low)

        let saved = await store.configurations()
        XCTAssertEqual(saved[.low]?.quality, 12)
        XCTAssertNil(saved[.high])

        await store.reset(.low)
        let reset = await store.configurations()
        XCTAssertEqual(reset[.low], .low)
    }
}

final class FFmpegArgumentBuilderTests: XCTestCase {
    private let builder = FFmpegArgumentBuilder()
    private let source = URL(fileURLWithPath: "/tmp/Screen Recording.mov")
    private let destination = URL(fileURLWithPath: "/tmp/output.mp4")
    private let sourceInfo = VideoSourceInfo(
        duration: 60, width: 2560, height: 1440, frameRate: 60, bitRate: 8_000_000
    )

    private func arguments(_ configuration: CompressionConfiguration) -> [String] {
        builder.arguments(configuration: configuration, source: source, sourceInfo: sourceInfo,
                          destination: destination)
    }

    func testFilenamesArePassedAsSeparateArguments() {
        let arguments = arguments(.balanced)
        XCTAssertTrue(arguments.contains(source.path))
        XCTAssertEqual(arguments.last, destination.path)
        XCTAssertFalse(arguments.contains { $0.contains("bash") || $0.contains("&&") })
    }

    func testConstantQualityUsesQualityAndNotBitrate() throws {
        let video = builder.videoArguments(configuration: .balanced, sourceInfo: sourceInfo)
        let qualityIndex = try XCTUnwrap(video.firstIndex(of: "-q:v"))
        XCTAssertEqual(video[qualityIndex + 1], "\(CompressionConfiguration.balanced.quality)")
        XCTAssertFalse(video.contains("-b:v"))
        XCTAssertFalse(video.contains("-maxrate"))
    }

    func testTargetBitrateUsesBitrateAndNotQuality() {
        var configuration = CompressionConfiguration.balanced
        configuration.qualityMode = .targetBitrate
        configuration.bitrate = .kbps(1500)
        configuration.bitrateCeiling = .twoTimes

        let video = builder.videoArguments(configuration: configuration, sourceInfo: sourceInfo)
        XCTAssertFalse(video.contains("-q:v"))
        XCTAssertEqual(value(of: "-b:v", in: video), "1500k")
        XCTAssertEqual(value(of: "-maxrate", in: video), "3000k")
        XCTAssertEqual(value(of: "-bufsize", in: video), "6000k")
    }

    func testConstantBitRateFlagIsOnlyAddedWhenRequested() {
        var configuration = CompressionConfiguration.balanced
        configuration.qualityMode = .targetBitrate
        configuration.bitrate = .kbps(2000)
        XCTAssertFalse(builder.videoArguments(configuration: configuration, sourceInfo: sourceInfo).contains("-constant_bit_rate"))

        configuration.constantBitRate = true
        XCTAssertEqual(value(of: "-constant_bit_rate", in: builder.videoArguments(configuration: configuration, sourceInfo: sourceInfo)), "1")
    }

    func testAutomaticBitrateCollapsesToConstantQuality() {
        var configuration = CompressionConfiguration.balanced
        configuration.qualityMode = .targetBitrate
        configuration.bitrate = .automatic
        let normalized = configuration.normalized()
        XCTAssertEqual(normalized.qualityMode, .constantQuality)
        XCTAssertTrue(builder.videoArguments(configuration: configuration, sourceInfo: sourceInfo).contains("-q:v"))
    }

    func testFrameRateIsOnlyReduced() {
        var configuration = CompressionConfiguration.balanced
        configuration.frameRate = .fps(30)
        XCTAssertEqual(builder.videoFilters(configuration: configuration, sourceInfo: sourceInfo), ["fps=30"])

        // A 30 fps source is left alone when 30 fps is requested.
        let slowerSource = VideoSourceInfo(duration: 60, width: 1920, height: 1080, frameRate: 30)
        XCTAssertTrue(builder.videoFilters(configuration: configuration, sourceInfo: slowerSource).isEmpty)

        // Asking for more frames than the source has would duplicate them.
        configuration.frameRate = .fps(60)
        XCTAssertTrue(builder.videoFilters(configuration: configuration, sourceInfo: slowerSource).isEmpty)
    }

    func testSourceFrameRateAddsNoFilter() {
        XCTAssertTrue(builder.videoFilters(configuration: .highQuality, sourceInfo: sourceInfo).isEmpty)
        XCTAssertTrue(builder.videoFilters(configuration: .balanced,
                                           sourceInfo: VideoSourceInfo(duration: 60, width: 2560, height: 1080,
                                                                       frameRate: 30)).isEmpty)
    }

    func testResolutionIsOnlyDownscaledAndKeepsTheAspectRatio() {
        var configuration = CompressionConfiguration.highQuality
        configuration.resolution = .height(1080)
        XCTAssertEqual(builder.videoFilters(configuration: configuration, sourceInfo: sourceInfo),
                       ["scale=-2:1080:flags=lanczos"])

        // Already smaller than the target: no upscaling.
        let smallSource = VideoSourceInfo(duration: 60, width: 1280, height: 720, frameRate: 60)
        XCTAssertTrue(builder.videoFilters(configuration: configuration, sourceInfo: smallSource).isEmpty)
    }

    func testFrameRateAndResolutionCombineInOneFilterChain() {
        var configuration = CompressionConfiguration.balanced
        configuration.frameRate = .fps(30)
        configuration.resolution = .height(720)
        XCTAssertEqual(builder.videoFilters(configuration: configuration, sourceInfo: sourceInfo),
                       ["fps=30", "scale=-2:720:flags=lanczos"])
    }

    func testScalingQualityIsCarriedIntoTheFilter() {
        var configuration = CompressionConfiguration.highQuality
        configuration.resolution = .height(720)
        configuration.scalingQuality = .bilinear
        XCTAssertEqual(builder.videoFilters(configuration: configuration, sourceInfo: sourceInfo),
                       ["scale=-2:720:flags=bilinear"])
    }

    func testCodecAndContainerTag() {
        let hevc = arguments(.balanced)
        XCTAssertEqual(value(of: "-c:v", in: hevc), "hevc_videotoolbox")
        XCTAssertEqual(value(of: "-tag:v", in: hevc), "hvc1")

        var h264 = CompressionConfiguration.balanced
        h264.codec = .h264
        let h264Arguments = arguments(h264)
        XCTAssertEqual(value(of: "-c:v", in: h264Arguments), "h264_videotoolbox")
        XCTAssertNil(value(of: "-tag:v", in: h264Arguments))
        XCTAssertEqual(value(of: "-pix_fmt", in: h264Arguments), "yuv420p")
    }

    func testTenBitUsesMain10() {
        let arguments = arguments(.balanced)
        XCTAssertEqual(value(of: "-pix_fmt", in: arguments), "p010le")
        XCTAssertEqual(value(of: "-profile:v", in: arguments), "main10")
    }

    func testKeyframeIntervalIsConvertedToFrames() {
        var configuration = CompressionConfiguration.highQuality
        configuration.keyframeInterval = .everyTenSeconds
        XCTAssertEqual(value(of: "-g", in: arguments(configuration)), "600")

        configuration.keyframeInterval = .everySecond
        XCTAssertEqual(value(of: "-g", in: arguments(configuration)), "60")

        configuration.keyframeInterval = .everyTenSeconds
        configuration.frameRate = .fps(30)
        XCTAssertEqual(value(of: "-g", in: arguments(configuration)), "300")
    }

    func testKeyframeIntervalIsAlwaysSent() {
        // Leaving the interval to VideoToolbox produces a keyframe every fifth of a second and
        // several times the file size, so the flag is never omitted.
        for configuration in [CompressionConfiguration.highQuality, .balanced, .medium, .low] {
            XCTAssertNotNil(value(of: "-g", in: arguments(configuration)), "\(configuration.preset) sends no keyframe interval")
        }

        // A target frame rate is enough to convert seconds into frames, even for a source whose
        // own frame rate could not be probed, and a fallback covers the case where neither is known.
        var unknownRate = CompressionConfiguration.highQuality
        unknownRate.frameRate = .source
        let arguments = builder.videoArguments(configuration: unknownRate,
                                              sourceInfo: VideoSourceInfo(width: 1920, height: 1080))
        XCTAssertEqual(value(of: "-g", in: arguments), "600")
    }

    func testAudioConfiguration() {
        XCTAssertEqual(builder.audioArguments(configuration: .balanced), ["-c:a", "aac", "-b:a", "128k"])

        var muted = CompressionConfiguration.balanced
        muted.audioCodec = .none
        XCTAssertEqual(builder.audioArguments(configuration: muted), ["-an"])

        var loud = CompressionConfiguration.balanced
        loud.audioBitrate = .kbps256
        XCTAssertEqual(builder.audioArguments(configuration: loud), ["-c:a", "aac", "-b:a", "256k"])
    }

    func testProgressReportingIsAlwaysRequested() {
        let arguments = arguments(.balanced)
        XCTAssertEqual(value(of: "-progress", in: arguments), "pipe:1")
        XCTAssertTrue(arguments.contains("-nostats"))
    }

    private func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

final class MediaProbeTests: XCTestCase {
    func testParsesStreamAndFormatFacts() throws {
        let json = """
        {"streams":[{"codec_name":"h264","width":2560,"height":1080,
        "avg_frame_rate":"79940/1343","r_frame_rate":"60/1","bit_rate":"6426380"}],
        "format":{"duration":"67.100000","bit_rate":"6514090"}}
        """
        let media = try XCTUnwrap(MediaProbe.parse(Data(json.utf8)))
        XCTAssertEqual(media.videoCodecName, "h264")
        XCTAssertEqual(media.info.width, 2560)
        XCTAssertEqual(media.info.height, 1080)
        XCTAssertEqual(media.info.duration ?? 0, 67.1, accuracy: 0.001)
        XCTAssertEqual(media.info.frameRate ?? 0, 59.52, accuracy: 0.01)
        XCTAssertEqual(media.info.bitRate, 6_426_380)
    }

    func testUnknownFrameRateIsReportedAsNil() {
        XCTAssertNil(MediaProbe.frameRate("0/0"))
        XCTAssertNil(MediaProbe.frameRate("N/A"))
        XCTAssertNil(MediaProbe.frameRate(nil))
        XCTAssertEqual(MediaProbe.frameRate("30/1") ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(MediaProbe.frameRate("25") ?? 0, 25, accuracy: 0.001)
    }

    func testMalformedProbeOutputDoesNotCrash() {
        XCTAssertNil(MediaProbe.parse(Data("garbage".utf8)))
        let media = MediaProbe.parse(Data("{}".utf8))
        XCTAssertNil(media?.info.width)
    }
}

final class BatchProgressTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/a.mov")
    private let b = URL(fileURLWithPath: "/tmp/b.mov")
    private let c = URL(fileURLWithPath: "/tmp/c.mov")

    func testEmptyBatchHasNoProgress() {
        let tracker = BatchProgressTracker()
        XCTAssertNil(tracker.progress.fraction)
        XCTAssertFalse(tracker.progress.isActive)
        XCTAssertFalse(tracker.progress.isComplete)
        XCTAssertFalse(tracker.progress.isDeterminate)
    }

    func testSingleJobAtFiftyPercent() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.begin(a)
        tracker.report(fraction: 0.5, for: a)
        XCTAssertEqual(tracker.progress.fraction ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(tracker.progress.currentJobNumber, 1)
        XCTAssertEqual(tracker.progress.remainingJobs, 1)
    }

    func testTwoJobsWhereOneIsDone() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.add(b)
        tracker.begin(a)
        tracker.report(fraction: 1, for: a)
        tracker.finish(a)
        tracker.begin(b)
        tracker.report(fraction: 0, for: b)
        XCTAssertEqual(tracker.progress.fraction ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(tracker.progress.completedJobs, 1)
        XCTAssertEqual(tracker.progress.currentJobNumber, 2)
        XCTAssertEqual(tracker.progress.remainingJobs, 1)
    }

    func testThreeJobsAtOneHundredFiftyAndZero() {
        var tracker = BatchProgressTracker()
        for job in [a, b, c] { tracker.add(job) }
        tracker.begin(a)
        tracker.report(fraction: 1, for: a)
        tracker.finish(a)
        tracker.begin(b)
        tracker.report(fraction: 0.5, for: b)
        XCTAssertEqual(tracker.progress.fraction ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(tracker.progress.totalJobs, 3)
        XCTAssertEqual(tracker.progress.completedJobs, 1)
        XCTAssertEqual(tracker.progress.remainingJobs, 2)
    }

    func testCompletedBatchIsOne() {
        var tracker = BatchProgressTracker()
        for job in [a, b, c] { tracker.add(job) }
        for job in [a, b, c] {
            tracker.begin(job)
            tracker.report(fraction: 1, for: job)
            tracker.finish(job)
        }
        XCTAssertEqual(tracker.progress.fraction, 1)
        XCTAssertTrue(tracker.progress.isComplete)
        XCTAssertEqual(tracker.progress.remainingJobs, 0)
        XCTAssertNil(tracker.progress.currentJobNumber)
    }

    func testDenominatorDoesNotShrinkWhenAJobCompletes() {
        var tracker = BatchProgressTracker()
        for job in [a, b, c] { tracker.add(job) }
        tracker.begin(a)
        tracker.report(fraction: 1, for: a)
        let before = tracker.progress.totalJobs
        tracker.finish(a)
        XCTAssertEqual(tracker.progress.totalJobs, before)
        XCTAssertEqual(tracker.progress.totalJobs, 3)
        // Still three quarters of the work left to account for.
        XCTAssertEqual(tracker.progress.completedJobs, 1)
    }

    func testFailedJobStillAdvancesTheBatch() {
        var tracker = BatchProgressTracker()
        for job in [a, b] { tracker.add(job) }
        tracker.begin(a)
        tracker.finish(a)
        XCTAssertEqual(tracker.progress.completedJobs, 1)
        XCTAssertEqual(tracker.progress.fraction ?? 0, 0.5, accuracy: 0.0001)
    }

    func testQueuedJobsCountAsZero() {
        var tracker = BatchProgressTracker()
        for job in [a, b, c] { tracker.add(job) }
        XCTAssertEqual(tracker.progress.fraction, 0)
        XCTAssertEqual(tracker.progress.completedJobs, 0)
        XCTAssertEqual(tracker.progress.remainingJobs, 3)
    }

    func testAddingTheSameJobTwiceIsIgnored() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.add(a)
        XCTAssertEqual(tracker.progress.totalJobs, 1)
    }

    func testProgressOfANonActiveJobIsIgnored() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.add(b)
        tracker.begin(b)
        tracker.report(fraction: 0.25, for: a)
        XCTAssertNil(tracker.progress.currentFraction)
        tracker.report(fraction: 0.25, for: b)
        XCTAssertEqual(tracker.progress.currentFraction ?? 0, 0.25, accuracy: 0.0001)
    }

    func testUnknownDurationIsNotDeterminateForASingleJob() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.begin(a)
        XCTAssertNil(tracker.progress.currentFraction)
        XCTAssertFalse(tracker.progress.isDeterminate)

        tracker.add(b)
        XCTAssertTrue(tracker.progress.isDeterminate)
    }

    func testResetClearsEverything() {
        var tracker = BatchProgressTracker()
        tracker.add(a)
        tracker.begin(a)
        tracker.reset()
        XCTAssertEqual(tracker.progress, .idle)
    }

    func testFractionsAreClamped() {
        let progress = BatchProgress(totalJobs: 1, completedJobs: 0, currentJobNumber: 1,
                                     currentFraction: 1.4, remainingJobs: 1)
        XCTAssertEqual(progress.fraction, 1)
        let negative = BatchProgress(totalJobs: 1, completedJobs: 0, currentJobNumber: 1,
                                     currentFraction: -0.5, remainingJobs: 1)
        XCTAssertEqual(negative.fraction, 0)
    }
}
