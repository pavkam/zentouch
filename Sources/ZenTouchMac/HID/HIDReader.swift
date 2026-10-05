// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import IOKit.hid
import ZenTouchCore

func hidStatus(_ result: IOReturn) -> String {
    String(format: "0x%08x", UInt32(bitPattern: result))
}

public final class HIDReader: TouchReading {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private var originalMode: [UInt8]?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var decoder = EXC3200Decoder()
    private var scheduled = false
    private var opened = false
    private var reportCount = 0
    private var frameCount = 0
    private var lastDevices: [[String: Any]] = []
    public private(set) var modeWarning: String?
    public private(set) var multitouchObserved = false
    public var onMultitouchObserved: (() -> Void)?
    public var onFrame: ((TouchFrame) -> Void)?
    public var onReport: ((ReportStatistics) -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onError: ((String) -> Void)?
    public var statistics: ReportStatistics { ReportStatistics(reports: reportCount, frames: frameCount) }

    public init() {
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: DeviceProfile.vendorID,
                kIOHIDProductIDKey: DeviceProfile.productID,
            ] as CFDictionary)
    }

    public func devices() -> [IOHIDDevice] {
        let devices = Array((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
        let details = devices.map(deviceDetails).sorted {
            String(describing: $0["LocationID"]) < String(describing: $1["LocationID"])
        }
        if !NSArray(array: details).isEqual(to: lastDevices) {
            diagnostics.record("hid.enumerate", ["devices": details])
            lastDevices = details
        }
        return devices
    }

    public func start(seize: Bool, multitouch: Bool) throws {
        precondition(Thread.isMainThread)
        guard device == nil else { throw ZenError(message: "The reader is already running.") }
        logPermissions("hid.start.permissions")
        diagnostics.record("hid.start", ["seize": seize, "multitouch": multitouch])
        reportCount = 0
        frameCount = 0
        modeWarning = nil
        multitouchObserved = false
        let matches = devices().filter {
            (IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String)?.hasPrefix(
                DeviceProfile.productPrefix) == true
        }
        guard matches.count == 1, let found = matches.first else {
            throw ZenError(
                message: matches.isEmpty
                    ? "The ZenScreen touch controller isn't connected over USB."
                    : "More than one touch controller matched. Disconnect the extra screen.")
        }
        guard let profile = DeviceProfile.descriptor else {
            throw ZenError(
                message: "ZenTouch's controller profile is missing. Reinstall the app before enabling input.")
        }
        guard let descriptor = IOHIDDeviceGetProperty(found, kIOHIDReportDescriptorKey as CFString) as? Data,
            descriptor == profile
        else {
            throw ZenError(
                message: "This controller has a different HID layout. Capture its descriptor before enabling input.")
        }
        let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0
        let result = IOHIDManagerOpen(manager, options)
        diagnostics.record(
            "hid.open", ["result": hidStatus(result), "options": options, "device": deviceDetails(found)])
        guard result == kIOReturnSuccess else {
            IOHIDManagerClose(manager, 0)
            throw ZenError(
                message:
                    "HID open failed (\(hidStatus(result))). Grant ZenTouch Input Monitoring, quit it, and reopen it. Exclusive access also requires that other touch drivers are stopped."
            )
        }
        opened = true
        device = found
        do {
            if multitouch {
                let mode = try getMode(found)
                originalMode = mode
                var enabled = mode
                enabled[1] = 2  // HID Device Mode: multiple input.
                try setMode(found, enabled)
                let verified = try getMode(found)
                diagnostics.record("hid.mode.verify", ["bytes": hex(verified), "accepted": verified[1] == 2])
                if verified[1] != 2 {
                    // This exact EXC3200 profile emitted simultaneous contacts
                    // in live testing while GET_REPORT remained mode 0. Input
                    // packets, rather than this readback, establish the mode.
                    modeWarning = "Controller mode readback is \(verified[1]); waiting for multi-touch contact reports."
                    diagnostics.record("hid.mode.warning", ["readback": verified[1]])
                }
            }
            let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
            storage.initialize(repeating: 0, count: 64)
            buffer = storage
            IOHIDDeviceRegisterInputReportCallback(
                found, storage, 64,
                { context, result, _, type, reportID, report, count in
                    guard let context else { return }
                    let reader = Unmanaged<HIDReader>.fromOpaque(context).takeUnretainedValue()
                    guard count > 0, count <= 64 else {
                        diagnostics.record("hid.report.invalidLength", ["length": count])
                        reader.onError?("The touch controller sent an invalid report length.")
                        return
                    }
                    let bytes = Array(UnsafeBufferPointer(start: report, count: count))
                    reader.reportCount += 1
                    diagnostics.record(
                        "hid.report",
                        [
                            "result": hidStatus(result), "type": type.rawValue,
                            "reportID": reportID, "length": count, "bytes": hex(bytes), "sequence": reader.reportCount,
                        ])
                    guard result == kIOReturnSuccess else {
                        reader.onError?("Input report failed (\(hidStatus(result))).")
                        return
                    }
                    defer { reader.onReport?(reader.statistics) }
                    do {
                        if let frame = try reader.decoder.decode(bytes) {
                            reader.frameCount += 1
                            diagnostics.record(
                                "hid.frame",
                                [
                                    "scanTime": frame.scanTime, "count": frame.touches.count,
                                    "touches": frame.touches.map {
                                        ["id": $0.id, "x": $0.x, "y": $0.y] as [String: Any]
                                    },
                                    "sequence": reader.frameCount,
                                ])
                            if frame.touches.count >= 2 && !reader.multitouchObserved {
                                reader.multitouchObserved = true
                                reader.modeWarning = nil
                                diagnostics.record("hid.multitouch.observed", ["count": frame.touches.count])
                                reader.onMultitouchObserved?()
                            }
                            reader.onFrame?(frame)
                        } else {
                            diagnostics.record("hid.report.noFrame", ["reportID": reportID, "length": count])
                        }
                    } catch {
                        diagnostics.record(
                            "hid.decode.error", ["error": String(describing: error), "bytes": hex(bytes)])
                        reader.onError?("Invalid touch report: \(error)")
                    }
                }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDManagerRegisterDeviceRemovalCallback(
                manager,
                { context, _, _, removed in
                    guard let context else { return }
                    let reader = Unmanaged<HIDReader>.fromOpaque(context).takeUnretainedValue()
                    diagnostics.record("hid.removed", ["device": deviceDetails(removed)])
                    if reader.device == removed { reader.onDisconnect?() }
                }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            scheduled = true
            diagnostics.record(
                "hid.listening", ["runLoopMode": CFRunLoopMode.commonModes.rawValue as String, "bufferSize": 64])
        } catch {
            diagnostics.record("hid.start.error", ["error": error.localizedDescription])
            stop()
            throw error
        }
    }

    public func modeDescription() -> String {
        guard let found = devices().first else { return "not connected" }
        do { return String(describing: try getMode(found)) } catch { return error.localizedDescription }
    }

    private func getMode(_ device: IOHIDDevice) throws -> [UInt8] {
        var data: [UInt8] = [5, 0, 0]
        var size = data.count
        let result = data.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 5, $0.baseAddress!, &size)
        }
        diagnostics.record("hid.mode.read", ["result": hidStatus(result), "length": size, "bytes": hex(data)])
        guard result == kIOReturnSuccess, size == 3, data[0] == 5, data[1] <= 2 else {
            throw ZenError(
                message:
                    "Cannot read the controller's mode (\(hidStatus(result))). No mode change is safe until this succeeds."
            )
        }
        return data
    }

    private func setMode(_ device: IOHIDDevice, _ data: [UInt8]) throws {
        let result = data.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 5, $0.baseAddress!, data.count)
        }
        diagnostics.record("hid.mode.write", ["result": hidStatus(result), "bytes": hex(data)])
        guard result == kIOReturnSuccess else {
            throw ZenError(message: "Cannot set the controller's mode (\(hidStatus(result))).")
        }
    }

    @discardableResult public func stop() -> String? {
        var restoreError: String?
        if opened { diagnostics.record("hid.stop", ["reports": reportCount, "frames": frameCount]) }
        if scheduled {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            scheduled = false
        }
        if let device {
            if let buffer { IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil) }
            if let originalMode {
                do {
                    try setMode(device, originalMode)
                    diagnostics.record("hid.mode.restored", ["bytes": hex(originalMode)])
                } catch {
                    diagnostics.record("hid.mode.restore.error", ["error": error.localizedDescription])
                    restoreError =
                        "Could not restore the controller: \(error.localizedDescription) Reconnect its USB cable."
                }
            }
        }
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        if opened {
            IOHIDManagerClose(manager, 0)
            opened = false
        }
        buffer?.deinitialize(count: 64)
        buffer?.deallocate()
        buffer = nil
        device = nil
        originalMode = nil
        decoder.reset()
        return restoreError
    }

    deinit { stop() }
}
