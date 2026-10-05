// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

final class ApplicationController: NSObject, NSApplicationDelegate {
    private let reader = HIDReader()
    private lazy var session = TouchSession(reader: reader)
    private let preferences = AppPreferences()
    private var menuBar: MenuBarController?
    private var settings: SettingsWindowController?
    private var refreshTimer: Timer?
    private var previewTimer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var targets: [ScreenTarget] = []
    private var controllerAvailable = false
    private var message = "Use the menu bar to enable touch input."
    private var lastPermissions: PermissionState?
    private var latestFrame = TouchFrame(scanTime: 0, touches: [])
    private var latestStatistics = ReportStatistics()
    private var suspension: SuspensionReasons = []
    private var suspended: Bool { !suspension.isEmpty }
    private var wantsResume = false
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.record("app.didLaunch", ["presentation": "menuBar"])
        configureSession()
        configureMenuBar()
        configureSignals()
        observeEnvironment()
        let refreshTask = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(refreshTask, forMode: .common)
        refreshTimer = refreshTask
        let preview = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.settings?.updatePreview(frame: self.latestFrame, statistics: self.latestStatistics)
        }
        RunLoop.main.add(preview, forMode: .common)
        previewTimer = preview
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--smoke-test"), args.indices.contains(index + 1) {
            refresh(allowResume: false)
            runSmokeTest(output: URL(fileURLWithPath: args[index + 1]))
            return
        }
        wantsResume = preferences.inputEnabled || args.contains("--enable-input")
        if args.contains("--enable-input") { preferences.inputEnabled = true }
        refresh()
        if args.contains("--test-touch") {
            preferences.inputEnabled = false
            wantsResume = false
            showSettings()
            start(.contacts)
        } else if args.contains("--show-settings") || !PermissionState.current.canBridge {
            showSettings()
        }
    }

    private func configureSession() {
        session.onFrame = { [weak self] frame in self?.latestFrame = frame }
        session.onReport = { [weak self] counts in self?.latestStatistics = counts }
        session.onStatus = { [weak self] message in self?.setMessage(message) }
        session.onState = { [weak self] state in
            guard let self else { return }
            if !state.isRunning { self.wantsResume = false }
            self.updatePresentation()
        }
    }

    private func configureMenuBar() {
        let menu = MenuBarController()
        menu.onToggle = { [weak self] in
            guard let self else { return }
            if self.session.state == .running(.input) {
                self.stop()
            } else {
                if self.session.state.isRunning { self.stop() }
                self.start(.input)
            }
        }
        menu.onTest = { [weak self] in
            guard let self else { return }
            if self.session.state == .running(.contacts) {
                self.stop()
            } else {
                self.showSettings()
                self.start(.contacts)
            }
        }
        menu.onSettings = { [weak self] in self?.showSettings() }
        menu.onInputSettings = { [weak self] in self?.openPrivacy(input: true) }
        menu.onAccessibilitySettings = { [weak self] in self?.openPrivacy(input: false) }
        menu.onLogs = { [weak self] in self?.showLogs() }
        menu.onHelp = { [weak self] in self?.showHelp() }
        menu.onRefresh = { [weak self] in self?.refresh() }
        menuBar = menu
    }

    private func showSettings() {
        if settings == nil {
            let view = SettingsWindowController()
            view.onEnable = { [weak self] in self?.start(.input) }
            view.onTest = { [weak self] in self?.start(.contacts) }
            view.onStop = { [weak self] in self?.stop() }
            view.onInputSettings = { [weak self] in self?.openPrivacy(input: true) }
            view.onAccessibilitySettings = { [weak self] in self?.openPrivacy(input: false) }
            view.onLogs = { [weak self] in self?.showLogs() }
            view.onSelectDisplay = { [weak self] target in
                self?.preferences.displayID = target?.id
                self?.updatePresentation()
            }
            view.onPinchChange = { [weak self] enabled in self?.preferences.experimentalPinch = enabled }
            view.onSwipesChange = { [weak self] enabled in self?.preferences.threeFingerSwipes = enabled }
            settings = view
        }
        updatePresentation()
        settings?.present()
        settings?.updatePreview(frame: latestFrame, statistics: latestStatistics)
    }

    private func start(_ kind: SessionKind) {
        guard !session.state.isRunning, !suspended else { return }
        diagnostics.record("app.start", ["kind": kind.rawValue])
        let target = preferences.selectedTarget(in: targets)
        do {
            try session.start(
                kind: kind, target: target, pinch: preferences.experimentalPinch,
                swipes: preferences.threeFingerSwipes)
            preferences.inputEnabled = kind == .input
            if let target, kind == .input { preferences.displayID = target.id }
            latestStatistics = reader.statistics
            wantsResume = false
            setMessage(
                kind == .input
                    ? "Touch input is active. Tap or drag with one finger; scroll with two; swipe with three."
                    : "Testing finger contacts. This test sends no clicks or scrolling.")
        } catch {
            wantsResume = false
            setMessage(error.localizedDescription)
            diagnostics.record("app.start.error", ["error": error.localizedDescription])
            showSettings()
        }
        updatePresentation()
    }

    private func stop() {
        diagnostics.record("app.click", ["button": "Stop"])
        preferences.inputEnabled = false
        wantsResume = false
        session.stop()
        updatePresentation()
    }

    private func refresh(allowResume: Bool = true) {
        guard !isTerminating else { return }
        targets = ScreenTarget.all
        controllerAvailable = !reader.devices().isEmpty
        let permissions = PermissionState.current
        if permissions != lastPermissions {
            lastPermissions = permissions
            diagnostics.record(
                "app.permissions.changed",
                [
                    "inputMonitoring": permissions.inputMonitoring,
                    "accessibility": permissions.accessibility, "eventPosting": permissions.eventPosting,
                ])
        }
        session.poll()
        if allowResume, wantsResume, !suspended, !session.state.isRunning {
            if permissions.canBridge, controllerAvailable,
                let target = preferences.selectedTarget(in: targets), target.geometry?.supported == true
            {
                start(.input)
            } else {
                setMessage(
                    !permissions.canBridge
                        ? "Allow both permissions to enable touch input."
                        : "Waiting for the selected ZenScreen and its USB touch controller.")
            }
        }
        updatePresentation()
    }

    private func setMessage(_ value: String) {
        if message != value {
            message = value
            diagnostics.record("app.status", ["message": value])
        }
        updatePresentation()
    }
    private func updatePresentation() {
        let permissions = PermissionState.current
        let selected = preferences.selectedTarget(in: targets)
        menuBar?.update(
            state: session.state, permissions: permissions, targetAvailable: selected?.geometry?.supported == true,
            controllerAvailable: controllerAvailable)
        settings?.update(
            state: session.state, permissions: permissions, targets: targets, selected: selected,
            controllerAvailable: controllerAvailable, experimentalPinch: preferences.experimentalPinch,
            threeFingerSwipes: preferences.threeFingerSwipes, message: message
        )
    }
    private func openPrivacy(input: Bool) {
        diagnostics.record("app.permission.request", ["permission": input ? "Input Monitoring" : "Accessibility"])
        if input { PermissionState.requestInputMonitoring() } else { PermissionState.requestAccessibility() }
        let pane = input ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
    private func showLogs() {
        diagnostics.flush()
        NSWorkspace.shared.open(diagnostics.directory)
    }
    private func showHelp() {
        if let url = Bundle.main.url(forResource: "ZenTouchHelp", withExtension: "html") {
            NSWorkspace.shared.open(url)
        }
    }
    private func configureSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }
    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) {
            diagnostics.record("app.activeSpace.changed")
        }
        let pauses: [(Notification.Name, SuspensionReasons)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession),
        ]
        for (name, reason) in pauses {
            observe(workspace, name) { [weak self] in
                guard let self else { return }
                self.suspension.insert(reason)
                self.session.stop(reason: "Touch input paused while the Mac sleeps or locks.")
            }
        }
        let resumes: [(Notification.Name, SuspensionReasons)] = [
            (NSWorkspace.didWakeNotification, .sleep),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession),
        ]
        for (name, reason) in resumes {
            observe(workspace, name) { [weak self] in
                guard let self else { return }
                self.suspension.remove(reason)
                self.wantsResume = self.preferences.inputEnabled
                self.refresh()
            }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationDidBecomeActive(_ notification: Notification) { refresh(allowResume: false) }
    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        refreshTimer?.invalidate()
        previewTimer?.invalidate()
        session.stop(reason: "ZenTouch is quitting.")
        for (center, token) in observers { center.removeObserver(token) }
        for signal in signals { signal.cancel() }
        diagnostics.record("app.cleanup.complete")
        diagnostics.flush()
    }

    /// Inspects only our own view tree and lifecycle, without accessing other apps.
    private func runSmokeTest(output: URL) {
        showSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let window = self.settings?.window, let root = window.contentView else { return }
            root.layoutSubtreeIfNeeded()
            var ambiguous: [String] = []
            var clipped: [String] = []
            var scenario = ""
            func inspect(_ view: NSView) {
                if view.hasAmbiguousLayout { ambiguous.append("\(scenario): \(type(of: view))") }
                if view !== root, !view.isHidden {
                    let frame = view.convert(view.bounds, to: root)
                    if frame.minY < -1 || frame.maxY > root.bounds.height + 1 || frame.minX < -1
                        || frame.maxX > root.bounds.width + 1
                    {
                        clipped.append("\(scenario): \(type(of: view))")
                    }
                }
                view.subviews.forEach(inspect)
            }
            let originalFrame = window.frame
            for (name, size) in [
                ("default", originalFrame.size), ("minimum", window.minSize),
                ("large", NSSize(width: 760, height: 900)),
            ] {
                scenario = name
                window.setFrame(NSRect(origin: originalFrame.origin, size: size), display: true)
                root.layoutSubtreeIfNeeded()
                inspect(root)
            }
            window.setFrame(originalFrame, display: true)
            let report: [String: Any] = [
                "name": AppIdentity.name, "version": AppIdentity.version,
                "bundleID": Bundle.main.bundleIdentifier ?? "",
                "accessory": NSApp.activationPolicy() == .accessory,
                "menuBarPresent": self.menuBar?.isVisible == true, "settingsTitle": window.title,
                "inputMonitoringGranted": PermissionState.current.inputMonitoring,
                "accessibilityGranted": PermissionState.current.accessibility,
                "eventPostingGranted": PermissionState.current.eventPosting,
                "closingWindowKeepsAppRunning": !self.applicationShouldTerminateAfterLastWindowClosed(NSApp),
                "ambiguousViews": ambiguous, "clippedViews": clipped,
                "appIconPresent": Bundle.main.url(forResource: "ZenTouch", withExtension: "icns") != nil,
                "menuIconPresent": Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png") != nil,
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output, options: .atomic)
            } catch { diagnostics.record("app.smoke.error", ["error": error.localizedDescription]) }
            window.close()
            NSApp.terminate(nil)
        }
    }
}
