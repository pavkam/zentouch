// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ApplicationServices
import Foundation
import IOKit.hid
import ZenTouchCore

let diagnostics = DiagnosticLog.shared

func logPermissions(_ event: String) {
    diagnostics.record(
        event,
        [
            "inputMonitoring": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue,
            "accessibility": AXIsProcessTrusted(),
            "eventPosting": CGPreflightPostEventAccess(),
        ])
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func deviceDetails(_ device: IOHIDDevice) -> [String: Any] {
    var fields: [String: Any] = [:]
    for key in [
        kIOHIDProductKey, kIOHIDVendorIDKey, kIOHIDProductIDKey,
        kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey, kIOHIDTransportKey,
        kIOHIDLocationIDKey, kIOHIDMaxInputReportSizeKey,
    ] {
        if let value = IOHIDDeviceGetProperty(device, key as CFString) { fields[key] = value }
    }
    if let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
        fields["descriptorMatches"] = descriptor == DeviceProfile.descriptor
        fields["descriptorBytes"] = descriptor.count
    }
    return fields
}
