// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

/// User intent survives temporary USB/display loss. Explicit Stop and contact
/// testing clear it. Failed reopen attempts back off without opening Settings.
public final class SessionRecovery {
    public enum Result: Equatable {
        case idle, waiting, started
        case failed(String)
    }
    public private(set) var requested = false
    private let session: TouchSession
    private let now: () -> TimeInterval
    private var nextAttempt = 0.0
    private var retryDelay = 1.0

    public init(session: TouchSession, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.session = session
        self.now = now
    }
    public func request(_ enabled: Bool) {
        requested = enabled
        nextAttempt = 0
        retryDelay = 1
    }
    public func startInput(target: ScreenTarget?, pinch: Bool, swipes: Bool) throws {
        do {
            try session.start(kind: .input, target: target, pinch: pinch, swipes: swipes)
            nextAttempt = 0
            retryDelay = 1
        } catch {
            nextAttempt = now() + retryDelay
            retryDelay = min(15, retryDelay * 2)
            throw error
        }
    }
    @discardableResult public func refresh(
        available: Bool, suspended: Bool, target: ScreenTarget?, pinch: Bool = false, swipes: Bool = true
    ) -> Result {
        session.poll()
        guard requested, !suspended, !session.state.isRunning else { return .idle }
        guard available else {
            nextAttempt = 0
            retryDelay = 1
            return .waiting
        }
        guard now() >= nextAttempt else { return .idle }
        do {
            try startInput(target: target, pinch: pinch, swipes: swipes)
            return .started
        } catch { return .failed(error.localizedDescription) }
    }
}
