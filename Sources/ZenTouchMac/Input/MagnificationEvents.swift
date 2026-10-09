// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-FileCopyrightText: 2024 Sebastian Hueber
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

/// The isolated CG gesture ABI converts to AppKit's native magnify event.
/// See the Touch-Up attribution in THIRD-PARTY-NOTICES.md.
public enum MagnificationEvents {
    public enum Failure: Error { case invalidValue, unavailable }

    public static func make(location: CGPoint, delta: Double, phase: GesturePhase) throws -> CGEvent {
        guard location.x.isFinite, location.y.isFinite, delta.isFinite,
            abs(delta) <= 0.25
        else { throw Failure.invalidValue }
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: location, mouseButton: .left),
            let type = CGEventType(rawValue: 29)
        else { throw Failure.unavailable }
        event.type = type
        event.flags = []
        for (raw, value): (UInt32, Int64) in [(50, 248), (101, 4), (110, 8), (132, phase.rawValue)] {
            guard let field = CGEventField(rawValue: raw) else { throw Failure.unavailable }
            event.setIntegerValueField(field, value: value)
        }
        for raw: UInt32 in [113, 114, 116, 118] {
            guard let field = CGEventField(rawValue: raw) else { throw Failure.unavailable }
            event.setDoubleValueField(field, value: phase == .changed ? delta : 0)
        }
        return event
    }
}
