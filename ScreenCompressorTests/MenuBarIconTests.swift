import AppKit
import XCTest
@testable import ScreenCompressor

/// The menu-bar ring is drawn by hand, so these check the pixels that come out of it.
final class MenuBarIconTests: XCTestCase {
    private let side = 18

    func testIdleIconIsATemplateSoTheMenuBarCanTintIt() {
        XCTAssertTrue(MenuBarIcon.idle.isTemplate)
    }

    func testColouredIconsAreNotTemplates() {
        XCTAssertFalse(MenuBarIcon.inProgress(fraction: 0.5).isTemplate)
        XCTAssertFalse(MenuBarIcon.indeterminate.isTemplate)
        XCTAssertFalse(MenuBarIcon.completed.isTemplate)
    }

    func testRingIsGreenAndOnlyFillsTheProgressedPart() throws {
        let pixels = try rasterize(MenuBarIcon.inProgress(fraction: 0.25))

        // A quarter of the ring runs clockwise from the top, so the top-right quadrant is
        // green and the top-left quadrant is still only the track.
        XCTAssertTrue(pixels.containsGreen(in: 11...16, rows: 1...6), "no green in the top-right quadrant")
        XCTAssertFalse(pixels.containsGreen(in: 1...6, rows: 1...6), "green leaked into the top-left quadrant")
        XCTAssertFalse(pixels.containsGreen(in: 1...16, rows: 12...16), "green leaked into the bottom half")
    }

    func testFullRingIsGreenAllTheWayRound() throws {
        let pixels = try rasterize(MenuBarIcon.completed)
        XCTAssertTrue(pixels.containsGreen(in: 11...16, rows: 1...6), "top-right")
        XCTAssertTrue(pixels.containsGreen(in: 1...6, rows: 1...6), "top-left")
        XCTAssertTrue(pixels.containsGreen(in: 1...16, rows: 12...16), "bottom")
    }

    func testIndeterminateIconShowsNoProgress() throws {
        // A recording of unknown duration must never look like it has made progress.
        let pixels = try rasterize(MenuBarIcon.indeterminate)
        XCTAssertFalse(pixels.containsGreen(in: 0...17, rows: 0...17))
        XCTAssertTrue(pixels.containsVisiblePixel)
    }

    func testEveryIconDrawsSomething() throws {
        let images = [
            MenuBarIcon.idle,
            MenuBarIcon.indeterminate,
            MenuBarIcon.completed,
            MenuBarIcon.inProgress(fraction: 0.6)
        ]
        for image in images {
            XCTAssertTrue(try rasterize(image).containsVisiblePixel)
        }
    }

    // MARK: - Helpers

    private func rasterize(_ image: NSImage) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

private extension NSBitmapImageRep {
    /// `colorAt` uses a top-left origin, so `rows` count down from the top of the icon.
    func containsGreen(in columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> Bool {
        for x in columns {
            for y in rows {
                guard let colour = colorAt(x: x, y: y), colour.alphaComponent > 0.5 else { continue }
                guard let rgb = colour.usingColorSpace(.deviceRGB) else { continue }
                if rgb.greenComponent > 0.6, rgb.redComponent < 0.6, rgb.blueComponent < 0.6 { return true }
            }
        }
        return false
    }

    var containsVisiblePixel: Bool {
        for x in 0..<pixelsWide {
            for y in 0..<pixelsHigh {
                if let colour = colorAt(x: x, y: y), colour.alphaComponent > 0.05 { return true }
            }
        }
        return false
    }
}
