// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit

// Editable artwork shared by the app icon, menu bar and repository graphics.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let iconset = destination.appendingPathComponent("ZenTouch.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let mint = NSColor(srgbRed: 0.30, green: 0.96, blue: 0.80, alpha: 1)
let coral = NSColor(srgbRed: 1, green: 0.65, blue: 0.44, alpha: 1)
let pale = NSColor(srgbRed: 0.88, green: 0.98, blue: 1, alpha: 1)
let muted = NSColor(srgbRed: 0.58, green: 0.69, blue: 0.78, alpha: 1)
func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}
func line(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}
func contact(_ point: NSPoint, radius: CGFloat, color: NSColor, rings: Bool = true) {
    if rings {
        for scale in [CGFloat(1.7), 2.4] {
            color.withAlphaComponent(scale == 1.7 ? 0.45 : 0.15).setStroke()
            let ring = NSBezierPath(
                ovalIn: NSRect(
                    x: point.x - radius * scale, y: point.y - radius * scale,
                    width: radius * scale * 2, height: radius * scale * 2))
            ring.lineWidth = max(2, radius * 0.13)
            ring.stroke()
        }
    }
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    (value as NSString).draw(
        at: NSPoint(x: x, y: y),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ])
}
func gradient(_ path: NSBezierPath, _ start: NSColor, _ end: NSColor) {
    NSGradient(starting: start, ending: end)?.draw(in: path, angle: -55)
}
func icon(template: Bool, disconnected: Bool = false) {
    let screen = rect(230, 360, 564, 390, 48)
    if !template {
        let tile = rect(96, 96, 832, 832, 184)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 32
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        gradient(
            tile, NSColor(srgbRed: 0.13, green: 0.25, blue: 0.35, alpha: 1),
            NSColor(srgbRed: 0.025, green: 0.065, blue: 0.13, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        pale.withAlphaComponent(0.14).setStroke()
        tile.lineWidth = 3
        tile.stroke()
        gradient(
            screen, NSColor(srgbRed: 0.08, green: 0.19, blue: 0.28, alpha: 1),
            NSColor(srgbRed: 0.035, green: 0.10, blue: 0.17, alpha: 1))
    }
    let ink = template ? NSColor.black : pale.withAlphaComponent(0.9)
    screen.lineWidth = template ? 62 : 20
    ink.setStroke()
    screen.stroke()
    line([NSPoint(x: 512, y: 360), NSPoint(x: 512, y: 268)], color: ink, width: template ? 62 : 20)
    line([NSPoint(x: 405, y: 268), NSPoint(x: 619, y: 268)], color: ink, width: template ? 62 : 20)
    if !template {
        line([NSPoint(x: 340, y: 470), NSPoint(x: 430, y: 550)], color: mint.withAlphaComponent(0.24), width: 36)
        line([NSPoint(x: 588, y: 558), NSPoint(x: 678, y: 638)], color: coral.withAlphaComponent(0.24), width: 36)
    }
    if disconnected {
        let slash = [NSPoint(x: 190, y: 230), NSPoint(x: 844, y: 820)]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        line(slash, color: .black, width: 130)
        NSGraphicsContext.restoreGraphicsState()
        line(slash, color: .black, width: 62)
    } else {
        contact(NSPoint(x: 430, y: 550), radius: template ? 45 : 31, color: template ? .black : mint, rings: !template)
        contact(NSPoint(x: 678, y: 638), radius: template ? 45 : 31, color: template ? .black : coral, rings: !template)
    }
}
func render(width: Int, height: Int, drawing: () -> Void) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw NSError(domain: "ZenTouchArtwork", code: 1) }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    drawing()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ZenTouchArtwork", code: 2)
    }
    return png
}
func iconPNG(size: Int, template: Bool = false, disconnected: Bool = false) throws -> Data {
    try render(width: size, height: size) {
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(size) / 1024)
        transform.concat()
        icon(template: template, disconnected: disconnected)
    }
}
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try iconPNG(size: base * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try iconPNG(size: 54, template: true).write(to: destination.appendingPathComponent("MenuBarTemplate.png"))
try iconPNG(size: 54, template: true, disconnected: true).write(
    to: destination.appendingPathComponent("MenuBarDisconnectedTemplate.png"))
try iconPNG(size: 1024).write(to: destination.appendingPathComponent("app-icon.png"))
try render(width: 1600, height: 640) {
    gradient(
        rect(0, 0, 1600, 640, 0),
        NSColor(srgbRed: 0.07, green: 0.14, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.02, green: 0.045, blue: 0.09, alpha: 1))
    for index in 0...9 {
        line(
            [NSPoint(x: 840 + index * 84, y: 0), NSPoint(x: 840 + index * 84, y: 640)],
            color: pale.withAlphaComponent(0.035), width: 1)
    }
    text("ZenTouch", x: 96, y: 344, size: 100, color: pale, weight: .bold)
    text("Multi-touch for your ZenScreen.", x: 102, y: 278, size: 35, color: mint, weight: .medium)
    text("Tap. Drag. Scroll.", x: 102, y: 214, size: 27, color: muted)
    line([NSPoint(x: 104, y: 156), NSPoint(x: 170, y: 156)], color: coral, width: 4)
    text("macOS  ·  USB touch  ·  Menu bar", x: 102, y: 104, size: 20, color: muted)
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 908, yBy: 28)
    transform.scale(by: 0.56)
    transform.concat()
    icon(template: false)
    NSGraphicsContext.restoreGraphicsState()
}.write(to: destination.appendingPathComponent("readme-banner.png"))
try render(width: 1440, height: 380) {
    NSColor(srgbRed: 0.04, green: 0.08, blue: 0.13, alpha: 1).setFill()
    rect(0, 0, 1440, 380, 0).fill()
    for (index, label) in ["Tap to click", "Move to drag", "Two fingers to scroll"].enumerated() {
        let left = CGFloat(index * 480)
        pale.withAlphaComponent(0.075).setFill()
        rect(left + 24, 24, 456, 332, 24).fill()
        text(label, x: left + 50, y: 68, size: 27, color: pale, weight: .semibold)
        text(["One finger", "One finger", "Move together"][index], x: left + 50, y: 37, size: 18, color: muted)
        if index == 0 {
            contact(NSPoint(x: left + 208, y: 214), radius: 19, color: mint)
        } else if index == 1 {
            line(
                [NSPoint(x: left + 125, y: 177), NSPoint(x: left + 286, y: 247)], color: mint.withAlphaComponent(0.35),
                width: 5)
            line(
                [NSPoint(x: left + 271, y: 225), NSPoint(x: left + 290, y: 249), NSPoint(x: left + 263, y: 249)],
                color: mint, width: 4)
            contact(NSPoint(x: left + 245, y: 230), radius: 19, color: mint)
        } else {
            for (x, color) in [(left + 177, mint), (left + 295, coral)] {
                line([NSPoint(x: x, y: 165), NSPoint(x: x, y: 288)], color: color.withAlphaComponent(0.4), width: 4)
                line(
                    [NSPoint(x: x - 12, y: 274), NSPoint(x: x, y: 289), NSPoint(x: x + 12, y: 274)], color: color,
                    width: 4)
                contact(NSPoint(x: x, y: 223), radius: 17, color: color)
            }
        }
    }
}.write(to: destination.appendingPathComponent("gestures.png"))
print("Rendered ZenTouch app, menu bar, README and gesture artwork")
