// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore

private func finger(_ id: Int, _ x: Double, _ y: Double) -> Touch { Touch(id: id, x: x, y: y) }
private func finger(_ x: Double, _ y: Double) -> Touch { finger(1, x, y) }

func tapDoesNotPressUntilLift() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    try expect(engine.process([finger(0.5, 0.5)], time: 0) == [.move(Point(x: 500, y: 500))])
    try expect(engine.process([], time: 0.1) == [.click(Point(x: 500, y: 500), right: false)])
}

func cancelledDragAlwaysReleasesButton() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process([finger(0.5, 0.5)], time: 0)
    try expect(
        engine.process([finger(0.52, 0.5)], time: 0.1) == [.down(Point(x: 500, y: 500)), .drag(Point(x: 520, y: 500))])
    try expect(engine.cancel() == [.up(Point(x: 520, y: 500))])
    try expect(engine.process([], time: 0.2).isEmpty)
}

func twoFingerScrollHasPhasesAndNoAccidentalClick() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process([finger(1, 0.4, 0.5), finger(2, 0.6, 0.5)], time: 0)
    let actions = engine.process([finger(1, 0.4, 0.52), finger(2, 0.6, 0.52)], time: 0.1)
    try expect(actions.count == 2)
    try expect(actions[0] == .scroll(Point(x: 500, y: 500), dx: 0, dy: 0, phase: .began))
    _ = engine.process([finger(1, 0.4, 0.52)], time: 0.2)
    try expect(engine.process([], time: 0.3).isEmpty)
}

func sequentialTwoFingerLiftRightClicksOnce() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process([finger(1, 0.4, 0.5), finger(2, 0.6, 0.5)], time: 0)
    try expect(engine.process([finger(1, 0.4, 0.5)], time: 0.1) == [.click(Point(x: 500, y: 500), right: true)])
    try expect(engine.process([], time: 0.2).isEmpty)
}

func pinchIsOptInAndLatchesUntilLift() throws {
    var engine = GestureEngine(width: 1000, height: 1000, pinchEnabled: true)
    _ = engine.process([finger(1, 0.4, 0.5), finger(2, 0.6, 0.5)], time: 0)
    let actions = engine.process([finger(1, 0.38, 0.5), finger(2, 0.62, 0.5)], time: 0.1)
    try expect(actions.count == 2)
    try expect(actions.first == .magnify(Point(x: 500, y: 500), delta: 0, phase: .began))
    try expect(engine.process([], time: 0.2) == [.magnify(Point(x: 500, y: 500), delta: 0, phase: .ended)])
}

func disabledPinchCannotBecomeRightClick() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process([finger(1, 0.4, 0.5), finger(2, 0.6, 0.5)], time: 0)
    _ = engine.process([finger(1, 0.38, 0.5), finger(2, 0.62, 0.5)], time: 0.1)
    try expect(engine.process([], time: 0.2).isEmpty)
}

func addedThirdFingerCancelsDragWithoutClick() throws {
    var engine = GestureEngine(width: 1000, height: 1000)
    _ = engine.process([finger(0.2, 0.2)], time: 0)
    _ = engine.process([finger(0.3, 0.2)], time: 0.1)
    try expect(
        engine.process([finger(1, 0.3, 0.2), finger(2, 0.5, 0.2), finger(3, 0.7, 0.2)], time: 0.2) == [
            .up(Point(x: 300, y: 200))
        ])
    try expect(engine.process([], time: 0.3).isEmpty)
}
