import AppKit

/// Draws the app icon (with today's date, like a real calendar) and the menu bar glyph.
enum IconRenderer {
    static func appIcon(size: CGFloat, date: Date = Date()) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let body = rect.insetBy(dx: size * 0.097, dy: size * 0.097)
            let radius = body.width * 0.27
            let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
            // Maps unit coordinates (origin top-left of the body) to the drawing rect.
            func pt(_ u: CGFloat, _ v: CGFloat) -> NSPoint {
                NSPoint(x: body.minX + u * body.width, y: body.maxY - v * body.height)
            }

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = size * 0.035
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.014)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [NSColor.white, NSColor(white: 0.965, alpha: 1)])?.draw(in: body, angle: -90)

            // Grid lines below the header
            let headerV: CGFloat = 0.252
            NSColor(red: 0.66, green: 0.76, blue: 0.88, alpha: 0.95).setStroke()
            for u: CGFloat in [0.213, 0.403, 0.593, 0.783] {
                let l = NSBezierPath(); l.lineWidth = body.width * 0.007
                l.move(to: pt(u, headerV)); l.line(to: pt(u, 1)); l.stroke()
            }
            for v: CGFloat in [0.29, 0.471, 0.651, 0.829] {
                let l = NSBezierPath(); l.lineWidth = body.width * 0.007
                l.move(to: pt(0, v)); l.line(to: pt(1, v)); l.stroke()
            }

            // Red header with a darker bottom edge
            let bandH = body.height * headerV
            let band = NSRect(x: body.minX, y: body.maxY - bandH, width: body.width, height: bandH)
            NSGradient(colors: [NSColor(red: 0.93, green: 0.30, blue: 0.24, alpha: 1), NSColor(red: 0.92, green: 0.24, blue: 0.14, alpha: 1)])?
                .draw(in: band, angle: -90)
            NSColor(red: 0.70, green: 0.15, blue: 0.08, alpha: 1).setFill()
            NSRect(x: band.minX, y: band.minY, width: band.width, height: body.width * 0.008).fill()
            NSGraphicsContext.restoreGraphicsState()

            // Colored event tiles
            let tile = body.width * 0.213
            let tiles: [(CGFloat, CGFloat, NSColor, NSColor)] = [
                (0.122, 0.378, NSColor(red: 0.35, green: 0.85, blue: 0.22, alpha: 1), NSColor(red: 0.36, green: 0.80, blue: 0.26, alpha: 1)),
                (0.500, 0.562, NSColor(red: 1.00, green: 0.78, blue: 0.25, alpha: 1), NSColor(red: 1.00, green: 0.74, blue: 0.27, alpha: 1)),
                (0.312, 0.736, NSColor(red: 0.22, green: 0.56, blue: 1.00, alpha: 1), NSColor(red: 0.38, green: 0.68, blue: 1.00, alpha: 1)),
                (0.686, 0.738, NSColor(red: 0.95, green: 0.30, blue: 0.95, alpha: 1), NSColor(red: 0.93, green: 0.45, blue: 0.93, alpha: 1))
            ]
            for (u, v, top, bottom) in tiles {
                let c = pt(u, v)
                let r = NSRect(x: c.x - tile / 2, y: c.y - tile / 2, width: tile, height: tile)
                let tp = NSBezierPath(roundedRect: r, xRadius: tile * 0.27, yRadius: tile * 0.27)
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = top.withAlphaComponent(0.55)
                glow.shadowBlurRadius = size * 0.022
                glow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
                glow.set()
                top.setFill()
                tp.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.saveGraphicsState()
                tp.addClip()
                NSGradient(colors: [top, bottom])?.draw(in: r, angle: -90)
                NSGraphicsContext.restoreGraphicsState()
            }
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
