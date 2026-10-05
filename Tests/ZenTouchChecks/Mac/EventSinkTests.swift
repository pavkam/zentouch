// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

func eventCoordinatesRespectDisplayOriginAndEdges() throws {
    var events: [CGEvent] = []
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(
            bounds: CGRect(x: -1000, y: 200, width: 1000, height: 800), rotation: 0),
        experimentalPinch: false, postEvent: { events.append($0) })
    sink.emit(.move(Point(x: 1000, y: 800)))
    try expect(events.count == 1 && events[0].location == CGPoint(x: -1, y: 999))
    sink.emit(.move(Point(x: -10, y: -20)))
    try expect(events[1].location == CGPoint(x: -1000, y: 200))
}

func clickCountsDoNotLeakAcrossRightClickAndDrag() throws {
    var events: [CGEvent] = []
    var now = 10.0
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), rotation: 0),
        experimentalPinch: false, now: { now }, clickInterval: 0.5, postEvent: { events.append($0) })
    let p = Point(x: 200, y: 200)
    sink.emit(.click(p, right: false))
    now += 0.1
    sink.emit(.click(p, right: false))
    try expect(events[2].getIntegerValueField(.mouseEventClickState) == 2)
    sink.emit(.click(p, right: true))
    now += 0.1
    sink.emit(.click(p, right: false))
    try expect(events[6].getIntegerValueField(.mouseEventClickState) == 1)
    sink.emit(.down(p))
    sink.emit(.up(p))
    now += 0.1
    sink.emit(.click(p, right: false))
    try expect(events.last?.getIntegerValueField(.mouseEventClickState) == 1)
}

func scrollEventsRetainPhaseAndFractionalDeltas() throws {
    var events: [CGEvent] = []
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), rotation: 0),
        experimentalPinch: false, postEvent: { events.append($0) })
    sink.emit(.scroll(Point(x: 100, y: 200), dx: 2.25, dy: -3.5, phase: .changed))
    let event = try require(events.first)
    try expect(event.type == .scrollWheel && event.location == CGPoint(x: 100, y: 200))
    try expect(event.getIntegerValueField(.scrollWheelEventScrollPhase) == GesturePhase.changed.rawValue)
    try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -4)
    try expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 2)
    try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -3.5)
    try expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 2.25)
    sink.emit(.scroll(Point(x: 100, y: 200), dx: Double(Int32.max) * 2, dy: 0, phase: .ended))
    try expect(events.count == 2)
    try expect(events[1].getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == Int64(Int32.max))
    try expect(events[1].getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == Double(Int32.max) / 65536)
}
