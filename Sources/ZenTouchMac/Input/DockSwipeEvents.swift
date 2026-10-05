// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-FileCopyrightText: 2026 joshuarli
// SPDX-FileCopyrightText: 2026 Scott Lamb
// SPDX-License-Identifier: MIT AND ISC

import AppKit
import ZenTouchCore

/// Isolated private DockSwipe ABI. Field mapping follows macos-trackpad-companion;
/// the macOS 27 raw IOHID envelope is adapted from iss. See THIRD-PARTY-NOTICES.md.
/// This generates native phased Dock gestures, rather than keyboard shortcuts.
public enum DockSwipeEvents {
    public enum Failure: Error { case invalidValue, unavailable, unsupportedSerialization }

    public static func make(
        location: CGPoint, axis: SwipeAxis, progress: Double, velocity: Double, phase: GesturePhase,
        requiresHIDPayload: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    ) throws -> [CGEvent] {
        guard progress.isFinite, velocity.isFinite, location.x.isFinite, location.y.isFinite else {
            throw Failure.invalidValue
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
            let event = CGEvent(source: source), let companion = CGEvent(source: source)
        else { throw Failure.unavailable }
        // Finger coordinates have the opposite sign to the Dock's origin offset.
        let offset = -max(-1, min(1, progress))
        let speed = phase == .ended ? -max(-8, min(8, velocity)) : 0
        event.location = location
        event.flags = []
        try integer(event, 55, 30)  // DockControl
        try integer(event, 110, 23)  // FluidTouchGesture / DockSwipe
        try integer(event, 123, axis.rawValue)
        try integer(event, 132, phase.rawValue)
        try integer(event, 134, phase.rawValue)
        try integer(event, 135, Int64(Int32(bitPattern: Float(offset).bitPattern)))
        try double(event, 124, offset)
        try double(event, 125, 0.1)
        try double(event, 138, 3)
        try double(event, 169, Double(mach_absolute_time()))
        try double(event, 129, axis == .horizontal ? speed : 0)
        try double(event, 130, axis == .vertical ? speed : 0)
        try integer(companion, 55, 29)  // Companion Gesture flushes the Dock update.
        companion.location = location
        if requiresHIDPayload {
            guard let original = event.data else { throw Failure.unavailable }
            let payload = hidPayload(
                axis: axis, progress: offset, velocity: speed, phase: phase,
                timestamp: event.timestamp)
            let data = try appendingHIDPayload(payload, to: original as Data)
            guard let augmented = CGEvent(withDataAllocator: nil, data: data as CFData) else {
                throw Failure.unsupportedSerialization
            }
            return [augmented, companion]
        }
        return [event, companion]
    }

    /// Byte layout is explicit, independent of Swift struct alignment.
    /// The queue and nested HID records are little-endian; CG field headers are big-endian.
    public static func hidPayload(
        axis: SwipeAxis, progress: Double, velocity: Double, phase: GesturePhase, timestamp: UInt64
    ) -> Data {
        let includeVelocity = phase == .ended || velocity != 0
        var data = Data()
        data.le(timestamp)
        data.le(UInt64(0))  // sender ID
        data.le(UInt32(0))  // options
        data.le(UInt32(0))  // attribute length
        data.le(UInt32(includeVelocity ? 2 : 1))
        data.le(UInt32(40))
        data.le(UInt32(23))
        data.le(UInt32(phase.rawValue) << 24)
        data.le(UInt32(0))  // depth and padding
        data.le(fixed(0.1))
        data.le(Int32(0))  // position Y
        data.le(Int32(0))  // position Z
        data.le(UInt32(0))  // swipe mask
        data.le(UInt16(axis.rawValue))
        data.le(UInt16(3))  // DockPrimary flavor
        data.le(fixed(progress))
        if includeVelocity {
            data.le(UInt32(28))
            data.le(UInt32(9))
            data.le(UInt32(0))
            data.le(UInt32(1))  // child depth = 1
            data.le(fixed(axis == .horizontal ? velocity : 0))
            data.le(fixed(axis == .vertical ? velocity : 0))
            data.le(Int32(0))
        }
        return data
    }

    public static func appendingHIDPayload(_ payload: Data, to original: Data) throws -> Data {
        guard original.starts(with: [0, 0, 0, 2]), payload.count == 68 || payload.count == 96 else {
            throw Failure.unsupportedSerialization
        }
        var data = original
        var length = UInt16(payload.count).bigEndian
        var field = UInt16(4205).bigEndian
        Swift.withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        Swift.withUnsafeBytes(of: &field) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private static func fixed(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let result = Int32(max(Double(Int32.min), min(Double(Int32.max), (value * 65536).rounded(.towardZero))))
        return result == 0 && value != 0 ? (value > 0 ? 1 : -1) : result
    }
    private static func integer(_ event: CGEvent, _ field: UInt32, _ value: Int64) throws {
        guard let field = CGEventField(rawValue: field) else { throw Failure.unavailable }
        event.setIntegerValueField(field, value: value)
    }
    private static func double(_ event: CGEvent, _ field: UInt32, _ value: Double) throws {
        guard let field = CGEventField(rawValue: field) else { throw Failure.unavailable }
        event.setDoubleValueField(field, value: value)
    }
}

extension Data {
    fileprivate mutating func le<T: FixedWidthInteger>(_ value: T) {
        var encoded = value.littleEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
