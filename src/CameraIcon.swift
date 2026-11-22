import AppKit

enum CameraIcon {
    static let blue = NSColor(srgbRed: 0.05, green: 0.46, blue: 0.98, alpha: 1)
    static let red = NSColor(srgbRed: 0.96, green: 0.16, blue: 0.20, alpha: 1)

    // Własny rysunek wektorowy, skalowany również na ekranach Retina.
    static func image(color: NSColor, size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = rect.width / 20
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 18, height: 12),
                         xRadius: 2.5, yRadius: 2.5).fill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 13, width: 8, height: 4),
                         xRadius: 1.2, yRadius: 1.2).fill()
            NSColor.white.setStroke()
            let lens = NSBezierPath(ovalIn: NSRect(x: 6.4, y: 5.4, width: 7.2, height: 7.2))
            lens.lineWidth = 1.5
            lens.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 15.1, y: 11.4, width: 1.6, height: 1.6)).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false // macOS nie zamienia niebieskiego/czerwonego na monochrom.
        return image
    }
}
