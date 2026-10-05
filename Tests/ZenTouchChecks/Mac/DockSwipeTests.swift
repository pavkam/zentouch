// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

private func unsigned(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
    (0..<count).reduce(0) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
}
private func field(_ raw: UInt32) throws -> CGEventField { try require(CGEventField(rawValue: raw)) }

func swipeHIDPayloadHasPackedLayoutAndVelocityChild() throws {
    let began = DockSwipeEvents.hidPayload(
        axis: .vertical, progress: 0.5, velocity: 0,
        phase: .began, timestamp: 12345)
    try expect(began.count == 68 && unsigned(began, 0, 8) == 12345)
    try expect(unsigned(began, 24, 4) == 1 && unsigned(began, 28, 4) == 40)
    try expect(unsigned(began, 32, 4) == 23 && unsigned(began, 36, 4) == 0x0100_0000)
    try expect(unsigned(began, 60, 2) == 2 && unsigned(began, 62, 2) == 3)
    try expect(unsigned(began, 64, 4) == 32768)
    let ended = DockSwipeEvents.hidPayload(
        axis: .horizontal, progress: -1, velocity: -8,
        phase: .ended, timestamp: 23456)
    try expect(ended.count == 96 && unsigned(ended, 24, 4) == 2)
    try expect(unsigned(ended, 64, 4) == UInt64(UInt32(bitPattern: -65536)))
    try expect(unsigned(ended, 68, 4) == 28 && unsigned(ended, 72, 4) == 9)
    try expect(unsigned(ended, 80, 4) == 1)
    try expect(unsigned(ended, 84, 4) == UInt64(UInt32(bitPattern: -8 * 65536)))
    try expect(unsigned(ended, 88, 4) == 0)
    let zeroEnd = DockSwipeEvents.hidPayload(
        axis: .vertical, progress: 0, velocity: 0,
        phase: .ended, timestamp: 0)
    try expect(zeroEnd.count == 96)  // End needs a velocity record, even when stopped.
}

func dockSwipeEventsRoundTripBothCompatibilityPaths() throws {
    for raw in [false, true] {
        for axis in [SwipeAxis.horizontal, .vertical] {
            let events = try DockSwipeEvents.make(
                location: CGPoint(x: -500, y: 200), axis: axis,
                progress: 0.5, velocity: 99, phase: .ended, requiresHIDPayload: raw)
            try expect(events.count == 2)
            let event = events[0]
            try expect(event.getIntegerValueField(field(55)) == 30)
            try expect(events[1].getIntegerValueField(field(55)) == 29)
            try expect(event.location == CGPoint(x: -500, y: 200))
            try expect(event.getIntegerValueField(field(123)) == axis.rawValue)
            try expect(event.getIntegerValueField(field(132)) == 4)
            try expect(event.getIntegerValueField(field(134)) == 4)
            try expect(event.getDoubleValueField(field(124)) == -0.5)
            // CGEvent exposes this 32-bit field zero-extended; compare the wire bits.
            let bits = event.getIntegerValueField(try field(135))
            try expect(UInt32(truncatingIfNeeded: bits) == Float(-0.5).bitPattern)
            try expect(event.getDoubleValueField(field(axis == .horizontal ? 129 : 130)) == -8)
            if raw {
                let data = try require(event.data) as Data
                let payload = DockSwipeEvents.hidPayload(
                    axis: axis, progress: -0.5, velocity: -8,
                    phase: .ended, timestamp: event.timestamp)
                try expect(data.range(of: payload) != nil)
            }
        }
    }
}

func dockSwipeRejectsInvalidValuesAndUnknownSerialization() throws {
    try expectThrows(DockSwipeEvents.Failure.self) {
        try DockSwipeEvents.make(location: .zero, axis: .vertical, progress: .nan, velocity: 0, phase: .began)
    }
    let payload = DockSwipeEvents.hidPayload(axis: .vertical, progress: 0, velocity: 0, phase: .began, timestamp: 0)
    try expectThrows(DockSwipeEvents.Failure.self) {
        try DockSwipeEvents.appendingHIDPayload(payload, to: Data([0, 0, 0, 3]))
    }
    try expectThrows(DockSwipeEvents.Failure.self) {
        try DockSwipeEvents.appendingHIDPayload(Data(), to: Data([0, 0, 0, 2]))
    }
}

func swipePostsPairedSessionEventsAtMappedDisplayLocation() throws {
    var gestures: [CGEvent] = []
    var mouseEvents: [CGEvent] = []
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(bounds: CGRect(x: -1000, y: 200, width: 1000, height: 800), rotation: 0),
        experimentalPinch: false, postEvent: { mouseEvents.append($0) }, postGesture: { gestures.append($0) })
    sink.emit(.swipe(Point(x: 200, y: 300), axis: .horizontal, progress: -0.5, velocity: 0, phase: .changed))
    try expect(mouseEvents.isEmpty && gestures.count == 2)
    try expect(gestures[0].location == CGPoint(x: -800, y: 500))
    try expect(gestures[0].getDoubleValueField(field(124)) == 0.5)  // Finger coordinates are negated on the wire.
    try expect(gestures[0].getIntegerValueField(field(55)) == 30)
    try expect(gestures[1].getIntegerValueField(field(55)) == 29)
}

func verticalSwipeCommitsNativeDockActionsOnceOnLift() throws {
    var events: [CGEvent] = []
    var actions: [SystemGestureAction] = []
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), rotation: 0),
        experimentalPinch: false, postEvent: { events.append($0) }, postGesture: { events.append($0) },
        performSystemGesture: { actions.append($0) })
    for (progress, action) in [(-0.5, SystemGestureAction.missionControl), (0.5, .appExpose)] {
        sink.emit(.swipe(Point(x: 0, y: 0), axis: .vertical, progress: 0, velocity: 0, phase: .began))
        sink.emit(.swipe(Point(x: 0, y: 0), axis: .vertical, progress: progress, velocity: 0, phase: .changed))
        let beforeLift = actions.count
        sink.emit(.swipe(Point(x: 0, y: 0), axis: .vertical, progress: progress, velocity: 0, phase: .ended))
        sink.emit(.swipe(Point(x: 0, y: 0), axis: .vertical, progress: progress, velocity: 0, phase: .ended))
        try expect(actions.count == beforeLift + 1 && actions.last == action)
    }
    try expect(events.isEmpty)  // No competing partial DockControl transitions.
    try expect(DockActions.isAvailable)  // Resolves the ABI without invoking it in tests.
}

func verticalSwipeAbortShortTravelAndInvalidInputDoNotToggleDock() throws {
    for (first, last, phase) in [
        (-0.1, -0.1, GesturePhase.ended), (-0.5, -0.5, .cancelled),
        (-0.5, -0.3, .ended), (-0.5, Double.nan, .ended),
    ] {
        var commit = VerticalSwipeCommit()
        try expect(commit.process(progress: 0, phase: .began) == nil)
        try expect(commit.process(progress: first, phase: .changed) == nil)
        try expect(commit.process(progress: last, phase: phase) == nil)
        try expect(commit.process(progress: -1, phase: .ended) == nil)
    }
    var commit = VerticalSwipeCommit()
    try expect(commit.process(progress: -1, phase: .ended) == nil)
}
