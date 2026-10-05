// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchMac

final class MenuBarController: NSObject, NSMenuDelegate {
    var isVisible: Bool { item.isVisible }
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggle = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
    private let test = NSMenuItem(title: "Test Finger Contacts…", action: nil, keyEquivalent: "")
    private let input = NSMenuItem(title: "Input Monitoring", action: nil, keyEquivalent: "")
    private let accessibility = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
    var onToggle: (() -> Void)?
    var onTest: (() -> Void)?
    var onSettings: (() -> Void)?
    var onInputSettings: (() -> Void)?
    var onAccessibilitySettings: (() -> Void)?
    var onLogs: (() -> Void)?
    var onHelp: (() -> Void)?
    var onRefresh: (() -> Void)?

    override init() {
        super.init()
        item.autosaveName = "ZenTouchStatusItem"
        if let imageURL = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png"),
            let image = NSImage(contentsOf: imageURL)
        {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
        } else {
            item.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "ZenTouch")
        }
        item.button?.setAccessibilityLabel("ZenTouch")
        let menu = NSMenu(title: AppIdentity.name)
        menu.autoenablesItems = false
        menu.delegate = self
        bind(toggle, #selector(toggleInput))
        bind(test, #selector(testContacts))
        menu.addItem(toggle)
        menu.addItem(test)
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
    private func bind(_ item: NSMenuItem, _ selector: Selector) {
        item.target = self
        item.action = selector
    }
    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }
    func update(state: SessionState, permissions: PermissionState, targetAvailable: Bool, controllerAvailable: Bool) {
        let label: String
        switch state {
        case .stopped: label = "Stopped"
        case .running(.contacts): label = "Testing Contacts"
        case .running(.input): label = "Touch Input Active"
        }
        item.button?.toolTip = "ZenTouch — \(label)"
        toggle.state = state == .running(.input) ? .on : .off
        toggle.isEnabled =
            state == .running(.input) || (permissions.canBridge && targetAvailable && controllerAvailable)
        test.state = state == .running(.contacts) ? .on : .off
        test.isEnabled =
            state == .running(.contacts) || (!state.isRunning && permissions.inputMonitoring && controllerAvailable)
        input.title = "Input Monitoring\(permissions.inputMonitoring ? " Granted" : " Required")"
        input.state = permissions.inputMonitoring ? .on : .off
        accessibility.title =
            "Accessibility\(permissions.accessibility && permissions.eventPosting ? " Granted" : " Required")"
        accessibility.state = permissions.accessibility && permissions.eventPosting ? .on : .off
    }
    func menuWillOpen(_ menu: NSMenu) { onRefresh?() }
    @objc private func toggleInput() { onToggle?() }
    @objc private func testContacts() { onTest?() }
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
