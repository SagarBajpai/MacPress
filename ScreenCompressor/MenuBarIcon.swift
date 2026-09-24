import AppKit

/// Draws the MacPress menu-bar icon wrapped in a green progress ring.
///
/// The ring is a real image rather than a template so the green survives menu-bar tinting.
/// Colours are resolved when the image is drawn, which is also when the current appearance
/// is read.
enum MenuBarIcon {
    static let idleSymbolName = "arrow.down.circle"
    static let completedSymbolName = "checkmark"

    private static let canvas = NSSize(width: 18, height: 18)
    private static let ringWidth: CGFloat = 2
    private static let symbolBox: CGFloat = 9

    /// Plain template symbol. AppKit tints it for the current menu-bar appearance.
    static var idle: NSImage {
        let base = NSImage(systemSymbolName: idleSymbolName, accessibilityDescription: "MacPress")
        guard let base else { return NSImage(size: canvas) }
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        ) ?? base
        let image = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app symbol inside a green ring filled clockwise to `fraction`.
    static func inProgress(fraction: Double) -> NSImage {
        image(fraction: min(max(fraction, 0), 1), symbolName: idleSymbolName)
    }

    /// Watching a recording whose duration is unknown: the ring track is shown, never faked.
    static var indeterminate: NSImage {
        image(fraction: nil, symbolName: idleSymbolName)
    }

    /// Full green ring with a checkmark, shown briefly when a batch finishes.
    static var completed: NSImage {
        image(fraction: 1, symbolName: completedSymbolName)
    }

    private static func image(fraction: Double?, symbolName: String) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - ringWidth / 2 - 1

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = ringWidth
            NSColor.labelColor.withAlphaComponent(fraction == nil ? 0.3 : 0.2).setStroke()
            track.stroke()

            if let fraction, fraction > 0.001 {
                let ring = NSBezierPath()
                // Menu-bar arcs start at the top and travel clockwise.
                ring.appendArc(withCenter: center, radius: radius,
                               startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                ring.lineWidth = ringWidth
                ring.lineCapStyle = .round
                NSColor.systemGreen.setStroke()
                ring.stroke()
            }

            if let symbol = tintedSymbol(symbolName) {
                let box = rect.insetBy(dx: (rect.width - symbolBox) / 2, dy: (rect.height - symbolBox) / 2)
                symbol.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// SF Symbols are template images; this bakes the menu-bar foreground colour into them
    /// so they can sit on top of the coloured ring.
    private static func tintedSymbol(_ name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: symbolBox, weight: .semibold)
        ) ?? base
        let tinted = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
