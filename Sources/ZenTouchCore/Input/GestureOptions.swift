// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

public enum GestureFeature: String, CaseIterable, Sendable {
    case clicks, scrolling, pinch, desktops, missionControl, appExpose
}

public struct GestureOptions: Equatable, Sendable {
    public var clicks: Bool
    public var scrolling: Bool
    public var pinch: Bool
    public var desktops: Bool
    public var missionControl: Bool
    public var appExpose: Bool
    public var hasThreeFingerGesture: Bool { desktops || missionControl || appExpose }

    public init(
        clicks: Bool = true, scrolling: Bool = true, pinch: Bool = true,
        desktops: Bool = true, missionControl: Bool = true, appExpose: Bool = true
    ) {
        self.clicks = clicks
        self.scrolling = scrolling
        self.pinch = pinch
        self.desktops = desktops
        self.missionControl = missionControl
        self.appExpose = appExpose
    }

    public subscript(_ feature: GestureFeature) -> Bool {
        get {
            switch feature {
            case .clicks: return clicks
            case .scrolling: return scrolling
            case .pinch: return pinch
            case .desktops: return desktops
            case .missionControl: return missionControl
            case .appExpose: return appExpose
            }
        }
        set {
            switch feature {
            case .clicks: clicks = newValue
            case .scrolling: scrolling = newValue
            case .pinch: pinch = newValue
            case .desktops: desktops = newValue
            case .missionControl: missionControl = newValue
            case .appExpose: appExpose = newValue
            }
        }
    }
}
