// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore
import ZenTouchMac

final class AppPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var gestureOptions: GestureOptions {
        var options = GestureOptions()
        for feature in GestureFeature.allCases {
            let legacy: Bool
            switch feature {
            case .pinch: legacy = defaults.object(forKey: "experimentalPinch") as? Bool ?? true
            case .desktops, .missionControl, .appExpose:
                legacy = defaults.object(forKey: "threeFingerSwipes") as? Bool ?? true
            default: legacy = true
            }
            options[feature] = defaults.object(forKey: "gesture.\(feature.rawValue)") as? Bool ?? legacy
        }
        return options
    }
    func setGesture(_ feature: GestureFeature, enabled: Bool) {
        defaults.set(enabled, forKey: "gesture.\(feature.rawValue)")
    }
    var inputEnabled: Bool {
        get { defaults.bool(forKey: "touchInputEnabled") }
        set { defaults.set(newValue, forKey: "touchInputEnabled") }
    }
    var keepPointerStationary: Bool {
        get { defaults.bool(forKey: "keepPointerStationary") }
        set { defaults.set(newValue, forKey: "keepPointerStationary") }
    }
    var experimentalPinch: Bool {
        get { defaults.bool(forKey: "experimentalPinch") }
        set { defaults.set(newValue, forKey: "experimentalPinch") }
    }
    var threeFingerSwipes: Bool {
        get { defaults.object(forKey: "threeFingerSwipes") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "threeFingerSwipes") }
    }
    var showTouchIndicators: Bool {
        get { defaults.bool(forKey: "showTouchIndicators") }
        set { defaults.set(newValue, forKey: "showTouchIndicators") }
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
        DisplaySelection.resolve(id: displayID, uuid: defaults.string(forKey: "selectedDisplayUUID"), in: targets)
    }
    func select(_ target: ScreenTarget?) {
        displayID = target?.id
        if let uuid = target?.uuid {
            defaults.set(uuid, forKey: "selectedDisplayUUID")
        } else {
            defaults.removeObject(forKey: "selectedDisplayUUID")
        }
    }
}
