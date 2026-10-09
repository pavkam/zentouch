// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

func magnificationEventsConvertToNativeAppKitPhases() throws {
    for (phase, expected): (GesturePhase, NSEvent.Phase) in [
        (.began, .began), (.changed, .changed), (.ended, .ended), (.cancelled, .cancelled),
    ] {
        let event = try MagnificationEvents.make(location: CGPoint(x: 200, y: 300), delta: 0.125, phase: phase)
        let native = try require(NSEvent(cgEvent: event))
        try expect(native.type == .magnify && native.phase == expected)
        try expect(abs(native.magnification - (phase == .changed ? 0.125 : 0)) < 0.00001)
    }
    for delta in [Double.nan, .infinity, -0.3, 0.3] {
        try expectThrows(MagnificationEvents.Failure.self) {
            try MagnificationEvents.make(location: .zero, delta: delta, phase: .changed)
        }
    }
    try expectThrows(MagnificationEvents.Failure.self) {
        try MagnificationEvents.make(location: CGPoint(x: CGFloat.nan, y: 0), delta: 0.1, phase: .changed)
    }
}

func localWindowEventsKeepTheirAppKitWindowIdentity() throws {
    _ = NSApplication.shared
    let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    // Production hit testing only routes to on-screen windows. Register the
    // fixture with WindowServer before asking AppKit to round-trip coordinates.
    window.orderFront(nil)
    let actual = window.frame
    let bounds = CGRect(
        x: actual.minX, y: CGDisplayBounds(CGMainDisplayID()).height - actual.maxY,
        width: actual.width, height: actual.height)
    let target = InputWindow(id: CGWindowID(window.windowNumber), pid: getpid(), bounds: bounds)
    let factory = WindowEventFactory()
    let point = CGPoint(x: bounds.minX + 180, y: bounds.minY + 80)
    for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
        let source = try require(
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
        let routed = try require(factory.make(source, target: target))
        let native = try require(NSEvent(cgEvent: routed))
        try expect(native.windowNumber == window.windowNumber)
        // Before dispatch, NSEvent(cgEvent:) exposes different coordinate
        // conventions on macOS 26. Delivered coordinates are covered by the
        // native Settings control diagnostic; this regression checks identity.
    }
    for delta in [-0.125, 0.125] {
        let source = try MagnificationEvents.make(location: point, delta: delta, phase: .changed)
        let native = try require(NSEvent(cgEvent: try require(factory.make(source, target: target))))
        try expect(native.windowNumber == window.windowNumber && abs(native.magnification - delta) < 0.00001)
    }
}
