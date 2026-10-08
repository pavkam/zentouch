// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

/// WindowServer coordinates use the top-left of the primary display as origin.
public struct InputWindow: Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let bounds: CGRect
    public init(id: CGWindowID, pid: pid_t, bounds: CGRect) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
    }
    public var isValid: Bool {
        id != 0 && pid > 0 && bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite && bounds.maxX.isFinite && bounds.maxY.isFinite
            && bounds.width > 0 && bounds.height > 0
    }
    public func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - bounds.minX, y: bounds.maxY - point.y)
    }
}

public protocol PointerEventRouting: AnyObject {
    func post(_ event: CGEvent)
}

/// Injected dependencies keep automated checks from sending input to real apps.
public struct WindowRoutingEnvironment {
    public var windows: (CGPoint) -> [InputWindow]
    public var lookup: (InputWindow) -> InputWindow?
    public var activate: (InputWindow) -> Bool
    public var makeEvent: (CGEvent, InputWindow) -> CGEvent?
    public var deliver: (CGEvent, pid_t) -> Void
    public var afterActivation: (@escaping () -> Void) -> Void
    public init(
        windows: @escaping (CGPoint) -> [InputWindow], lookup: @escaping (InputWindow) -> InputWindow?,
        activate: @escaping (InputWindow) -> Bool,
        makeEvent: @escaping (CGEvent, InputWindow) -> CGEvent?,
        deliver: @escaping (CGEvent, pid_t) -> Void,
        afterActivation: @escaping (@escaping () -> Void) -> Void
    ) {
        self.windows = windows
        self.lookup = lookup
        self.activate = activate
        self.makeEvent = makeEvent
        self.deliver = deliver
        self.afterActivation = afterActivation
    }
}

/// Experimental window-directed input. Never falls back to posting at the HID tap.
public final class WindowEventRouter: PointerEventRouting {
    private let environment: WindowRoutingEnvironment
    private var mouseHeld = false
    private var mouseWindow: InputWindow?
    private var heldClickCount: Int64 = 1
    private var scrollWindow: InputWindow?
    private var pinchWindow: InputWindow?
    private var lastClickWindow: InputWindow?
    private var awaitingActivation = false
    private var pending: [(CGEvent, InputWindow)] = []
    private var lastDrop: String?

    public convenience init() {
        let factory = WindowEventFactory()
        self.init(
            environment: WindowRoutingEnvironment(
                windows: WindowDiscovery.visible,
                lookup: WindowDiscovery.lookup,
                activate: WindowDiscovery.activate,
                makeEvent: factory.make,
                deliver: { $0.postToPid($1) },
                afterActivation: { work in DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work) }
            ))
    }
    public init(environment: WindowRoutingEnvironment) { self.environment = environment }

    public func post(_ event: CGEvent) {
        precondition(Thread.isMainThread)
        guard let event = event.copy() else { return }
        let target: InputWindow?
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            guard !mouseHeld else {
                drop("duplicateDown")
                return
            }
            mouseHeld = true
            mouseWindow = hit(event.location)
            target = mouseWindow
            if event.type == .rightMouseDown { lastClickWindow = nil }
            if event.type == .leftMouseDown, !same(lastClickWindow, target) {
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            heldClickCount = event.getIntegerValueField(.mouseEventClickState)
        case .leftMouseDragged, .rightMouseDragged:
            lastClickWindow = nil
            target = mouseHeld ? refreshed(mouseWindow) : nil
        case .leftMouseUp, .rightMouseUp:
            target = mouseHeld ? refreshed(mouseWindow) : nil
            event.setIntegerValueField(.mouseEventClickState, value: heldClickCount)
            if event.type == .leftMouseUp { lastClickWindow = target }
            mouseHeld = false
            mouseWindow = nil
        case .mouseMoved:
            target = mouseHeld ? refreshed(mouseWindow) : hit(event.location)
        case .scrollWheel:
            let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            if phase == GesturePhase.began.rawValue { scrollWindow = hit(event.location) }
            target = refreshed(scrollWindow)
            if phase == GesturePhase.ended.rawValue || phase == GesturePhase.cancelled.rawValue {
                scrollWindow = nil
            }
        default:
            // System swipes bypass this router. Only the opt-in pinch ABI is accepted.
            guard event.type.rawValue == 29, let field = CGEventField(rawValue: 132) else {
                drop("unsupportedEvent")
                return
            }
            let phase = event.getIntegerValueField(field)
            if phase == GesturePhase.began.rawValue { pinchWindow = hit(event.location) }
            target = refreshed(pinchWindow)
            if phase == GesturePhase.ended.rawValue || phase == GesturePhase.cancelled.rawValue {
                pinchWindow = nil
            }
        }
        guard let target else {
            drop("noWindow")
            return
        }
        lastDrop = nil
        pending.append((event, target))
        drain()
    }

    private func same(_ a: InputWindow?, _ b: InputWindow?) -> Bool {
        guard let a, let b else { return false }
        return a.id == b.id && a.pid == b.pid
    }
    private func hit(_ point: CGPoint) -> InputWindow? {
        guard point.x.isFinite && point.y.isFinite else { return nil }
        return environment.windows(point).first { $0.isValid && $0.bounds.contains(point) }
    }
    private func refreshed(_ window: InputWindow?) -> InputWindow? {
        guard let window, let current = environment.lookup(window), current.isValid,
            same(current, window)
        else { return nil }
        return current
    }
    private func deliver(_ event: CGEvent, _ window: InputWindow) {
        guard let current = refreshed(window), let routed = environment.makeEvent(event, current) else {
            drop("windowUnavailable")
            return
        }
        environment.deliver(routed, current.pid)
        diagnostics.record(
            "input.window.post",
            [
                "type": routed.type.rawValue, "window": current.id, "pid": current.pid,
                "x": routed.location.x, "y": routed.location.y,
            ])
    }
    private func drain() {
        guard !awaitingActivation else { return }
        while let (event, target) = pending.first {
            guard let current = refreshed(target) else {
                pending.removeFirst()
                drop("windowUnavailable")
                continue
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown, environment.activate(current) {
                awaitingActivation = true
                environment.afterActivation { [weak self] in self?.finishActivation() }
                return
            }
            pending.removeFirst()
            deliver(event, current)
        }
    }
    private func finishActivation() {
        awaitingActivation = false
        if !pending.isEmpty {
            let (event, target) = pending.removeFirst()
            deliver(event, target)
        }
        drain()
    }
    private func drop(_ reason: String) {
        guard lastDrop != reason else { return }
        lastDrop = reason
        diagnostics.record("input.window.drop", ["reason": reason])
    }
}
