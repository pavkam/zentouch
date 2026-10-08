// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit

/// NSEvent embeds window-local coordinates that CGEvent.location alone cannot set.
/// A hidden borderless window supplies those coordinates for a foreign window.
public final class WindowEventFactory {
    private var template: NSWindow?
    public init() {}
    deinit { template?.close() }
    public func make(_ source: CGEvent, target: InputWindow) -> CGEvent? {
        precondition(Thread.isMainThread)
        guard target.isValid, source.location.x.isFinite, source.location.y.isFinite else { return nil }
        let height = CGDisplayBounds(CGMainDisplayID()).height
        let frame = CGRect(
            x: target.bounds.minX, y: height - target.bounds.maxY,
            width: target.bounds.width, height: target.bounds.height)
        if template == nil {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true
            window.isExcludedFromWindowsMenu = true
            template = window
        }
        guard let template else { return nil }
        template.setFrame(frame, display: false)
        let nsType: NSEvent.EventType
        switch source.type {
        case .leftMouseDown: nsType = .leftMouseDown
        case .leftMouseUp: nsType = .leftMouseUp
        case .leftMouseDragged: nsType = .leftMouseDragged
        case .rightMouseDown: nsType = .rightMouseDown
        case .rightMouseUp: nsType = .rightMouseUp
        case .rightMouseDragged: nsType = .rightMouseDragged
        default: nsType = .mouseMoved
        }
        guard
            let event = NSEvent.mouseEvent(
                with: nsType, location: target.localPoint(source.location),
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(source.flags.rawValue)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: template.windowNumber,
                context: nil, eventNumber: 1,
                clickCount: Int(source.getIntegerValueField(.mouseEventClickState)),
                pressure: nsType == .leftMouseUp || nsType == .rightMouseUp ? 0 : 1)?.cgEvent,
            let windowField = CGEventField(rawValue: 51)
        else { return nil }
        event.type = source.type
        event.flags = source.flags
        event.timestamp = source.timestamp
        event.setIntegerValueField(windowField, value: Int64(target.id))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.id))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.id))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(target.pid))
        event.setIntegerValueField(.eventSourceUserData, value: source.getIntegerValueField(.eventSourceUserData))
        if source.type == .scrollWheel {
            for field: CGEventField in [
                .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
                .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
            ] {
                event.setIntegerValueField(field, value: source.getIntegerValueField(field))
            }
            for field: CGEventField in [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
                event.setDoubleValueField(field, value: source.getDoubleValueField(field))
            }
        } else if source.type.rawValue == 29 {
            for raw: UInt32 in [50, 101, 110, 132] {
                if let field = CGEventField(rawValue: raw) {
                    event.setIntegerValueField(field, value: source.getIntegerValueField(field))
                }
            }
            for raw: UInt32 in [113, 114, 116, 118] {
                if let field = CGEventField(rawValue: raw) {
                    event.setDoubleValueField(field, value: source.getDoubleValueField(field))
                }
            }
        }
        return event
    }
}
