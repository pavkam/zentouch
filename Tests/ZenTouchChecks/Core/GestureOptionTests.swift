// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ZenTouchCore

private func contacts(_ count: Int, x: Double = 0.4, y: Double = 0.5) -> [Touch] {
    (0..<count).map { Touch(id: $0, x: x + Double($0) * 0.1, y: y) }
}
private func isClick(_ action: InputAction) -> Bool {
    if case .click = action { return true }
    if case .down = action { return true }
    if case .drag = action { return true }
    return false
}

func disabledClicksStillAllowTwoFingerScrollingAndZoom() throws {
    var engine = GestureEngine(width: 1000, height: 1000, options: GestureOptions(clicks: false))
    try expect(engine.process(contacts(1), time: 0).isEmpty)
    try expect(engine.process(contacts(1, x: 0.5), time: 0.1).isEmpty)
    try expect(engine.process([], time: 0.2).isEmpty)
    _ = engine.process(contacts(1), time: 1)
    _ = engine.process(contacts(2), time: 1.1)
    let scroll = engine.process(contacts(2, y: 0.54), time: 1.2)
    try expect(
        scroll.contains {
            if case .scroll = $0 { return true }
            return false
        })
    try expect(!scroll.contains(where: isClick))
    _ = engine.process([], time: 1.3)
    _ = engine.process(contacts(2), time: 2)
    let zoom = engine.process([Touch(id: 0, x: 0.38, y: 0.5), Touch(id: 1, x: 0.52, y: 0.5)], time: 2.1)
    try expect(
        zoom.contains {
            if case .magnify = $0 { return true }
            return false
        })
    _ = engine.process([], time: 2.2)
    _ = engine.process(contacts(2), time: 3)
    try expect(engine.process(contacts(1), time: 3.1).isEmpty)
    try expect(engine.process([], time: 3.2).isEmpty)
}

func disabledScrollingNeverConvertsMotionToSecondaryClick() throws {
    var engine = GestureEngine(width: 1000, height: 1000, options: GestureOptions(scrolling: false))
    _ = engine.process(contacts(2), time: 0)
    try expect(engine.process(contacts(2, y: 0.55), time: 0.1).isEmpty)
    try expect(engine.process(contacts(1, y: 0.55), time: 0.2).isEmpty)
    try expect(engine.process([], time: 0.3).isEmpty)
    _ = engine.process(contacts(2), time: 1)
    let zoom = engine.process([Touch(id: 0, x: 0.38, y: 0.5), Touch(id: 1, x: 0.52, y: 0.5)], time: 1.1)
    try expect(
        zoom.contains {
            if case .magnify = $0 { return true }
            return false
        })
}

func gestureChangesReleaseActiveInputAndSuppressUntilLift() throws {
    var engine = GestureEngine(width: 1000, height: 1000, options: GestureOptions())
    _ = engine.process(contacts(1), time: 0)
    _ = engine.process(contacts(1, x: 0.45), time: 0.1)
    var next = GestureOptions(clicks: false)
    try expect(engine.updateOptions(next) == [.up(Point(x: 450, y: 500))])
    try expect(engine.process(contacts(2), time: 0.2).isEmpty)
    next.clicks = true
    try expect(engine.updateOptions(next).isEmpty)
    try expect(engine.process(contacts(1), time: 0.3).isEmpty)
    try expect(engine.process([], time: 0.4).isEmpty)
    _ = engine.process(contacts(1), time: 0.5)
    try expect(engine.process([], time: 0.6).contains(where: isClick))
    _ = engine.process(contacts(2), time: 1)
    _ = engine.process([Touch(id: 0, x: 0.38, y: 0.5), Touch(id: 1, x: 0.52, y: 0.5)], time: 1.1)
    next.pinch = false
    try expect(engine.updateOptions(next) == [.magnify(Point(x: 450, y: 500), delta: 0, phase: .cancelled)])
    try expect(engine.process(contacts(1), time: 1.2).isEmpty)
    try expect(engine.process([], time: 1.3).isEmpty)
}

func allGesturesDisabledProduceNoInput() throws {
    let options = GestureOptions(
        clicks: false, scrolling: false, pinch: false, desktops: false, missionControl: false, appExpose: false)
    for count in 1...3 {
        var engine = GestureEngine(width: 1000, height: 1000, options: options)
        try expect(engine.process(contacts(count), time: 0).isEmpty)
        try expect(engine.process(contacts(count, x: 0.55, y: 0.55), time: 0.1).isEmpty)
        try expect(engine.process(contacts(1), time: 0.2).isEmpty)
        try expect(engine.process([], time: 0.3).isEmpty)
    }
}

func threeFingerDirectionsAreIndependentlyEnabled() throws {
    for enabled in [GestureFeature.desktops, .missionControl, .appExpose] {
        var options = GestureOptions(desktops: false, missionControl: false, appExpose: false)
        options[enabled] = true
        for direction in [GestureFeature.desktops, .missionControl, .appExpose] {
            var engine = GestureEngine(width: 1000, height: 1000, options: options)
            _ = engine.process(contacts(3), time: 0)
            let moved = contacts(
                3, x: direction == .desktops ? 0.5 : 0.4,
                y: direction == .missionControl ? 0.4 : direction == .appExpose ? 0.6 : 0.5)
            let actions = engine.process(moved, time: 0.1) + engine.process([], time: 0.2)
            let swipes = actions.filter {
                if case .swipe = $0 { return true }
                return false
            }
            try expect(swipes.isEmpty == (enabled != direction))
        }
    }
}

func pinchIncludesThresholdTravelAndVerticalReversalCancels() throws {
    var engine = GestureEngine(width: 1000, height: 1000, options: GestureOptions())
    _ = engine.process(contacts(2), time: 0)
    _ = engine.process([Touch(id: 0, x: 0.396, y: 0.5), Touch(id: 1, x: 0.504, y: 0.5)], time: 0.1)
    let actions = engine.process([Touch(id: 0, x: 0.392, y: 0.5), Touch(id: 1, x: 0.508, y: 0.5)], time: 0.2)
    let delta = actions.compactMap { action -> Double? in
        if case .magnify(_, let delta, .changed) = action { return delta }
        return nil
    }
    try expect(delta.count == 1 && abs(delta[0] - 0.16) < 0.0001)
    var swipe = GestureEngine(width: 1000, height: 1000, options: GestureOptions(appExpose: false))
    _ = swipe.process(contacts(3), time: 0)
    _ = swipe.process(contacts(3, y: 0.4), time: 0.1)
    _ = swipe.process(contacts(3, y: 0.6), time: 0.2)
    let finished = swipe.process([], time: 0.3)
    try expect(finished.count == 1)
    if case .swipe(_, .vertical, _, 0, .cancelled) = finished[0] {
    } else {
        try expect(false)
    }
}
