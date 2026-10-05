// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

public enum SystemGestureAction: String, Equatable, Sendable { case missionControl, appExpose }

/// Native Dock commands are discrete: commit a deliberate swipe once on lift.
/// Returning toward the origin cancels, as does a too-short swipe or lost contact.
public struct VerticalSwipeCommit {
    private var active = false
    private var lastProgress = 0.0
    private var lastMovement = 0.0
    public init() {}

    public mutating func process(progress: Double, phase: GesturePhase) -> SystemGestureAction? {
        guard progress.isFinite else {
            active = false
            return nil
        }
        if phase == .began {
            active = true
            lastProgress = progress
            lastMovement = 0
            return nil
        }
        guard active else { return nil }
        if phase == .cancelled {
            active = false
            return nil
        }
        if progress != lastProgress { lastMovement = progress - lastProgress }
        lastProgress = progress
        guard phase == .ended else { return nil }
        active = false
        guard abs(progress) >= 0.2, lastMovement * progress > 0 else { return nil }
        return progress < 0 ? .missionControl : .appExpose
    }
}
