// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit

enum WindowDiscovery {
    static func decode(_ info: [String: Any]) -> InputWindow? {
        guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let dictionary = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        else { return nil }
        let window = InputWindow(id: id, pid: pid, bounds: bounds)
        return window.isValid ? window : nil
    }
    static func visible(at point: CGPoint) -> [InputWindow] {
        let ignored = Set(
            NSApplication.shared.windows.filter { $0.ignoresMouseEvents }.compactMap {
                $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil
            })
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        let candidates: [InputWindow] = list.compactMap { info in
            guard (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                let window = decode(info), !ignored.contains(window.id)
            else { return nil }
            return window
        }
        // WindowServer lists mouse-transparent utility overlays too. Accessibility
        // hit testing identifies the actual interactive window below them.
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
            let element
        {
            AXUIElementSetMessagingTimeout(element, 0.1)
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
                    let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                    let bounds = accessibilityBounds(value as! AXUIElement),
                    let window = candidates.first(where: {
                        $0.pid == pid && matching($0.bounds, bounds) && $0.bounds.contains(point)
                    })
                {
                    return [window]
                }
                // Menus may expose an AX top-level element rather than AXWindow.
                let owned = candidates.filter { $0.pid == pid && $0.bounds.contains(point) }
                if !owned.isEmpty { return owned }
            }
        }
        // Without an AX hit, avoid noninteractive background/helper applications.
        return candidates.filter { window in
            guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
            return app.activationPolicy == .regular || window.pid == getpid()
                || (Bundle.main.bundleIdentifier != nil && app.bundleIdentifier == Bundle.main.bundleIdentifier)
        }
    }
    private static func accessibilityBounds(_ window: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(window, 0.1)
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private static func matching(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
            && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
    static func lookup(_ target: InputWindow) -> InputWindow? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, target.id) as? [[String: Any]],
            let window = list.first.flatMap(decode), window.id == target.id, window.pid == target.pid
        else { return nil }
        return window
    }
    static func activate(_ target: InputWindow) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: target.pid) else { return false }
        if target.pid == getpid() {
            let changed = !application.isActive
            NSApplication.shared.window(withWindowNumber: Int(target.id))?.makeKeyAndOrderFront(nil)
            if changed { NSApplication.shared.activate() }
            return changed
        }
        let changed = !application.isActive
        if changed {
            NSApplication.shared.yieldActivation(to: application)
            _ = application.activate(from: .current, options: [])
        }
        // Raise only the touched window, using geometry instead of reading titles.
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        if changed {
            // A real touchscreen press should focus its app even when this
            // menu-bar bridge is in the background and cannot yield foreground focus.
            _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        {
            for window in windows {
                guard let bounds = accessibilityBounds(window), matching(bounds, target.bounds) else { continue }
                _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                break
            }
        }
        return changed
    }
}
