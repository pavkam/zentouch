// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore

private func three(_ dx: Double = 0, _ dy: Double = 0) -> [Touch] {
    (1...3).map { Touch(id: $0, x: Double($0) * 0.1 + dx, y: 0.5 + dy) }
}
private let anchor = Point(x: 200, y: 500)

func threeFingerSwipeHasCumulativePhasesAndAxisLock() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process(three(), time: 0)
    try expect(engine.process(three(0.01), time: 0.01).isEmpty)
    let began = engine.process(three(0.048), time: 0.1)
    try expect(began.first == .swipe(anchor, axis: .horizontal, progress: 0, velocity: 0, phase: .began))
    guard case .swipe(_, .horizontal, let progress, _, .changed) = began.last else {
        throw CheckFailure(description: "Missing horizontal changed phase")
    }
    try expect(abs(progress - 0.2) < 0.00001)
    let moved = engine.process(three(0.12, -0.2), time: 0.2)
    guard case .swipe(_, .horizontal, let cumulative, _, .changed) = moved.first else {
        throw CheckFailure(description: "Axis changed mid-swipe")
    }
    try expect(abs(cumulative - 0.5) < 0.00001)
    let ended = engine.process([], time: 0.25)
    guard case .swipe(_, .horizontal, _, let velocity, .ended) = ended.first else {
        throw CheckFailure(description: "Missing ended phase")
    }
    try expect(velocity > 0 && velocity <= 8 && !engine.hasActiveGesture)
}

func threeFingerSwipePromotesSequentialPlacementAndSuppressesLift() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process(Array(three().prefix(1)), time: 0)
    _ = engine.process(Array(three().prefix(2)), time: 0.03)
    _ = engine.process(three(), time: 0.06)
    _ = engine.process(three(0, -0.12), time: 0.16)
    let ended = engine.process(Array(three(0, -0.12).prefix(2)), time: 0.2)
    guard case .swipe(_, .vertical, let progress, _, .ended) = ended.first else {
        throw CheckFailure(description: "First lift did not end vertical swipe")
    }
    try expect(abs(progress + 0.5) < 0.00001)
    try expect(engine.process(Array(three().prefix(1)), time: 0.22).isEmpty)
    try expect(engine.process([], time: 0.24).isEmpty)
}

func thirdFingerNeverConvertsActiveScrollToNavigation() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process(Array(three().prefix(2)), time: 0)
    _ = engine.process(Array(three(0, 0.05).prefix(2)), time: 0.1)
    let actions = engine.process(three(0, 0.05), time: 0.15)
    try expect(actions.count == 1)
    guard case .scroll(_, _, _, .cancelled) = actions.first else {
        throw CheckFailure(description: "Active scroll must cancel")
    }
    try expect(engine.process(three(0.3), time: 0.2).isEmpty)
    try expect(engine.process([], time: 0.3).isEmpty)
}

func incoherentThreeFingerMotionAndTapsDoNothing() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process(three(), time: 0)
    var moving = three()
    moving[0] = Touch(id: 1, x: 0.4, y: 0.5)
    try expect(engine.process(moving, time: 0.1).isEmpty)
    try expect(engine.process([], time: 0.2).isEmpty)
    _ = engine.process(three(), time: 1)
    try expect(engine.process([], time: 1.1).isEmpty)
    var disabled = GestureEngine(width: 1000, height: 1000, swipesEnabled: false)
    try expect(disabled.process(three(), time: 0).isEmpty)
    try expect(disabled.process(three(0.3), time: 0.1).isEmpty)
    try expect(disabled.process([], time: 0.2).isEmpty)
}

func swipeCancelsOnFourthFingerAndContactReplacement() throws {
    for replace in [false, true] {
        var engine = GestureEngine(width: 1000, height: 1000)
        _ = engine.process(three(), time: 0)
        _ = engine.process(three(0.1), time: 0.1)
        var changed = three(0.1)
        if replace { changed.removeFirst() }
        changed.append(Touch(id: 4, x: 0.6, y: 0.5))
        let actions = engine.process(changed, time: 0.2)
        guard case .swipe(_, _, _, 0, .cancelled) = actions.first else {
            throw CheckFailure(description: "Unexpected contact change must cancel")
        }
        try expect(engine.process(three(0.3), time: 0.3).isEmpty)
        try expect(engine.process([], time: 0.4).isEmpty)
    }
}

func swipeReversalAndPausedLiftHaveNoStaleVelocity() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process(three(), time: 0)
    _ = engine.process(three(0.2), time: 0.1)
    let reversed = engine.process(three(), time: 0.2)
    try expect(reversed == [.swipe(anchor, axis: .horizontal, progress: 0, velocity: 0, phase: .changed)])
    try expect(
        engine.process([], time: 0.5) == [
            .swipe(anchor, axis: .horizontal, progress: 0, velocity: 0, phase: .ended)
        ])
}
