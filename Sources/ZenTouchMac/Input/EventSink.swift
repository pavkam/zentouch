// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-FileCopyrightText: 2024 Sebastian Hueber
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

public protocol EventPosting: AnyObject {
    func emit(_ action: InputAction)
}

public final class EventSink: EventPosting {
    let target: ScreenTarget
    let experimentalPinch: Bool
    private let bounds: CGRect
    private let postEvent: (CGEvent) -> Void
    private let postGesture: (CGEvent) -> Void
    private let now: () -> TimeInterval
    private let clickInterval: TimeInterval
    private var lastClick: (time: TimeInterval, point: Point)?
    private var clickCount: Int64 = 0
    public init(
        target: ScreenTarget, geometry: DisplayGeometry, experimentalPinch: Bool,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        clickInterval: TimeInterval? = nil,
        postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        postGesture: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.target = target
        self.experimentalPinch = experimentalPinch
        self.bounds = geometry.bounds
        self.now = now
        self.clickInterval = clickInterval ?? NSEvent.doubleClickInterval
        self.postEvent = postEvent
        self.postGesture = postGesture
    }

    public func emit(_ action: InputAction) {
        diagnostics.record(
            "input.action", ["action": String(describing: action), "displayID": target.id, "target": target.name])
        switch action {
        case .move(let p): mouse(.mouseMoved, p)
        case .down(let p):
            lastClick = nil
            mouse(.leftMouseDown, p, clicks: 1)
        case .drag(let p): mouse(.leftMouseDragged, p, clicks: 1)
        case .up(let p): mouse(.leftMouseUp, p, clicks: 1)
        case .click(let p, let right):
            let now = now()
            if !right, let lastClick, now - lastClick.time < clickInterval,
                hypot(p.x - lastClick.point.x, p.y - lastClick.point.y) < 8
            {
                clickCount = min(clickCount + 1, 3)
            } else {
                clickCount = 1
            }
            lastClick = right ? nil : (now, p)
            mouse(right ? .rightMouseDown : .leftMouseDown, p, clicks: clickCount)
            mouse(right ? .rightMouseUp : .leftMouseUp, p, clicks: clickCount)
        case .scroll(let p, let dx, let dy, let phase):
            guard
                let event = CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: wheelDelta(dy), wheel2: wheelDelta(dx), wheel3: 0)
            else { return }
            event.location = global(p)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            // Pixel fields are integers; the 16.16 fields retain fractional movement.
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(wheelDelta(dy)))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(wheelDelta(dx)))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedDelta(dy))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedDelta(dx))
            post(event)
        case .swipe(let p, let axis, let progress, let velocity, let phase):
            do {
                let events = try DockSwipeEvents.make(
                    location: global(p), axis: axis,
                    progress: progress, velocity: velocity, phase: phase)
                for event in events { postGesture(event) }
                diagnostics.record(
                    "input.swipe.post",
                    [
                        "axis": axis.rawValue,
                        "phase": phase.rawValue, "progress": progress, "velocity": velocity,
                        "rawHID": ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
                    ])
            } catch {
                diagnostics.record("input.swipe.error", ["error": String(describing: error)])
            }
        case .magnify(let p, let delta, let phase):
            guard experimentalPinch,
                let event = CGEvent(
                    mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: global(p), mouseButton: .left)
            else { return }
            // Undocumented CGEvent ABI used by Touch-Up. This simple adapter may
            // work with NSResponder.magnify but fail with gesture recognizers.
            // Kept opt-in until tested against this macOS build and target apps.
            guard let gestureType = CGEventType(rawValue: 29),
                let subtype = CGEventField(rawValue: 50), let direction = CGEventField(rawValue: 101),
                let kind = CGEventField(rawValue: 110), let phaseField = CGEventField(rawValue: 132)
            else {
                diagnostics.record("input.pinch.unsupported")
                return
            }
            let deltaFields = [113, 114, 116, 118].compactMap { CGEventField(rawValue: UInt32($0)) }
            guard deltaFields.count == 4 else {
                diagnostics.record("input.pinch.unsupported")
                return
            }
            event.type = gestureType
            event.flags = []
            for field in deltaFields {
                event.setDoubleValueField(field, value: delta)
            }
            event.setIntegerValueField(subtype, value: 248)
            event.setIntegerValueField(direction, value: 4)
            event.setIntegerValueField(kind, value: 8)
            event.setIntegerValueField(phaseField, value: phase.rawValue)
            post(event)
        }
    }

    private func global(_ p: Point) -> CGPoint {
        CGPoint(
            x: bounds.minX + min(max(p.x, 0), bounds.width - 1),
            y: bounds.minY + min(max(p.y, 0), bounds.height - 1))
    }
    private func wheelDelta(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(min(Double(Int32.max), max(Double(Int32.min), value.rounded())))
    }
    private func fixedDelta(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(Double(Int32.max) / 65536, max(Double(Int32.min) / 65536, value))
    }
    private func mouse(_ type: CGEventType, _ point: Point, clicks: Int64 = 0) {
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: global(point),
                mouseButton: type == .rightMouseDown || type == .rightMouseUp ? .right : .left)
        else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        post(event)
    }

    private func post(_ event: CGEvent) {
        diagnostics.record(
            "input.post",
            [
                "type": event.type.rawValue,
                "x": event.location.x, "y": event.location.y, "flags": event.flags.rawValue,
            ])
        postEvent(event)
    }
}
