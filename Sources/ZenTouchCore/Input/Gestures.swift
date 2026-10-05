// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    func distance(to other: Point) -> Double { hypot(x - other.x, y - other.y) }
}

public enum GesturePhase: Int64, Equatable, Sendable {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
}

public enum InputAction: Equatable, Sendable {
    case move(Point)
    case down(Point)
    case drag(Point)
    case up(Point)
    case click(Point, right: Bool)
    case scroll(Point, dx: Double, dy: Double, phase: GesturePhase)
    case magnify(Point, delta: Double, phase: GesturePhase)
}

/// Direct touch: one finger clicks/drags; two fingers scroll/pinch/right-click.
/// Once a multi-finger interaction ends, remaining fingers cannot become clicks.
public struct GestureEngine {
    private enum Mode { case idle, single, pair, scroll, pinch, suppress }
    private var mode = Mode.idle
    private var ids: [Int] = []
    private var start = Point(x: 0, y: 0)
    private var last = Point(x: 0, y: 0)
    private var startDistance = 0.0
    private var lastDistance = 0.0
    private var beganAt = 0.0
    private var dragging = false
    private var pairTap = true
    private let width: Double
    private let height: Double
    public let pinchEnabled: Bool
    public var hasActiveGesture: Bool { mode != .idle && mode != .suppress }

    public init(width: Double, height: Double, pinchEnabled: Bool = false) {
        self.width = width
        self.height = height
        self.pinchEnabled = pinchEnabled
    }

    public mutating func cancel() -> [InputAction] {
        var actions: [InputAction] = []
        if dragging { actions.append(.up(last)) }
        if mode == .scroll { actions.append(.scroll(start, dx: 0, dy: 0, phase: .cancelled)) }
        if mode == .pinch { actions.append(.magnify(start, delta: 0, phase: .cancelled)) }
        mode = .idle
        ids = []
        dragging = false
        return actions
    }

    /// After a lost/invalid packet, residual fingers must not become a new tap.
    public mutating func cancelUntilLift() -> [InputAction] {
        let actions = cancel()
        mode = .suppress
        return actions
    }

    public mutating func process(_ touches: [Touch], time: Double) -> [InputAction] {
        let sorted = touches.sorted { $0.id < $1.id }
        guard time.isFinite, Set(sorted.map(\.id)).count == sorted.count,
            sorted.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
        else {
            return cancelUntilLift()
        }
        let newIDs = sorted.map(\.id)
        let points = sorted.map { Point(x: $0.x * width, y: $0.y * height) }
        var actions: [InputAction] = []
        if sorted.isEmpty {
            if mode == .single {
                if dragging {
                    actions.append(.up(last))
                } else if time - beganAt <= 0.5 {
                    actions.append(.click(last, right: false))
                } else {
                    actions.append(.click(last, right: true))
                }
            } else if mode == .pair, pairTap, time - beganAt <= 0.5 {
                actions.append(.click(last, right: true))
            } else if mode == .scroll {
                actions.append(.scroll(start, dx: 0, dy: 0, phase: .ended))
            } else if mode == .pinch {
                actions.append(.magnify(start, delta: 0, phase: .ended))
            }
            mode = .idle
            ids = []
            dragging = false
            return actions
        }
        if mode == .suppress { return [] }
        if sorted.count > 2 {
            actions += cancel()
            mode = .suppress
            return actions
        }
        if mode == .idle {
            mode = sorted.count == 1 ? .single : .pair
            pairTap = true
            ids = newIDs
            beganAt = time
            start = centroid(points)
            last = start
            if sorted.count == 2 {
                startDistance = points[0].distance(to: points[1])
                lastDistance = startDistance
            }
            return [.move(start)]
        }
        if newIDs != ids {
            if mode == .pair, sorted.count == 1, ids.contains(newIDs[0]), pairTap, time - beganAt <= 0.5 {
                actions.append(.click(last, right: true))
                mode = .suppress
                return actions
            }
            // Adding a second finger before a drag qualifies for a two-finger gesture.
            if mode == .single, sorted.count == 2, !dragging, newIDs.contains(ids[0]) {
                mode = .pair
                ids = newIDs
                beganAt = time
                pairTap = true
                start = centroid(points)
                last = start
                startDistance = points[0].distance(to: points[1])
                lastDistance = startDistance
                return [.move(start)]
            }
            actions += cancel()
            mode = .suppress
            return actions
        }
        let center = centroid(points)
        if mode == .single {
            if !dragging, start.distance(to: center) >= 8 {
                dragging = true
                actions.append(.down(start))
            }
            actions.append(dragging ? .drag(center) : .move(center))
        } else {
            let distance = points[0].distance(to: points[1])
            if mode == .pair {
                let travel = start.distance(to: center)
                let spread = abs(distance - startDistance)
                if travel >= 8 || spread >= 12 { pairTap = false }
                if pinchEnabled, startDistance > 10, spread >= 12, spread > travel * 1.5 {
                    mode = .pinch
                    actions.append(.magnify(start, delta: 0, phase: .began))
                } else if travel >= 8, travel > spread * 0.6 {
                    mode = .scroll
                    actions.append(.scroll(start, dx: 0, dy: 0, phase: .began))
                }
            }
            if mode == .scroll {
                actions.append(.scroll(start, dx: center.x - last.x, dy: center.y - last.y, phase: .changed))
            } else if mode == .pinch, lastDistance > 10 {
                let delta = max(-0.2, min(0.2, distance / lastDistance - 1))
                actions.append(.magnify(start, delta: delta, phase: .changed))
            }
            lastDistance = distance
        }
        last = center
        return actions
    }

    private func centroid(_ points: [Point]) -> Point {
        Point(
            x: points.map(\.x).reduce(0, +) / Double(points.count),
            y: points.map(\.y).reduce(0, +) / Double(points.count))
    }
}
