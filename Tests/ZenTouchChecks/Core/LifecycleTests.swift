// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ZenTouchCore

func independentSuspensionReasonsMustAllClear() throws {
    var reasons: SuspensionReasons = [.sleep, .inactiveSession, .displaySleep]
    reasons.remove(.sleep)
    try expect(!reasons.isEmpty && reasons.contains(.inactiveSession))
    reasons.remove(.inactiveSession)
    try expect(!reasons.isEmpty && reasons.contains(.displaySleep))
    reasons.remove(.displaySleep)
    try expect(reasons.isEmpty)
    reasons.insert(.sleep)
    reasons.remove(.inactiveSession)
    try expect(!reasons.isEmpty)
}
