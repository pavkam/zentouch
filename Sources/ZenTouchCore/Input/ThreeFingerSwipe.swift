// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

/// Recognizes coherent movement, locks the axis, and sends cumulative progress.
/// The Dock decides whether a completed swipe commits or springs back.
struct ThreeFingerSwipe {
    private let origins: [Point]
    private let anchor: Point
    private var axis: SwipeAxis?
    private var progress = 0.0
    private var velocity = 0.0
    private var lastTime: Double
    private var lastMovementTime: Double
    private static let fullTravel = 240.0

    init(points: [Point], time: Double) {
        origins = points
        anchor = Point(x: points.map(\.x).reduce(0, +) / 3, y: points.map(\.y).reduce(0, +) / 3)
        lastTime = time
        lastMovementTime = time
    }

    mutating func process(points: [Point], time: Double) -> [InputAction] {
        guard time >= lastTime else { return [] }
        let deltas = zip(points, origins).map { Point(x: $0.x - $1.x, y: $0.y - $1.y) }
        let dx = deltas.map(\.x).reduce(0, +) / 3
        let dy = deltas.map(\.y).reduce(0, +) / 3
        var actions: [InputAction] = []
        if axis == nil {
            let candidate: SwipeAxis
            if abs(dx) >= 24 && abs(dx) > abs(dy) * 1.25 {
                candidate = .horizontal
            } else if abs(dy) >= 24 && abs(dy) > abs(dx) * 1.25 {
                candidate = .vertical
            } else {
                return []
            }
            let travel = candidate == .horizontal ? dx : dy
            guard
                deltas.allSatisfy({
                    let movement = candidate == .horizontal ? $0.x : $0.y
                    return movement * travel > 0 && abs(movement) >= 12
                        && hypot($0.x - dx, $0.y - dy) <= max(24, abs(travel) * 0.5)
                })
            else { return [] }
            axis = candidate
            actions.append(.swipe(anchor, axis: candidate, progress: 0, velocity: 0, phase: .began))
        }
        guard let axis else { return [] }
        let next = max(-1, min(1, (axis == .horizontal ? dx : dy) / Self.fullTravel))
        let dt = time - lastTime
        if dt > 0 {
            velocity = max(-8, min(8, (next - progress) / dt))
        }
        if next != progress { lastMovementTime = time }
        progress = next
        lastTime = time
        actions.append(.swipe(anchor, axis: axis, progress: progress, velocity: 0, phase: .changed))
        return actions
    }

    func finish(cancelled: Bool, time: Double) -> [InputAction] {
        guard let axis else { return [] }  // Three-finger taps have no action.
        let age = time - lastMovementTime
        let endVelocity = !cancelled && age >= 0 && age <= 0.1 ? velocity : 0
        return [
            .swipe(
                anchor, axis: axis, progress: progress, velocity: endVelocity,
                phase: cancelled ? .cancelled : .ended)
        ]
    }
}
