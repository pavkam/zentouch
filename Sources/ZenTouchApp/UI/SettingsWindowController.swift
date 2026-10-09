// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var loginOptionAvailable: Bool { login.isEnabled }
    var loginOptionState: NSControl.StateValue { login.state }
    var loginApprovalVisible: Bool { !loginSettings.isHidden }
    var loginNoteText: String { loginNote.stringValue }
    var canStop: Bool { toggle.state == .on && toggle.isEnabled }
    var canStart: Bool { toggle.state == .off && toggle.isEnabled }
    var displaySelectionEnabled: Bool { displays.isEnabled }
    var gestureOptionsEnabled: Bool { cards.values.allSatisfy { $0.toggle.isEnabled } }
    var pointerOptionEnabled: Bool { stationary.isEnabled }
    var touchIndicatorsEnabled: Bool { indicators.isEnabled }
    var selectedTab: Int { sections.selectedSegment }
    var animationIsActive: Bool {
        animationTimer != nil
    }
    private let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginSettings = NSButton(title: "Open Login Items", target: nil, action: nil)
    private let loginNote = NSTextField(wrappingLabelWithString: "Starts in the menu bar when you sign in.")
    private var loginStatus = LoginItemStatus.disabled
    private let inputLabel = NSTextField(labelWithString: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let inputButton = NSButton(title: "Allow Input Monitoring", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Allow Accessibility", target: nil, action: nil)
    private let displays = NSPopUpButton()
    private let stationary = NSButton(checkboxWithTitle: "Keep pointer stationary", target: nil, action: nil)
    private let indicators = NSButton(checkboxWithTitle: "Show touch indicators", target: nil, action: nil)
    private let toggle = NSButton(checkboxWithTitle: "Active", target: nil, action: nil)
    private let logs = NSButton(title: "Open Logs Folder", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Ready.")
    private let canvas = TouchCanvas()
    private let tabs = NSView()
    private var panels: [NSView] = []
    private let sections = NSSegmentedControl(
        labels: ["Touch", "Gestures", "App"], trackingMode: .selectOne, target: nil, action: nil)
    private var cards: [GestureFeature: GestureCard] = [:]
    private var animationTimer: Timer?
    private var motionObserver: NSObjectProtocol?
    private var targets: [ScreenTarget] = []
    var onLoginChange: ((Bool) -> Void)?
    var onLoginSettings: (() -> Void)?
    var onToggle: (() -> Void)?
    var onInputSettings: (() -> Void)?
    var onAccessibilitySettings: (() -> Void)?
    var onSelectDisplay: ((ScreenTarget?) -> Void)?
    var onPointerChange: ((Bool) -> Void)?
    var onGestureChange: ((GestureFeature, Bool) -> Void)?
    var onIndicatorsChange: ((Bool) -> Void)?
    var onLogs: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 770),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ZenTouch Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ZenTouchSettingsWindowV3")
        window.setContentSize(NSSize(width: 760, height: 770))
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
        window.center()
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateAnimationTimer() }
    }

    required init?(coder: NSCoder) { nil }
    deinit {
        animationTimer?.invalidate()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }
    private func updateAnimationTimer() {
        let animate =
            window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && selectedTab == 1 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animate else {
            animationTimer?.invalidate()
            animationTimer = nil
            setAnimationProgress(0.35)
            return
        }
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.setAnimationProgress(ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 3) / 3)
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateAnimationTimer() }
    func windowWillClose(_ notification: Notification) {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func text(_ value: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false)
        -> NSTextField
    {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    private func stack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let view = NSStackView(views: views)
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = spacing
        for child in views { child.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true }
        return view
    }
    private func buildContent(in window: NSWindow) {
        guard let root = window.contentView else { return }
        let title = text(AppIdentity.name, size: 23, weight: .semibold)
        let subtitle = text("Your screen. Your gestures.", secondary: true)
        let heading = stack([title, subtitle], spacing: 3)
        title.heightAnchor.constraint(equalToConstant: 27).isActive = true
        subtitle.heightAnchor.constraint(equalToConstant: 16).isActive = true
        heading.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let image = NSImageView()
        image.image = Bundle.main.url(forResource: "ZenTouch", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        image.widthAnchor.constraint(equalToConstant: 42).isActive = true
        image.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        heading.widthAnchor.constraint(equalToConstant: 220).isActive = true
        heading.setContentHuggingPriority(.required, for: .vertical)
        toggle.target = self
        toggle.action = #selector(toggleInput)
        toggle.controlSize = .large
        toggle.font = .systemFont(ofSize: 13, weight: .semibold)
        toggle.contentTintColor = .controlAccentColor
        let header = NSStackView(views: [image, heading, spacer, toggle])
        header.spacing = 12
        header.alignment = .centerY
        header.heightAnchor.constraint(equalToConstant: 46).isActive = true
        sections.target = self
        sections.action = #selector(changeSection)
        sections.selectedSegment = 0
        sections.segmentStyle = .rounded
        sections.setAccessibilityLabel("Settings section")
        sections.segmentDistribution = .fillEqually
        panels = [touchPanel(), gesturePanel(), appPanel()]
        for (index, panel) in panels.enumerated() {
            panel.translatesAutoresizingMaskIntoConstraints = false
            tabs.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
                panel.topAnchor.constraint(equalTo: tabs.topAnchor),
                panel.bottomAnchor.constraint(equalTo: tabs.bottomAnchor),
            ])
            panel.isHidden = index != 0
        }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        logs.target = self
        logs.action = #selector(showLogs)
        logs.controlSize = .small
        logs.setContentHuggingPriority(.required, for: .horizontal)
        let footer = NSStackView(views: [status, logs])
        footer.spacing = 16
        footer.alignment = .bottom
        footer.setContentHuggingPriority(.required, for: .vertical)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        logs.trailingAnchor.constraint(equalTo: footer.trailingAnchor).isActive = true
        for view in [header, sections, tabs, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            sections.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            sections.heightAnchor.constraint(equalToConstant: 28),
            tabs.topAnchor.constraint(equalTo: sections.bottomAnchor, constant: 20),
            tabs.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.heightAnchor.constraint(equalToConstant: 28),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
    }

    private func touchPanel() -> NSView {
        displays.target = self
        displays.action = #selector(selectDisplay)
        displays.setAccessibilityLabel("Display receiving ZenScreen touch input")
        stationary.target = self
        stationary.action = #selector(changePointer)
        indicators.target = self
        indicators.action = #selector(changeIndicators)
        let filler = NSView()
        let panel = stack([
            text("Touch surface", size: 16, weight: .semibold),
            text("Choose the display that should receive your touches.", secondary: true),
            displays, canvas,
            stationary,
            text(
                "Send touches to the window under your finger while the mouse stays put. Some desktop and menu controls may not respond.",
                size: 11, secondary: true),
            indicators,
            text(
                "Soft rings follow your fingers on the screen. Closing Settings keeps touch input running.", size: 11,
                secondary: true), filler,
        ])
        filler.heightAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        canvas.heightAnchor.constraint(equalToConstant: 200).isActive = true
        return panel
    }
    private func gesturePanel() -> NSView {
        var rows: [NSView] = [
            text("Make touch your own", size: 16, weight: .semibold),
            text("Choose what each gesture does. Changes take effect after you lift your fingers.", secondary: true),
        ]
        let features = GestureFeature.allCases
        for index in stride(from: 0, to: features.count, by: 2) {
            let pair = features[index..<min(index + 2, features.count)].map { feature in
                let card = GestureCard(feature: feature)
                card.onChange = { [weak self] feature, enabled in self?.onGestureChange?(feature, enabled) }
                cards[feature] = card
                return card
            }
            let row = NSStackView(views: pair)
            row.distribution = .fillEqually
            row.spacing = 12
            rows.append(row)
        }
        rows.append(NSView())
        return stack(rows)
    }
    private func permissionRow(_ label: NSTextField, _ button: NSButton) -> NSStackView {
        label.font = .systemFont(ofSize: 12)
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, button])
        row.spacing = 12
        return row
    }
    private func appPanel() -> NSView {
        login.target = self
        login.action = #selector(changeLogin)
        login.allowsMixedState = true
        loginSettings.target = self
        loginSettings.action = #selector(openLoginSettings)
        loginSettings.isHidden = true
        loginNote.font = .systemFont(ofSize: 11)
        loginNote.textColor = .secondaryLabelColor
        inputButton.target = self
        inputButton.action = #selector(allowInput)
        accessibilityButton.target = self
        accessibilityButton.action = #selector(allowAccessibility)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let panel = stack(
            [
                text("At home in the menu bar", size: 16, weight: .semibold),
                NSStackView(views: [login, loginSettings]), loginNote,
                text("Permissions", size: 14, weight: .semibold),
                text("Allow ZenTouch to read your touchscreen and send input to your Mac.", secondary: true),
                permissionRow(inputLabel, inputButton), permissionRow(accessibilityLabel, accessibilityButton),
                text(
                    "Uncheck Active to pause touch input. Quit restores the controller and closes ZenTouch.", size: 11,
                    secondary: true),
                spacer,
            ], spacing: 16)
        return panel
    }
    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateAnimationTimer()
    }
    func selectTab(_ index: Int) {
        guard (0..<3).contains(index) else { return }
        sections.selectedSegment = index
        for (offset, panel) in panels.enumerated() { panel.isHidden = offset != index }
        updateAnimationTimer()
    }
    func gestureState(_ feature: GestureFeature) -> NSControl.StateValue? { cards[feature]?.toggle.state }
    func setAnimationProgress(_ value: Double) { for card in cards.values { card.preview.progress = value } }
    func update(
        state: SessionState, permissions: PermissionState, targets: [ScreenTarget], selected: ScreenTarget?,
        controllerAvailable: Bool, experimentalPinch: Bool, threeFingerSwipes: Bool, showTouchIndicators: Bool,
        keepPointerStationary: Bool = false, gestureOptions: GestureOptions? = nil,
        inputRequested: Bool, targetAvailable: Bool, suspended: Bool = false, message: String
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
        if targets != self.targets || displays.numberOfItems == 0 {
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
        let hardwareAvailable = targetAvailable && controllerAvailable
        displays.isEnabled =
            !state.isRunning && controllerAvailable && !suspended
            && (targetAvailable || targets.contains(where: { $0.isSupportedTouchDisplay }))
        stationary.state = keepPointerStationary ? .on : .off
        stationary.isEnabled = !state.isRunning && hardwareAvailable && !suspended
        let options =
            gestureOptions
            ?? GestureOptions(
                pinch: experimentalPinch, desktops: threeFingerSwipes, missionControl: threeFingerSwipes,
                appExpose: threeFingerSwipes)
        for (feature, card) in cards {
            card.update(enabled: options[feature], available: hardwareAvailable && !suspended)
        }
        indicators.state = showTouchIndicators ? .on : .off
        indicators.isEnabled = hardwareAvailable && !suspended
        let canStop = state.isRunning || inputRequested
        toggle.state = canStop ? .on : .off
        toggle.isEnabled = canStop || (permissions.canBridge && hardwareAvailable && !suspended)
        status.stringValue = message
    }
    func updatePreview(frame: TouchFrame) {
        guard window?.isVisible == true else { return }
        canvas.touches = frame.touches
        canvas.setAccessibilityValue("\(frame.touches.count) finger contacts")
    }
    func updateLoginItem(status: LoginItemStatus, error: String? = nil) {
        loginStatus = status
        login.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        login.isEnabled = status != .unavailable
        loginSettings.isHidden = status != .requiresApproval
        loginNote.textColor = error == nil ? .secondaryLabelColor : .systemRed
        if let error {
            loginNote.stringValue = "Couldn’t update launch at login: \(error)"
        } else {
            switch status {
            case .enabled, .disabled:
                loginNote.stringValue =
                    "Starts in the menu bar when you sign in. Previously active touch input resumes."
            case .requiresApproval:
                loginNote.stringValue = "Waiting for approval in System Settings → General → Login Items."
            case .unavailable: loginNote.stringValue = "Install ZenTouch in Applications to enable launch at login."
            }
        }
    }
    @objc private func changeSection() { selectTab(sections.selectedSegment) }
    @objc private func changeLogin() { onLoginChange?(loginStatus == .disabled) }
    @objc private func openLoginSettings() { onLoginSettings?() }
    @objc private func toggleInput() { onToggle?() }
    @objc private func allowInput() { onInputSettings?() }
    @objc private func allowAccessibility() { onAccessibilitySettings?() }
    @objc private func selectDisplay() {
        let index = displays.indexOfSelectedItem - 1
        onSelectDisplay?(targets.indices.contains(index) ? targets[index] : nil)
    }
    @objc private func changePointer() { onPointerChange?(stationary.state == .on) }
    @objc private func changeIndicators() { onIndicatorsChange?(indicators.state == .on) }
    @objc private func showLogs() { onLogs?() }
}
