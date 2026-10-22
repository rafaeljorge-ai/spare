import AppKit

/// Mini Spare ring for the menu bar: a template image, so the system tints it for light and dark bars.
enum MenuBarIcon {
    static func ring(usedFraction: Double) -> NSImage {
        let used = min(1, max(0, usedFraction))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2 - 2
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * used, clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
