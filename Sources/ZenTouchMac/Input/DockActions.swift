// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-FileCopyrightText: 2026 Scott Lamb
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

/// Isolated private Dock command adapter, following macos-trackpad-companion.
/// Vertical gestures commit on lift; horizontal gestures retain their phased ABI.
public enum DockActions {
    public enum Failure: Error {
        case unavailable
        case rejected(Int32)
    }
    private typealias SendNotification = @convention(c) (UnsafeRawPointer?, Int32) -> Int32
    // Keep the framework mapped for the lifetime of the cached function pointer.
    private static let framework = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        RTLD_LAZY)
    private static let send: SendNotification? = {
        guard let framework, let symbol = dlsym(framework, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()
    public static var isAvailable: Bool { send != nil }

    public static func perform(_ action: SystemGestureAction) throws {
        guard let send else { throw Failure.unavailable }
        let name = (action == .missionControl ? "com.apple.expose.awake" : "com.apple.expose.front.awake") as CFString
        let result = withExtendedLifetime(name) { send(Unmanaged.passUnretained(name).toOpaque(), 0) }
        guard result == 0 else { throw Failure.rejected(result) }
    }
}
