// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

private final class RoutingFixture {
    let a = InputWindow(id: 101, pid: 111, bounds: CGRect(x: -500, y: 100, width: 600, height: 400))
    let b = InputWindow(id: 102, pid: 222, bounds: CGRect(x: 0, y: 100, width: 600, height: 400))
    var visible: [InputWindow] = []
    var existing: [InputWindow] = []
    var activates: [CGWindowID] = []
    var delivered: [(CGEventType, InputWindow, Int64)] = []
    var delayed = false
    var work: (() -> Void)?
    lazy var router = WindowEventRouter(
        environment: WindowRoutingEnvironment(
            windows: { [unowned self] _ in visible },
            lookup: { [unowned self] target in existing.first { $0.id == target.id && $0.pid == target.pid } },
            activate: { [unowned self] target in
                activates.append(target.id)
                return delayed
            },
            makeEvent: { [unowned self] event, target in
                delivered.append((event.type, target, event.getIntegerValueField(.mouseEventClickState)))
                return event.copy()
            },
            deliver: { _, _ in },
            afterActivation: { [unowned self] in work = $0 }))
    init() {
        visible = [b, a]
        existing = visible
    }
    func send(_ type: CGEventType, _ point: CGPoint = CGPoint(x: -100, y: 200), clicks: Int64 = 1) throws {
        let event = try require(
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        router.post(event)
    }
    func scroll(_ phase: GesturePhase, at point: CGPoint) throws {
        let event = try require(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -3, wheel2: 2, wheel3: 0))
        event.location = point
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        router.post(event)
    }
}

func windowRoutingLocksDragsAndTracksMovedWindows() throws {
    let f = RoutingFixture()
    try f.send(.leftMouseDown)
    let moved = InputWindow(id: f.a.id, pid: f.a.pid, bounds: CGRect(x: -700, y: -300, width: 600, height: 400))
    f.existing = [f.b, moved]
    try f.send(.leftMouseDragged, CGPoint(x: 200, y: 200))
    try f.send(.leftMouseUp, CGPoint(x: 200, y: 200))
    try expect(f.delivered.map { $0.1.id } == [f.a.id, f.a.id, f.a.id])
    try expect(f.delivered[1].1.bounds == moved.bounds)
    try f.send(.mouseMoved, CGPoint(x: 200, y: 200))
    try expect(f.delivered.last?.1.id == f.b.id)
    try expect(f.activates == [f.a.id])
}

func windowRoutingDoesNotRetargetMissingOrReusedWindows() throws {
    let f = RoutingFixture()
    try f.send(.leftMouseDown)
    f.existing = [f.b, InputWindow(id: f.a.id, pid: 999, bounds: f.a.bounds)]
    try f.send(.leftMouseDragged, CGPoint(x: 200, y: 200))
    try f.send(.leftMouseUp, CGPoint(x: 200, y: 200))
    try expect(f.delivered.count == 1)
    try f.send(.leftMouseDown, CGPoint(x: 200, y: 200))
    try f.send(.leftMouseUp, CGPoint(x: 200, y: 200))
    try expect(f.delivered.suffix(2).allSatisfy { $0.1.id == f.b.id })
    f.visible = []
    try f.send(.leftMouseDown)
    f.visible = [f.b]
    try f.send(.leftMouseDragged, CGPoint(x: 200, y: 200))
    try f.send(.leftMouseUp, CGPoint(x: 200, y: 200))
    try expect(f.delivered.count == 3)
}

func windowRoutingLocksScrollAndRequiresNewBeginAfterCancel() throws {
    let f = RoutingFixture()
    try f.scroll(.began, at: CGPoint(x: -100, y: 200))
    try f.scroll(.changed, at: CGPoint(x: 200, y: 200))
    try f.scroll(.cancelled, at: CGPoint(x: 200, y: 200))
    try f.scroll(.changed, at: CGPoint(x: 200, y: 200))
    try f.scroll(.ended, at: CGPoint(x: 200, y: 200))
    try expect(f.delivered.count == 3 && f.delivered.allSatisfy { $0.1.id == f.a.id })
    try expect(f.activates.isEmpty)
    try f.scroll(.began, at: CGPoint(x: 200, y: 200))
    try expect(f.delivered.last?.1.id == f.b.id)
}

