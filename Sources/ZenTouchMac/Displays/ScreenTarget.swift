// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit

public struct DisplayGeometry: Equatable {
    public let bounds: CGRect
    public let rotation: Double
    public init(bounds: CGRect, rotation: Double) {
        self.bounds = bounds
        self.rotation = rotation
    }
    public var supported: Bool {
        bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width >= 1 && bounds.height >= 1 && rotation.isFinite
            && rotation.truncatingRemainder(dividingBy: 360) == 0
    }
}

public struct ScreenTarget: Equatable {
    public let id: CGDirectDisplayID
    public let name: String
    public init(id: CGDirectDisplayID, name: String) {
        self.id = id
        self.name = name
    }
    public var geometry: DisplayGeometry? {
        guard CGDisplayIsOnline(id) != 0 else { return nil }
        return DisplayGeometry(bounds: CGDisplayBounds(id), rotation: CGDisplayRotation(id))
    }
    public static var all: [ScreenTarget] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return ScreenTarget(id: number.uint32Value, name: screen.localizedName)
        }
    }
    public static var zenScreen: ScreenTarget? { all.first { $0.name.contains("MB16AM") } }
}
