// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchMac

final class AppPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var inputEnabled: Bool {
        get { defaults.bool(forKey: "touchInputEnabled") }
        set { defaults.set(newValue, forKey: "touchInputEnabled") }
    }
    var experimentalPinch: Bool {
        get { defaults.bool(forKey: "experimentalPinch") }
        set { defaults.set(newValue, forKey: "experimentalPinch") }
    }
    var displayID: UInt32? {
        get { (defaults.object(forKey: "selectedDisplayID") as? NSNumber)?.uint32Value }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "selectedDisplayID")
            } else {
                defaults.removeObject(forKey: "selectedDisplayID")
            }
        }
    }
    func selectedTarget(in targets: [ScreenTarget]) -> ScreenTarget? {
        if let displayID { return targets.first { $0.id == displayID } }
        return targets.first { $0.name.contains("MB16AM") }
    }
}
