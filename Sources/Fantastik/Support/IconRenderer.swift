import AppKit

/// Draws the app icon (with today's date, like a real calendar) and the menu bar glyph.
enum IconRenderer {
    static func appIcon(size: CGFloat, date: Date) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let body = rect.insetBy(dx: size * 0.085, dy: size * 0.085)
            let radius = body.width * 0.225
            let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = size * 0.03
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [NSColor.white, NSColor(white: 0.93, alpha: 1)])?.draw(in: body, angle: -90)
            let bandH = body.height * 0.29
            let band = NSRect(x: body.minX, y: body.maxY - bandH, width: body.width, height: bandH)
            NSGradient(colors: [NSColor(red: 1.0, green: 0.37, blue: 0.30, alpha: 1), NSColor(red: 0.90, green: 0.16, blue: 0.17, alpha: 1)])?
                .draw(in: band, angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            let c = Calendar.current
            let weekday = date.formatted(.dateTime.weekday(.wide)).uppercased()
            let day = "\(c.component(.day, from: date))"
            draw(weekday, in: band, font: .systemFont(ofSize: body.width * 0.095, weight: .semibold), color: NSColor.white.withAlphaComponent(0.95), kern: body.width * 0.012)
            let numRect = NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height - bandH)
            draw(day, in: numRect, font: .systemFont(ofSize: body.width * 0.5, weight: .medium), color: NSColor(white: 0.12, alpha: 1), kern: 0)
            return true
        }
    }

    private static func draw(_ s: String, in rect: NSRect, font: NSFont, color: NSColor, kern: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    /// Template image: rounded calendar glyph with the day of month.
    static func menuBarImage(day: Int) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            let r = NSRect(x: 1.5, y: 0.5, width: 17, height: 15)
            let p = NSBezierPath(roundedRect: r, xRadius: 3.6, yRadius: 3.6)
            p.lineWidth = 1.3
            NSColor.black.setStroke()
            p.stroke()
            let top = NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.maxY - 4.2, width: r.width, height: 4.2), xRadius: 3.6, yRadius: 3.6)
            NSColor.black.setFill()
            top.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5, weight: .bold), .foregroundColor: NSColor.black]
            let s = NSAttributedString(string: "\(day)", attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.minY + (r.height - 4.2 - sz.height) / 2 + 0.3))
            return true
        }
        img.isTemplate = true
        return img
    }

    /// `Fantastik --render-icon <dir>` writes an .iconset used by the bundle script.
    static func writeIconset(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let specs: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                      ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        for (name, px) in specs {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            appIcon(size: CGFloat(px), date: Date()).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
            }
        }
    }
}
