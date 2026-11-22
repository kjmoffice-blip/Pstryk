import AppKit

@main struct IconBuilder {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for factor in [1, 2] {
                let size = points * factor
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let old = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSGraphicsContext.saveGraphicsState()
                let scale = CGFloat(size) / 1024
                let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
                NSColor(srgbRed: 0.94, green: 0.97, blue: 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884),
                             xRadius: 198, yRadius: 198).fill()
                CameraIcon.image(color: CameraIcon.blue, size: 620)
                    .draw(in: NSRect(x: 202, y: 202, width: 620, height: 620))
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.current = old
                let name = "icon_\(points)x\(points)" + (factor == 2 ? "@2x" : "") + ".png"
                try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
