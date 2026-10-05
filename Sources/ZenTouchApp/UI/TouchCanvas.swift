// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

final class TouchCanvas: NSView {
    var touches: [Touch] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 170)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("ZenScreen finger contact preview")
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        if touches.isEmpty {
            let text = "Touch the ZenScreen to see your finger contacts."
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSString(string: text).draw(
                in: NSRect(x: 8, y: bounds.midY - 8, width: bounds.width - 16, height: 32),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ])
        }
        for touch in touches {
            let diameter = 30.0
            let rect = NSRect(
                x: touch.x * (bounds.width - diameter), y: touch.y * (bounds.height - diameter),
                width: diameter, height: diameter)
            NSColor.systemTeal.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let label = NSString(string: "\(touch.id + 1)")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
