// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

private final class FakeReader: TouchReading {
    var onFrame: ((TouchFrame) -> Void)?
    var onReport: ((ReportStatistics) -> Void)?
    var onDisconnect: (() -> Void)?
    var onError: ((String) -> Void)?
    var onMultitouchObserved: (() -> Void)?
    var statistics = ReportStatistics()
    var modeWarning: String?
    var starts = 0, stops = 0
    var startError: Error?
    var restoreError: String?
    func start(seize: Bool, multitouch: Bool) throws {
        starts += 1
        if let startError { throw startError }
    }
    func stop() -> String? {
        stops += 1
        return restoreError
    }
    func send(_ touches: [Touch]) { onFrame?(TouchFrame(scanTime: 0, touches: touches)) }
}
private final class FakeSink: EventPosting {
    var actions: [InputAction] = []
    func emit(_ action: InputAction) { actions.append(action) }
}
private final class Fixture {
    var now = 0.0
    var permissions = PermissionState(inputMonitoring: true, accessibility: true, eventPosting: true)
    var geometry: DisplayGeometry? = DisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), rotation: 0)
    let reader = FakeReader(), sink = FakeSink()
    let target = ScreenTarget(id: 1, name: "Test ZenScreen")
    lazy var session = TouchSession(
        reader: reader,
        environment: SessionEnvironment(
            permissions: { [unowned self] in self.permissions }, geometry: { [unowned self] _ in self.geometry },
            now: { [unowned self] in self.now }), automaticPolling: false,
        makeSink: { [unowned self] _, _, _ in self.sink })
    func start() throws { try session.start(kind: .input, target: target) }
    func beginDrag() {
        reader.send([Touch(id: 0, x: 0.2, y: 0.2)])
        now = 0.1
        reader.send([Touch(id: 0, x: 0.3, y: 0.2)])
    }
    deinit { session.stop() }
}

func sessionPermissionsAreCheckedBeforeOpening() throws {
    let f = Fixture()
    f.permissions = PermissionState(inputMonitoring: false, accessibility: true, eventPosting: true)
    try expectThrows(ZenError.self) { try f.start() }
    f.permissions = PermissionState(inputMonitoring: true, accessibility: true, eventPosting: false)
    try expectThrows(ZenError.self) { try f.start() }
    try expect(f.reader.starts == 0 && f.session.state == .stopped && f.sink.actions.isEmpty)
    // Diagnostic capture requires no Accessibility permission.
    try f.session.start(kind: .contacts, target: nil)
    try expect(f.reader.starts == 1)
}

func sessionRejectsUnsupportedGeometry() throws {
    let f = Fixture()
    f.geometry = DisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), rotation: 90)
    try expectThrows(ZenError.self) { try f.start() }
    f.geometry = nil
    try expectThrows(ZenError.self) { try f.start() }
    try expect(f.reader.starts == 0)
}

func duplicateStartPreservesActiveDrag() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    try expectThrows(ZenError.self) { try f.start() }
    try expect(f.reader.starts == 1 && f.session.state == .running(.input))
    f.session.stop()
    try expect(f.sink.actions.last == .up(Point(x: 300, y: 200)))
}

func failedStartClearsReaderAndCallbacks() throws {
    let f = Fixture()
    f.reader.startError = ZenError(message: "Simulated device busy")
    try expectThrows(ZenError.self) { try f.start() }
    try expect(f.reader.stops == 1 && f.session.state == .stopped)
    f.reader.send([Touch(id: 0, x: 0.5, y: 0.5)])
    try expect(f.sink.actions.isEmpty && f.reader.onFrame == nil)
}

func sessionStopIsIdempotentAndReleasesDrag() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    f.session.stop()
    f.session.stop()
    try expect(f.reader.stops == 1)
    let releases = f.sink.actions.filter {
        if case .up = $0 { return true }
        return false
    }
    try expect(releases.count == 1)
    let count = f.sink.actions.count
    f.reader.send([])
    try expect(f.sink.actions.count == count && f.session.state == .stopped)
}

