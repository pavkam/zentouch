// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ServiceManagement
import ZenTouchCore

public enum LoginItemStatus: String {
    case disabled, enabled, requiresApproval, unavailable

    public init(serviceStatus: SMAppService.Status, bundledApplication: Bool) {
        guard bundledApplication else {
            self = .unavailable
            return
        }
        switch serviceStatus {
        // macOS 27 reports notFound before the first registration. The bundle
        // exists; only its Background Task Management record is missing.
        case .notRegistered, .notFound: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        @unknown default: self = .unavailable
        }
    }
}

/// macOS owns the preference; never mirror it in UserDefaults.
public final class LaunchAtLogin {
    private let readStatus: () -> LoginItemStatus
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    public var status: LoginItemStatus { readStatus() }

    public init(
        readStatus: @escaping () -> LoginItemStatus,
        register: @escaping () throws -> Void,
        unregister: @escaping () throws -> Void
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
    }

    public convenience init() {
        self.init(
            readStatus: {
                LoginItemStatus(
                    serviceStatus: SMAppService.mainApp.status,
                    bundledApplication: Bundle.main.bundleURL.pathExtension == "app")
            },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() })
    }

    public func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .disabled): try register()
        case (false, .enabled), (false, .requiresApproval): try unregister()
        case (_, .unavailable):
            throw ZenError(message: "Install ZenTouch in Applications before enabling launch at login.")
        default: break
        }
    }

    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
