// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

/// Developer-only, time-limited trace of Dock swipe events. The mask excludes
/// keyboard, mouse and ordinary scrolling; this is never enabled by default.
public final class DockSwipeTrace {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    public init() {}
    public func start(seconds: TimeInterval = 120) -> Bool {
        stop()
        guard seconds.isFinite, seconds > 0,
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly, eventsOfInterest: CGEventMask(1) << 30,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let trace = Unmanaged<DockSwipeTrace>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = trace.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if type.rawValue == 30 {
                        trace.record(event)
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            diagnostics.record("diagnostic.dockTrace.failed")
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: min(seconds, 120), repeats: false) { [weak self] _ in self?.stop() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        diagnostics.record("diagnostic.dockTrace.started", ["seconds": min(seconds, 120)])
        return true
    }
    private func record(_ event: CGEvent) {
        var fields: [String: Any] = ["sourcePID": event.getIntegerValueField(.eventSourceUnixProcessID)]
        for raw: UInt32 in [110, 123, 124, 125, 126, 129, 130, 132, 134, 135, 136, 138] {
            if let field = CGEventField(rawValue: raw) {
                let value = event.getDoubleValueField(field)
                fields["f\(raw)"] = value.isFinite ? value : 0
            }
        }
        // Dock events contain gesture metadata, not keys or application text.
        if let data = event.data {
            let bytes = data as Data
            fields["serializedBytes"] = bytes.count
            fields["serializedHex"] = bytes.prefix(2048).map { String(format: "%02x", $0) }.joined()
        }
        diagnostics.record("diagnostic.dockSwipe", fields)
    }
    public func stop() {
        timer?.invalidate()
        timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        let wasRunning = tap != nil
        tap = nil
        if wasRunning { diagnostics.record("diagnostic.dockTrace.stopped") }
    }
    deinit { stop() }
}
