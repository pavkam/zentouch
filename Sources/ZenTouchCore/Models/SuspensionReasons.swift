// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

/// Independent sleep/lock reasons must all clear before input resumes.
public struct SuspensionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let sleep = SuspensionReasons(rawValue: 1 << 0)
    public static let inactiveSession = SuspensionReasons(rawValue: 1 << 1)
    public static let displaySleep = SuspensionReasons(rawValue: 1 << 2)
}