func revokedPermissionsStopBeforeNewInput() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    f.permissions = PermissionState(inputMonitoring: true, accessibility: false, eventPosting: false)
    f.reader.send([Touch(id: 0, x: 0.8, y: 0.2)])
    try expect(f.session.state == .stopped && f.reader.stops == 1)
    try expect(f.sink.actions.last == .up(Point(x: 300, y: 200)))
}

func displayChangesStopBeforeNewInput() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    f.geometry = DisplayGeometry(bounds: CGRect(x: 1000, y: 0, width: 1000, height: 1000), rotation: 0)
    f.reader.send([Touch(id: 0, x: 0.8, y: 0.2)])
    try expect(f.session.state == .stopped && f.reader.stops == 1)
    try expect(f.sink.actions.last == .up(Point(x: 300, y: 200)))
}

func stalledGestureCannotBecomeAnotherClick() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    f.now = 3
    f.session.poll()
    let afterCancel = f.sink.actions.count
    f.reader.send([Touch(id: 0, x: 0.6, y: 0.2)])
    f.reader.send([])
    try expect(f.sink.actions.count == afterCancel)
    f.now = 4
    f.reader.send([Touch(id: 0, x: 0.4, y: 0.4)])
    f.now = 4.1
    f.reader.send([])
    try expect(f.sink.actions.last == .click(Point(x: 400, y: 400), right: false))
}

func idleTimeoutDoesNotSuppressFirstTouch() throws {
    let f = Fixture()
    try f.start()
    f.now = 10
    f.session.poll()
    f.reader.send([Touch(id: 0, x: 0.4, y: 0.4)])
    f.now = 10.1
    f.reader.send([])
    try expect(f.sink.actions.last == .click(Point(x: 400, y: 400), right: false))
}

func decodeErrorReleasesAndSuppressesResidualContacts() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    f.reader.onError?("Malformed packet")
    let count = f.sink.actions.count
    f.reader.send([Touch(id: 0, x: 0.6, y: 0.2)])
    f.reader.send([])
    try expect(f.sink.actions.count == count)
    try expect(f.sink.actions.last == .up(Point(x: 300, y: 200)))
}

func disconnectKeepsRestoreFailureVisible() throws {
    let f = Fixture()
    try f.start()
    f.beginDrag()
    var status = ""
    f.session.onStatus = { status = $0 }
    f.reader.restoreError = "Mode restoration failed"
    f.reader.onDisconnect?()
    try expect(f.session.state == .stopped && status == "Mode restoration failed")
}

func sessionFailuresCancelNativeSwipeExactlyOnce() throws {
    for reason in 0..<3 {
        let f = Fixture()
        try f.start()
        let touches = (1...3).map { Touch(id: $0, x: Double($0) * 0.1, y: 0.5) }
        f.reader.send(touches)
        f.now = 0.1
        f.reader.send(touches.map { Touch(id: $0.id, x: $0.x + 0.1, y: $0.y) })
        if reason == 0 {
            f.session.stop()
        } else if reason == 1 {
            f.permissions = PermissionState(inputMonitoring: true, accessibility: false, eventPosting: false)
            f.session.poll()
        } else {
            f.reader.onError?("Lost report during swipe")
        }
        f.reader.send(touches)
        f.reader.send([])
        f.session.stop()
        let cancellations = f.sink.actions.filter {
            if case .swipe(_, _, _, 0, .cancelled) = $0 { return true }
            return false
        }
        try expect(cancellations.count == 1)
        try expect(
            !f.sink.actions.contains {
                if case .click = $0 { return true }
                return false
            })
    }
    let disabled = Fixture()
    try disabled.session.start(kind: .input, target: disabled.target, swipes: false)
    disabled.reader.send((1...3).map { Touch(id: $0, x: Double($0) * 0.1, y: 0.5) })
    disabled.now = 0.1
    disabled.reader.send((1...3).map { Touch(id: $0, x: Double($0) * 0.1 + 0.2, y: 0.5) })
    disabled.reader.send([])
    try expect(disabled.sink.actions.isEmpty)
}
