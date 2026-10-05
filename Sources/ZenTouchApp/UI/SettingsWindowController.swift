// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var canStop: Bool { toggle.title == "Stop Touch Input" && toggle.isEnabled }
    private let inputLabel = NSTextField(labelWithString: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let inputButton = NSButton(title: "Allow Input Monitoring", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Allow Accessibility", target: nil, action: nil)
    private let displays = NSPopUpButton()
    private let pinch = NSButton(checkboxWithTitle: "Enable experimental pinch", target: nil, action: nil)
    private let swipes = NSButton(checkboxWithTitle: "Enable three-finger swipes", target: nil, action: nil)
    private let indicators = NSButton(checkboxWithTitle: "Show touch indicators", target: nil, action: nil)
    private let toggle = NSButton(title: "Start Touch Input", target: nil, action: nil)
    private let logs = NSButton(title: "Open Logs Folder", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Ready.")
    private let canvas = TouchCanvas()
    private var targets: [ScreenTarget] = []
    var onToggle: (() -> Void)?
    var onInputSettings: (() -> Void)?
    var onAccessibilitySettings: (() -> Void)?
    var onSelectDisplay: ((ScreenTarget?) -> Void)?
    var onPinchChange: ((Bool) -> Void)?
    var onSwipesChange: ((Bool) -> Void)?
    var onIndicatorsChange: ((Bool) -> Void)?
    var onLogs: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "ZenTouch Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ZenTouchSettingsWindow")
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func buildContent(in window: NSWindow) {
        guard let root = window.contentView else { return }
        let content = NSStackView()
        content.orientation = .vertical
        content.distribution = .fill
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
        ])
        func add(_ view: NSView) {
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let title = NSTextField(labelWithString: AppIdentity.name)
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Multi-touch input for your ZenScreen.")
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        add(heading)
        add(label("Permissions", weight: .semibold))
        inputButton.target = self
        inputButton.action = #selector(allowInput)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(allowAccessibility)
        add(permissionRow(inputLabel, inputButton))
        add(permissionRow(accessibilityLabel, accessibilityButton))
        add(label("Send touch input to", weight: .semibold))
        displays.target = self
        displays.action = #selector(selectDisplay)
        displays.setAccessibilityLabel("Display receiving ZenScreen touch input")
        add(displays)
        swipes.target = self
        swipes.action = #selector(changeSwipes)
        add(swipes)
        let swipeNote = NSTextField(
            wrappingLabelWithString:
                "Left/right: desktops. Up: Mission Control. Down: App Exposé. Uses a private macOS gesture adapter.")
        swipeNote.font = .systemFont(ofSize: 11)
        swipeNote.textColor = .secondaryLabelColor
        add(swipeNote)
        pinch.target = self
        pinch.action = #selector(changePinch)
        add(pinch)
        let pinchNote = NSTextField(
            wrappingLabelWithString: "Pinch uses an experimental adapter. Compatibility varies between apps.")
        pinchNote.font = .systemFont(ofSize: 11)
        pinchNote.textColor = .secondaryLabelColor
        add(pinchNote)
        indicators.target = self
        indicators.action = #selector(changeIndicators)
        add(indicators)
        toggle.target = self
        toggle.action = #selector(toggleInput)
        toggle.bezelStyle = .rounded
        toggle.controlSize = .large
        toggle.font = .systemFont(ofSize: 13, weight: .semibold)
        toggle.contentTintColor = .controlAccentColor
        add(toggle)
        status.font = .systemFont(ofSize: 12)
        status.setAccessibilityRole(.staticText)
        add(status)
        add(canvas)
        canvas.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let footer = NSTextField(
            wrappingLabelWithString:
                "ZenTouch stays in the menu bar when this window closes. Stop pauses input; Quit restores the controller and exits."
        )
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        add(footer)
        logs.target = self
        logs.action = #selector(showLogs)
        content.addArrangedSubview(logs)
        root.layoutSubtreeIfNeeded()
        let compactHeight = content.fittingSize.height + 48
        window.setContentSize(NSSize(width: root.bounds.width, height: compactHeight))
        window.minSize =
            window.frameRect(
                forContentRect: NSRect(x: 0, y: 0, width: 560, height: compactHeight)
            ).size
    }
    private func label(_ title: String, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: weight)
        return label
    }
    private func permissionRow(_ label: NSTextField, _ button: NSButton) -> NSStackView {
        label.font = .systemFont(ofSize: 12)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, button])
        row.spacing = 8
        return row
    }
    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func update(
        state: SessionState, permissions: PermissionState, targets: [ScreenTarget], selected: ScreenTarget?,
        controllerAvailable: Bool, experimentalPinch: Bool, threeFingerSwipes: Bool, showTouchIndicators: Bool,
        inputRequested: Bool,
        message: String
    ) {
        inputLabel.stringValue =
            permissions.inputMonitoring ? "✓ Input Monitoring granted" : "○ Input Monitoring required"
        accessibilityLabel.stringValue =
            permissions.accessibility && permissions.eventPosting
            ? "✓ Accessibility granted" : "○ Accessibility required"
        inputLabel.textColor = permissions.inputMonitoring ? .systemGreen : .secondaryLabelColor
        accessibilityLabel.textColor =
            permissions.accessibility && permissions.eventPosting ? .systemGreen : .secondaryLabelColor
        inputButton.title = permissions.inputMonitoring ? "Open Settings" : "Allow Input Monitoring"
        accessibilityButton.title =
            permissions.accessibility && permissions.eventPosting ? "Open Settings" : "Allow Accessibility"
        let oldTargets = self.targets
        if targets != oldTargets || displays.numberOfItems == 0 {
            self.targets = targets
            displays.removeAllItems()
            displays.addItem(withTitle: "Choose a display…")
            displays.addItems(withTitles: targets.map { $0.name })
        }
        if let selected, let index = targets.firstIndex(of: selected) {
            displays.selectItem(at: index + 1)
        } else {
            displays.selectItem(at: 0)
        }
        displays.isEnabled = !state.isRunning
        pinch.isEnabled = !state.isRunning
        pinch.state = experimentalPinch ? .on : .off
        swipes.isEnabled = !state.isRunning
        swipes.state = threeFingerSwipes ? .on : .off
        indicators.state = showTouchIndicators ? .on : .off
        let canStop = state.isRunning || inputRequested
        toggle.title = canStop ? "Stop Touch Input" : "Start Touch Input"
        toggle.isEnabled = canStop || (permissions.canBridge && selected != nil && controllerAvailable)
        status.stringValue = message
    }
    func updatePreview(frame: TouchFrame) {
        guard window?.isVisible == true else { return }
        canvas.touches = frame.touches
        canvas.setAccessibilityValue("\(frame.touches.count) finger contacts")
    }
    @objc private func toggleInput() { onToggle?() }
    @objc private func allowInput() { onInputSettings?() }
    @objc private func allowAccessibility() { onAccessibilitySettings?() }
    @objc private func selectDisplay() {
        let index = displays.indexOfSelectedItem - 1
        onSelectDisplay?(targets.indices.contains(index) ? targets[index] : nil)
    }
    @objc private func changePinch() { onPinchChange?(pinch.state == .on) }
    @objc private func changeSwipes() { onSwipesChange?(swipes.state == .on) }
    @objc private func changeIndicators() { onIndicatorsChange?(indicators.state == .on) }
    @objc private func showLogs() { onLogs?() }
}
