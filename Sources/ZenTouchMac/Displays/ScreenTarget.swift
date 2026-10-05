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
    public let uuid: String?
    public init(id: CGDirectDisplayID, name: String, uuid: String? = nil) {
        self.id = id
        self.name = name
        self.uuid = uuid
    }
    public var geometry: DisplayGeometry? {
        guard CGDisplayIsOnline(id) != 0, CGDisplayIsAsleep(id) == 0 else { return nil }
        return DisplayGeometry(bounds: CGDisplayBounds(id), rotation: CGDisplayRotation(id))
    }
    public static var all: [ScreenTarget] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = number.uint32Value
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            }
            return ScreenTarget(id: id, name: screen.localizedName, uuid: uuid)
        }
    }
    public static var zenScreen: ScreenTarget? { all.first { $0.name.contains("MB16AM") } }
}

/// Display IDs can change after monitor sleep. A saved UUID must never silently
/// resolve to another display that happens to inherit its old numeric ID.
public enum DisplaySelection {
    public static func resolve(id: UInt32?, uuid: String?, in targets: [ScreenTarget]) -> ScreenTarget? {
        if let uuid { return targets.first { $0.uuid == uuid } }
        if let id, let exact = targets.first(where: { $0.id == id }) { return exact }
        let screens = targets.filter { $0.name.contains("MB16AM") }
        return screens.count == 1 ? screens.first : nil
    }
}
