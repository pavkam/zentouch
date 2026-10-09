// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

extension GestureFeature {
    var title: String {
        switch self {
        case .clicks: return "Click & drag"
        case .scrolling: return "Scroll"
        case .pinch: return "Pinch to zoom"
        case .desktops: return "Switch desktops"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        }
    }
    var explanation: String {
        switch self {
        case .clicks: return "Tap or drag with one finger. Hold or tap with two for a secondary click."
        case .scrolling: return "Move two fingers together to scroll in any direction."
        case .pinch: return "Spread two fingers to zoom in; bring them together to zoom out."
        case .desktops: return "Swipe left or right with three fingers to move between desktops."
        case .missionControl: return "Swipe up with three fingers to see your open windows."
        case .appExpose: return "Swipe down with three fingers to see the current app’s windows."
        }
    }
}

/// A local illustration, never a source of injected input. The Settings timer
/// advances it only while this tab is visible and Reduce Motion is off.
final class GesturePreviewView: NSView {
    let feature: GestureFeature
    var progress = 0.35 { didSet { needsDisplay = true } }
    var enabled = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    init(feature: GestureFeature) {
        self.feature = feature
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(feature.explanation)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let wave = (1 - cos(progress * .pi * 2)) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let area = CGRect(x: center.x - 90, y: center.y - 28, width: 180, height: 56)
        let accent = NSColor.controlAccentColor.withAlphaComponent(enabled ? 1 : 0.35)
        func box(_ rect: CGRect, fill: NSColor, radius: CGFloat = 5) {
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func window(_ rect: CGRect, highlighted: Bool = false) {
            box(rect, fill: highlighted ? accent.withAlphaComponent(0.14) : NSColor.quaternaryLabelColor)
            box(
                CGRect(x: rect.minX + 5, y: rect.minY + 5, width: max(2, rect.width - 10), height: 3),
                fill: accent.withAlphaComponent(0.5), radius: 1)
        }
        func finger(_ point: CGPoint, pulse: Double = 0) {
            let halo = CGFloat(11 + pulse * 5)
            accent.withAlphaComponent(0.12 + pulse * 0.1).setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)).fill()
            accent.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill()
            NSColor.white.withAlphaComponent(0.75).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            ring.lineWidth = 1
            ring.stroke()
        }
        switch feature {
        case .clicks:
            let button = CGRect(x: center.x - 36, y: center.y - 12, width: 72, height: 25)
            box(button, fill: accent.withAlphaComponent(0.1 + wave * 0.14), radius: 7)
            finger(CGPoint(x: center.x - 32 + wave * 32, y: center.y), pulse: wave)
        case .scrolling:
            let clip = NSBezierPath(roundedRect: area, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            for index in -1..<5 {
                box(
                    CGRect(x: area.minX + 16, y: area.minY + CGFloat(index * 17) - wave * 25, width: 135, height: 4),
                    fill: NSColor.quaternaryLabelColor, radius: 2)
            }
            NSGraphicsContext.restoreGraphicsState()
            for x in [-10.0, 10.0] { finger(CGPoint(x: center.x + x, y: center.y + 14 - wave * 26)) }
        case .pinch:
            let scale = 0.75 + wave * 0.5
            window(
                CGRect(x: center.x - 48 * scale, y: center.y - 24 * scale, width: 96 * scale, height: 48 * scale),
                highlighted: true)
            for sign in [-1.0, 1.0] { finger(CGPoint(x: center.x + sign * (20 + wave * 32), y: center.y + 4)) }
        case .desktops:
            let offset = wave * 44
            window(CGRect(x: center.x - 69 - offset, y: center.y - 22, width: 80, height: 44))
            window(CGRect(x: center.x + 23 - offset, y: center.y - 22, width: 80, height: 44), highlighted: true)
            for index in -1...1 { finger(CGPoint(x: center.x + CGFloat(index * 17) + 26 - offset, y: center.y + 4)) }
        case .missionControl, .appExpose:
            let spread = wave * 22
            for index in -1...1 {
                window(
                    CGRect(
                        x: center.x - 23 + CGFloat(index) * (24 + spread), y: center.y - 20 + CGFloat(abs(index)) * 6,
                        width: 46, height: 36), highlighted: feature == .appExpose)
            }
            let movement = feature == .missionControl ? 15 - wave * 24 : -15 + wave * 24
            for index in -1...1 { finger(CGPoint(x: center.x + CGFloat(index * 17), y: center.y + movement)) }
        }
    }
}
