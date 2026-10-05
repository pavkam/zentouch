// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import QuartzCore
import ZenTouchCore
import ZenTouchMac

private final class TouchIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A decorative, mouse-transparent surface on the selected display only.
final class TouchIndicatorOverlay {
    private var window: TouchIndicatorPanel?
    private var displayID: CGDirectDisplayID?
    private var displayFrame: CGRect?
    private var markers: [Int: CALayer] = [:]
    private var lastFrameAt: TimeInterval?
    private let now: () -> TimeInterval
    private var reduceMotion = false
    var indicatorCount: Int { markers.count }
    var isVisible: Bool { window?.isVisible == true }
    var positions: [Int: CGPoint] { markers.mapValues { $0.position } }
    var isNonInteractive: Bool {
        guard let window else { return false }
        return window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain
    }
    var pulseCount: Int {
        markers.values.filter { $0.sublayers?.first?.animation(forKey: "pulse") != nil }.count
    }

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func configure(enabled: Bool, target: ScreenTarget?, active: Bool) {
        guard enabled, active, let target, target.geometry?.supported == true,
            let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == target.id
            })
        else {
            stop()
            return
        }
        if target.id != displayID || screen.frame != displayFrame {
            stop()
            displayID = target.id
            displayFrame = screen.frame
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced != reduceMotion {
            reduceMotion = reduced
            for marker in markers.values {
                if let ring = marker.sublayers?.first { configurePulse(ring) }
            }
        }
    }

    func update(_ frame: TouchFrame) {
        guard let displayFrame else { return }
        guard !frame.touches.isEmpty else {
            hide()
            return
        }
        guard frame.touches.count <= 10, Set(frame.touches.map { $0.id }).count == frame.touches.count,
            frame.touches.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            hide()
            return
        }
        if window == nil { createWindow(frame: displayFrame) }
        guard let window, let root = window.contentView?.layer else { return }
        let ids = Set(frame.touches.map { $0.id })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in Array(markers.keys) where !ids.contains(id) {
            markers.removeValue(forKey: id)?.removeFromSuperlayer()
        }
        for touch in frame.touches {
            let marker: CALayer
            if let existing = markers[touch.id] {
                marker = existing
            } else {
                marker = makeMarker()
                markers[touch.id] = marker
                root.addSublayer(marker)
            }
            // Match the bridge's clamping; AppKit's display frame has a
            // bottom-left origin, while the controller reports top-left.
            marker.position = CGPoint(
                x: min(max(touch.x * displayFrame.width, 0), displayFrame.width - 1),
                y: displayFrame.height - min(max(touch.y * displayFrame.height, 0), displayFrame.height - 1))
        }
        CATransaction.commit()
        lastFrameAt = now()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func poll() {
        guard let lastFrameAt, now() - lastFrameAt > 2 else { return }
        hide()
    }

    /// Renders our own decorative layer only, for the no-input GUI smoke check.
    func writePreview(to output: URL) throws {
        guard let root = window?.contentView?.layer,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width), pixelsHigh: Int(root.bounds.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = CGContext(
                data: bitmap.bitmapData, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: bitmap.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ZenError(message: "Cannot render the touch indicator preview.") }
        root.render(in: context)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ZenError(message: "Cannot encode the touch indicator preview.")
        }
        try data.write(to: output, options: .atomic)
    }

    private func createWindow(frame: CGRect) {
        let panel = TouchIndicatorPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ZenTouch Touch Indicators"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setAccessibilityElement(false)
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.setAccessibilityElement(false)
        panel.contentView = view
        window = panel
    }

    private func makeMarker() -> CALayer {
        let marker = CALayer()
        marker.bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        ring.position = CGPoint(x: 40, y: 40)
        ring.cornerRadius = 22
        ring.borderWidth = 2
        ring.borderColor = NSColor.systemTeal.cgColor
        marker.addSublayer(ring)
        configurePulse(ring)
        let center = CALayer()
        center.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        center.position = CGPoint(x: 40, y: 40)
        center.cornerRadius = 14
        center.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.28).cgColor
        center.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        center.borderWidth = 1.5
        center.shadowColor = NSColor.black.cgColor
        center.shadowOpacity = 0.3
        center.shadowRadius = 3
        center.shadowOffset = .zero
        marker.addSublayer(center)
        return marker
    }

    private func configurePulse(_ ring: CALayer) {
        ring.removeAllAnimations()
        ring.opacity = 0.7
        guard !reduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.85
        scale.toValue = 1.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [scale, fade]
        pulse.duration = 0.95
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(pulse, forKey: "pulse")
    }

    private func hide() {
        for marker in markers.values { marker.removeFromSuperlayer() }
        markers.removeAll()
        lastFrameAt = nil
        window?.orderOut(nil)
    }

    func stop() {
        hide()
        window?.close()
        window = nil
        displayID = nil
        displayFrame = nil
    }

    deinit { stop() }
}
