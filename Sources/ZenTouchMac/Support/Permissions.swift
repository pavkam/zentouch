// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ApplicationServices
import IOKit.hid

public struct PermissionState: Equatable {
    public let inputMonitoring: Bool
    public let accessibility: Bool
    public let eventPosting: Bool
    public var canBridge: Bool { inputMonitoring && accessibility && eventPosting }

    public init(inputMonitoring: Bool, accessibility: Bool, eventPosting: Bool) {
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.eventPosting = eventPosting
    }

    public static var current: PermissionState {
        PermissionState(
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
            accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
    }

    public static func requestInputMonitoring() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    public static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