func windowRoutingActivationPreservesOrderAndRevalidates() throws {
    let f = RoutingFixture()
    f.delayed = true
    try f.send(.leftMouseDown)
    try f.send(.leftMouseDragged)
    try f.send(.leftMouseUp)
    try expect(f.delivered.isEmpty && f.activates.count == 1)
    f.work?()
    try expect(f.delivered.map { $0.0 } == [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    try f.send(.leftMouseDown)
    try f.send(.leftMouseUp)
    f.existing = [f.b]
    f.work?()
    try expect(f.delivered.count == 3)
}

func windowRoutingHitOrderClickCountsAndInvalidGeometry() throws {
    let f = RoutingFixture()
    try f.send(.leftMouseDown, CGPoint(x: 50, y: 200), clicks: 2)
    try f.send(.leftMouseUp, CGPoint(x: 50, y: 200), clicks: 2)
    try expect(f.delivered.first?.1.id == f.b.id && f.delivered.first?.2 == 1 && f.delivered[1].2 == 1)
    try f.send(.leftMouseDown, CGPoint(x: 50, y: 200), clicks: 2)
    try f.send(.leftMouseUp, CGPoint(x: 50, y: 200), clicks: 2)
    try expect(f.delivered[2].2 == 2)
    f.visible = [f.a]
    try f.send(.leftMouseDown, CGPoint(x: 50, y: 200), clicks: 3)
    try expect(f.delivered.last?.1.id == f.a.id && f.delivered.last?.2 == 1)
    try f.send(.leftMouseUp, CGPoint(x: 50, y: 200), clicks: 3)
    try f.send(.leftMouseDown, CGPoint(x: 50, y: 200), clicks: 3)
    try f.send(.leftMouseUp, CGPoint(x: 50, y: 200), clicks: 3)
    try expect(f.delivered.suffix(2).allSatisfy { $0.2 == 2 })
    try expect(f.a.localPoint(CGPoint(x: -400, y: 200)) == CGPoint(x: 100, y: 300))
    let invalid = InputWindow(id: 0, pid: 0, bounds: CGRect(x: 0, y: 0, width: 1, height: 1))
    try expect(!invalid.isValid)
}

func stationarySinkBypassesGlobalPointerPosting() throws {
    final class Router: PointerEventRouting {
        var events: [CGEvent] = []
        func post(_ event: CGEvent) { events.append(event) }
    }
    let router = Router()
    var global: [CGEvent] = []
    let sink = EventSink(
        target: ScreenTarget(id: 1, name: "Test"),
        geometry: DisplayGeometry(bounds: CGRect(x: -100, y: 200, width: 600, height: 400), rotation: 0),
        experimentalPinch: true, pointerRouter: router, postEvent: { global.append($0) })
    let point = Point(x: 50, y: 80)
    sink.emit(.click(point, right: false))
    sink.emit(.scroll(point, dx: 2.25, dy: -3.5, phase: .began))
    sink.emit(.magnify(point, delta: 0.02, phase: .began))
    try expect(global.isEmpty && router.events.count == 4)
    try expect(router.events[2].location == CGPoint(x: -50, y: 280))
    try expect(router.events[2].getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -3.5)
}

func windowRoutingLocksPinchAndIgnoresUnexpectedEventTypes() throws {
    let f = RoutingFixture()
    let phaseField = try require(CGEventField(rawValue: 132))
    let gestureType = try require(CGEventType(rawValue: 29))
    let e = try require(
        CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: -100, y: 200), mouseButton: .left))
    e.type = gestureType
    e.setIntegerValueField(phaseField, value: GesturePhase.began.rawValue)
    f.router.post(e)
    e.location = CGPoint(x: 200, y: 200)
    e.setIntegerValueField(phaseField, value: GesturePhase.changed.rawValue)
    f.router.post(e)
    e.setIntegerValueField(phaseField, value: GesturePhase.cancelled.rawValue)
    f.router.post(e)
    e.setIntegerValueField(phaseField, value: GesturePhase.ended.rawValue)
    f.router.post(e)
    try expect(f.delivered.count == 3 && f.delivered.allSatisfy { $0.1.id == f.a.id })
    e.type = .keyDown
    f.router.post(e)
    try expect(f.delivered.count == 3)
}

func windowRoutingSerializesQuickTouchesAcrossApplications() throws {
    let f = RoutingFixture()
    f.delayed = true
    try f.send(.leftMouseDown)
    try f.send(.leftMouseUp)
    try f.send(.leftMouseDown, CGPoint(x: 200, y: 200))
    try f.send(.leftMouseUp, CGPoint(x: 200, y: 200))
    try expect(f.delivered.isEmpty && f.activates == [f.a.id])
    f.work?()
    try expect(f.delivered.map { $0.1.id } == [f.a.id, f.a.id])
    try expect(f.activates == [f.a.id, f.b.id])
    f.work?()
    try expect(f.delivered.map { $0.1.id } == [f.a.id, f.a.id, f.b.id, f.b.id])
}

func windowRoutingCancelsQueuedInputWhenSessionIsReleased() throws {
    var scheduled: (() -> Void)?
    var delivered = 0
    let window = InputWindow(id: 1, pid: 2, bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    var router: WindowEventRouter? = WindowEventRouter(
        environment: WindowRoutingEnvironment(
            windows: { _ in [window] }, lookup: { _ in window }, activate: { _ in true },
            makeEvent: { e, _ in e.copy() }, deliver: { _, _ in delivered += 1 },
            afterActivation: { scheduled = $0 }))
    let event = try require(
        CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 20, y: 30), mouseButton: .left))
    router?.post(event)
    router = nil
    scheduled?()
    try expect(delivered == 0)
}
