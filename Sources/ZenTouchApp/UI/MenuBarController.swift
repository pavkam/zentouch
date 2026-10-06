// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchMac

final class MenuBarController: NSObject, NSMenuDelegate {
    var isVisible: Bool { item.isVisible }
    var requestedInputCanBeStopped: Bool { toggle.state == .on && toggle.isEnabled }
    var canStart: Bool { toggle.state == .off && toggle.isEnabled }
    var hasDisconnectedIcon: Bool { item.button?.image === disconnectedIcon }
    private let connectedIcon = MenuBarController.icon("MenuBarTemplate", fallback: "hand.tap")
    private let disconnectedIcon = MenuBarController.icon(
        "MenuBarDisconnectedTemplate", fallback: "display.trianglebadge.exclamationmark")
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggle = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
    private let input = NSMenuItem(title: "Input Monitoring", action: nil, keyEquivalent: "")
    private let accessibility = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
    var onToggle: (() -> Void)?
    var onSettings: (() -> Void)?
    var onInputSettings: (() -> Void)?
    var onAccessibilitySettings: (() -> Void)?
    var onLogs: (() -> Void)?
    var onHelp: (() -> Void)?
    var onRefresh: (() -> Void)?

    override init() {
        super.init()
        item.autosaveName = "ZenTouchStatusItem"
        item.button?.image = disconnectedIcon
        item.button?.setAccessibilityLabel("ZenTouch")
        let menu = NSMenu(title: AppIdentity.name)
        menu.autoenablesItems = false
        menu.delegate = self
        bind(toggle, #selector(toggleInput))
        menu.addItem(toggle)
        menu.addItem(action("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        bind(input, #selector(openInputSettings))
        bind(accessibility, #selector(openAccessibilitySettings))
        menu.addItem(input)
        menu.addItem(accessibility)
        menu.addItem(.separator())
        menu.addItem(action("Open Logs Folder", #selector(showLogs)))
        menu.addItem(action("ZenTouch Help", #selector(showHelp)))
        menu.addItem(action("About ZenTouch", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(action("Quit ZenTouch", #selector(quit), key: "q"))
        item.menu = menu
    }
    private static func icon(_ name: String, fallback: String) -> NSImage? {
        let image =
            Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "ZenTouch")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }
    private func bind(_ item: NSMenuItem, _ selector: Selector) {
        item.target = self
        item.action = selector
    }
    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }
    func update(
        state: SessionState, permissions: PermissionState, targetAvailable: Bool, controllerAvailable: Bool,
        inputRequested: Bool, suspended: Bool = false, unavailableReason: String? = nil
    ) {
        let label: String
        let hardwareAvailable = targetAvailable && controllerAvailable
        if !hardwareAvailable {
            label =
                (unavailableReason ?? "ZenScreen unavailable")
                + (inputRequested ? " Waiting to resume touch input." : "")
        } else if suspended {
            label = "Touch Input Paused"
        } else {
            switch state {
            case .stopped: label = inputRequested ? "Waiting to Resume Touch Input" : "Stopped"
            case .running(.contacts): label = "Testing Contacts"
            case .running(.input): label = "Touch Input Active"
            }
        }
        let icon = hardwareAvailable ? connectedIcon : disconnectedIcon
        if item.button?.image !== icon { item.button?.image = icon }
        item.button?.toolTip = "ZenTouch — \(label)"
        item.button?.setAccessibilityValue(label)
        toggle.state = inputRequested ? .on : .off
        toggle.isEnabled =
            inputRequested || (permissions.canBridge && hardwareAvailable && !suspended)
        input.title = "Input Monitoring\(permissions.inputMonitoring ? " Granted" : " Required")"
        input.state = permissions.inputMonitoring ? .on : .off
        accessibility.title =
            "Accessibility\(permissions.accessibility && permissions.eventPosting ? " Granted" : " Required")"
        accessibility.state = permissions.accessibility && permissions.eventPosting ? .on : .off
    }
    func menuWillOpen(_ menu: NSMenu) { onRefresh?() }
    @objc private func toggleInput() { onToggle?() }
    @objc private func showSettings() { onSettings?() }
    @objc private func openInputSettings() { onInputSettings?() }
    @objc private func openAccessibilitySettings() { onAccessibilitySettings?() }
    @objc private func showLogs() { onLogs?() }
    @objc private func showHelp() { onHelp?() }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppIdentity.name,
            .applicationVersion: AppIdentity.version, .version: "",
            .credits: NSAttributedString(
                string: "Multi-touch input for your ZenScreen.\nMIT License · github.com/pavkam/zentouch"),
        ])
    }
    @objc private func quit() { NSApp.terminate(nil) }
    deinit { NSStatusBar.system.removeStatusItem(item) }
}
