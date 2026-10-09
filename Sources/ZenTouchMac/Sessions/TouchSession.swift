// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

public enum SessionKind: String, Equatable { case contacts, input }
public enum SessionState: Equatable {
    case stopped
    case running(SessionKind)
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// The closures let lifecycle checks run without hardware or posting real input.
public struct SessionEnvironment {
    public var permissions: () -> PermissionState
    public var geometry: (ScreenTarget) -> DisplayGeometry?
    public var now: () -> TimeInterval
    public init(
        permissions: @escaping () -> PermissionState = { .current },
        geometry: @escaping (ScreenTarget) -> DisplayGeometry? = { $0.geometry },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.permissions = permissions
        self.geometry = geometry
        self.now = now
    }
}

public final class TouchSession {
    public let reader: TouchReading
    public private(set) var state: SessionState = .stopped
    public var onFrame: ((TouchFrame) -> Void)?
    public var onReport: ((ReportStatistics) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onState: ((SessionState) -> Void)?
    private var engine: GestureEngine?
    private var sink: EventPosting?
    private var target: ScreenTarget?
    private var initialGeometry: DisplayGeometry?
    private var timer: Timer?
    private var lastFrameAt = 0.0
    private var lastHeartbeatAt = 0.0
    private let environment: SessionEnvironment
    private let automaticPolling: Bool
    private let makeSink: (ScreenTarget, DisplayGeometry, Bool) -> EventPosting

    public init(
        reader: TouchReading = HIDReader(), environment: SessionEnvironment = SessionEnvironment(),
        automaticPolling: Bool = true,
        makeSink: ((ScreenTarget, DisplayGeometry, Bool) -> EventPosting)? = nil
    ) {
        self.reader = reader
        self.environment = environment
        self.automaticPolling = automaticPolling
        self.makeSink = makeSink ?? { EventSink(target: $0, geometry: $1, experimentalPinch: $2) }
    }

    public func start(
        kind: SessionKind, target: ScreenTarget?, pinch: Bool = false, multitouch: Bool = true,
        swipes: Bool = true, options: GestureOptions? = nil
    ) throws {
        precondition(Thread.isMainThread)
        guard !state.isRunning else {
            throw ZenError(message: "Touch input is already running. Stop it before starting another session.")
        }
        let gestureOptions =
            options
            ?? GestureOptions(
                pinch: pinch, desktops: swipes, missionControl: swipes, appExpose: swipes)
        let permissions = environment.permissions()
        guard permissions.inputMonitoring else {
            throw ZenError(message: "Allow ZenTouch Input Monitoring, then quit and reopen it.")
        }
        diagnostics.record(
            "session.start",
            [
                "kind": kind.rawValue, "pinch": gestureOptions.pinch, "multitouch": multitouch,
                "swipes": gestureOptions.hasThreeFingerGesture,
                "gestures": GestureFeature.allCases.filter { gestureOptions[$0] }.map(\.rawValue),
                "target": target?.name ?? "none", "displayID": target?.id ?? 0,
            ])
        if kind == .input {
            guard ModelCatalog.current != nil else {
                throw ZenError(message: "ZenTouch's model catalog is missing or invalid. Reinstall the app.")
            }
            guard permissions.canBridge else {
                throw ZenError(message: "Allow ZenTouch Accessibility, then reopen it to enable input.")
            }
            guard let target, let geometry = environment.geometry(target) else {
                throw ZenError(message: "Select a connected ZenScreen display first.")
            }
            guard geometry.supported else {
                throw ZenError(message: "Set the ZenScreen to landscape with 0° rotation before enabling input.")
            }
            self.target = target
            initialGeometry = geometry
            sink = makeSink(target, geometry, gestureOptions.pinch)
            sink?.updateOptions(gestureOptions)
            engine = GestureEngine(
                width: geometry.bounds.width, height: geometry.bounds.height,
                options: gestureOptions)
        }
        reader.onMultitouchObserved = { [weak self] in
            self?.onStatus?(
                kind == .input
                    ? "Multi-touch input is active." : "Multi-touch confirmed. The dots show your finger contacts.")
        }
        reader.onReport = { [weak self] counts in self?.onReport?(counts) }
        reader.onFrame = { [weak self] frame in
            guard let self, self.state.isRunning else { return }
            // Check before posting, rather than waiting for the next timer tick.
            guard self.validateEnvironment() else { return }
            self.lastFrameAt = self.environment.now()
            if var engine = self.engine {
                let actions = engine.process(frame.touches, time: self.lastFrameAt)
                self.engine = engine
                for action in actions { self.sink?.emit(action) }
            }
            self.onFrame?(frame)
        }
        reader.onError = { [weak self] message in
            guard let self else { return }
            diagnostics.record("session.error", ["message": message])
            self.cancelGestures(suppressUntilLift: true)
            self.onStatus?(message)
        }
        reader.onDisconnect = { [weak self] in
            self?.stop(reason: "Touch controller disconnected. Waiting for it to return.")
        }
        do { try reader.start(seize: kind == .input, multitouch: multitouch) } catch {
            _ = reader.stop()
            clearCallbacks()
            sink = nil
            engine = nil
            self.target = nil
            initialGeometry = nil
            diagnostics.record("session.start.error", ["error": error.localizedDescription])
            throw error
        }
        state = .running(kind)
        onState?(state)
        lastFrameAt = environment.now()
        lastHeartbeatAt = lastFrameAt
        if automaticPolling {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    public func updateGestureOptions(_ options: GestureOptions) {
        precondition(Thread.isMainThread)
        guard var engine, engine.options != options else { return }
        let actions = engine.updateOptions(options)
        self.engine = engine
        // Cancel the old pinch while the sink still permits its terminal event.
        for action in actions { sink?.emit(action) }
        sink?.updateOptions(options)
        diagnostics.record(
            "session.gestures.changed", ["enabled": GestureFeature.allCases.filter { options[$0] }.map(\.rawValue)])
    }

    public func poll() {
        guard state.isRunning, validateEnvironment() else { return }
        guard reader.isConnected else {
            stop(reason: "Touch controller unavailable. Waiting for it to return.")
            return
        }
        let now = environment.now()
        if now - lastHeartbeatAt >= 5 {
            lastHeartbeatAt = now
            diagnostics.record(
                "session.heartbeat",
                [
                    "counts": reader.statistics.fields,
                    "secondsSinceFrame": now - lastFrameAt, "kind": String(describing: state),
                ])
        }
        if engine?.hasActiveGesture == true, now - lastFrameAt > 2 {
            diagnostics.record("session.gesture.timeout")
            cancelGestures(suppressUntilLift: true)
        }
    }

    @discardableResult private func validateEnvironment() -> Bool {
        let permissions = environment.permissions()
        guard permissions.inputMonitoring else {
            stop(reason: "Input stopped: Input Monitoring is no longer allowed.")
            return false
        }
        if case .running(.input) = state {
            guard permissions.canBridge else {
                stop(reason: "Input stopped: Accessibility is no longer allowed.")
                return false
            }
            guard let target, environment.geometry(target) == initialGeometry else {
                stop(
                    reason:
                        "Input stopped: the display configuration changed. Check the selected screen and enable input again."
                )
                return false
            }
        }
        return true
    }

    private func cancelGestures(suppressUntilLift: Bool = false) {
        guard var engine else { return }
        let actions = suppressUntilLift ? engine.cancelUntilLift() : engine.cancel()
        self.engine = engine
        if !actions.isEmpty {
            diagnostics.record("session.gestures.cancel", ["actions": actions.map { String(describing: $0) }])
        }
        for action in actions { sink?.emit(action) }
    }

    public func stop(reason: String = "Stopped. The controller's previous mode was requested.") {
        precondition(Thread.isMainThread)
        guard state.isRunning else { return }
        diagnostics.record("session.stop", ["reason": reason])
        timer?.invalidate()
        timer = nil
        cancelGestures()
        let restoreError = reader.stop()
        clearCallbacks()
        sink = nil
        engine = nil
        target = nil
        initialGeometry = nil
        state = .stopped
        onState?(state)
        onFrame?(TouchFrame(scanTime: 0, touches: []))
        onStatus?(restoreError ?? reason)
    }

    private func clearCallbacks() {
        reader.onFrame = nil
        reader.onReport = nil
        reader.onError = nil
        reader.onDisconnect = nil
        reader.onMultitouchObserved = nil
    }

    deinit { stop(reason: "Touch session closed.") }
}
