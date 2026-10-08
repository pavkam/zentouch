// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ServiceManagement
import ZenTouchCore
import ZenTouchMac

func loginItemFirstRegistrationIsAvailableInAppBundle() throws {
    try expect(LoginItemStatus(serviceStatus: .notFound, bundledApplication: true) == .disabled)
    try expect(LoginItemStatus(serviceStatus: .notRegistered, bundledApplication: true) == .disabled)
    try expect(LoginItemStatus(serviceStatus: .enabled, bundledApplication: true) == .enabled)
    try expect(LoginItemStatus(serviceStatus: .requiresApproval, bundledApplication: true) == .requiresApproval)
    for state in [SMAppService.Status.notFound, .notRegistered, .enabled, .requiresApproval] {
        try expect(LoginItemStatus(serviceStatus: state, bundledApplication: false) == .unavailable)
    }
}

func loginItemUsesSystemStatusAndHandlesApproval() throws {
    var status = LoginItemStatus.disabled
    var registrations = 0
    var removals = 0
    let login = LaunchAtLogin(
        readStatus: { status },
        register: {
            registrations += 1
            status = .requiresApproval
        },
        unregister: {
            removals += 1
            status = .disabled
        })
    try login.setEnabled(false)
    try expect(registrations == 0 && removals == 0)
    try login.setEnabled(true)
    try expect(login.status == .requiresApproval && registrations == 1)
    try login.setEnabled(true)
    try expect(registrations == 1)
    try login.setEnabled(false)
    try expect(login.status == .disabled && removals == 1)
    status = .enabled
    try login.setEnabled(true)
    try expect(registrations == 1)
    status = .disabled  // External changes must be visible immediately.
    try expect(login.status == .disabled)
    status = .enabled
    try login.setEnabled(false)
    try expect(removals == 2)
}

func loginItemFailuresNeverPretendRegistrationSucceeded() throws {
    var status = LoginItemStatus.disabled
    let login = LaunchAtLogin(
        readStatus: { status },
        register: { throw ZenError(message: "Registration denied") },
        unregister: { throw ZenError(message: "Removal denied") })
    try expectThrows(ZenError.self) { try login.setEnabled(true) }
    try expect(login.status == .disabled)
    status = .enabled
    try expectThrows(ZenError.self) { try login.setEnabled(false) }
    try expect(login.status == .enabled)
    status = .unavailable
    try expectThrows(ZenError.self) { try login.setEnabled(true) }
    try expectThrows(ZenError.self) { try login.setEnabled(false) }
}
