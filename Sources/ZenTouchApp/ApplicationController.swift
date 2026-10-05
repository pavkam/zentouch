// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

final class ApplicationController: NSObject, NSApplicationDelegate {
    private let reader = HIDReader()
    private lazy var session = TouchSession(reader: reader)
    private let preferences = AppPreferences()
    private let indicators = TouchIndicatorOverlay()
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
    private var latestFrameAt = 0.0
    private var suspension: SuspensionReasons = []
    private var suspended: Bool { !suspension.isEmpty }
    private lazy var recovery = SessionRecovery(session: session)
    private var dockTrace: DockSwipeTrace?
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
            self.settings?.updatePreview(frame: self.latestFrame)
            self.indicators.poll()
        }
        RunLoop.main.add(preview, forMode: .common)
        previewTimer = preview
        let args = CommandLine.arguments
        if args.contains("--show-touch-indicators") { preferences.showTouchIndicators = true }
        if let index = args.firstIndex(of: "--smoke-test"), args.indices.contains(index + 1) {
            refresh(allowResume: false)
            runSmokeTest(output: URL(fileURLWithPath: args[index + 1]))
            return
        }
        if let index = args.firstIndex(of: "--probe-system-gesture"), args.indices.contains(index + 1) {
            refresh(allowResume: false)
            let action: SystemGestureAction = args[index + 1] == "up" ? .missionControl : .appExpose
            do {
                guard ["up", "down"].contains(args[index + 1]), PermissionState.current.canBridge else {
                    throw ZenError(message: "Probe requires up/down and both existing grants.")
                }
                try DockActions.perform(action)
                diagnostics.record("diagnostic.systemGesture.sent", ["action": action.rawValue])
            } catch { diagnostics.record("diagnostic.systemGesture.error", ["error": String(describing: error)]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        recovery.request(preferences.inputEnabled || args.contains("--enable-input"))
        if args.contains("--enable-input") { preferences.inputEnabled = true }
        if args.contains("--trace-dock-swipes") {
            let trace = DockSwipeTrace()
            if trace.start() { dockTrace = trace }
        }
        if args.contains("--test-touch") {
            preferences.inputEnabled = false
            recovery.request(false)
        }
        refresh()
        if args.contains("--test-touch") {
            showSettings()
            start(.contacts)
        } else if args.contains("--show-settings") || !PermissionState.current.canBridge {
            showSettings()
        }
    }

    private func configureSession() {
        session.onFrame = { [weak self] frame in
            self?.latestFrame = frame
            self?.latestFrameAt = ProcessInfo.processInfo.systemUptime
            self?.indicators.update(frame)
        }
        session.onStatus = { [weak self] message in self?.setMessage(message) }
        session.onState = { [weak self] _ in
            guard let self else { return }
            self.updatePresentation()
        }
    }

    private func configureMenuBar() {
        let menu = MenuBarController()
        menu.onToggle = { [weak self] in
            guard let self else { return }
            if self.recovery.requested {
                self.stop()
            } else {
                if self.session.state.isRunning { self.stop() }
                self.start(.input)
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
            view.onToggle = { [weak self] in
                guard let self else { return }
                if self.recovery.requested || self.session.state.isRunning {
                    self.stop()
                } else {
                    self.start(.input)
                }
            }
            view.onInputSettings = { [weak self] in self?.openPrivacy(input: true) }
            view.onAccessibilitySettings = { [weak self] in self?.openPrivacy(input: false) }
            view.onLogs = { [weak self] in self?.showLogs() }
            view.onSelectDisplay = { [weak self] target in
                self?.preferences.select(target)
                self?.updatePresentation()
            }
            view.onPinchChange = { [weak self] enabled in self?.preferences.experimentalPinch = enabled }
            view.onSwipesChange = { [weak self] enabled in self?.preferences.threeFingerSwipes = enabled }
            view.onIndicatorsChange = { [weak self] enabled in
                guard let self else { return }
                self.preferences.showTouchIndicators = enabled
                diagnostics.record("app.touchIndicators.changed", ["enabled": enabled])
                self.updatePresentation()
                if enabled, ProcessInfo.processInfo.systemUptime - self.latestFrameAt < 0.25 {
                    self.indicators.update(self.latestFrame)
                }
            }
            settings = view
        }
        updatePresentation()
        settings?.present()
        settings?.updatePreview(frame: latestFrame)
    }

    private func start(_ kind: SessionKind) {
        guard !session.state.isRunning, !suspended else { return }
        diagnostics.record("app.start", ["kind": kind.rawValue])
        let target = preferences.selectedTarget(in: targets)
        preferences.inputEnabled = kind == .input
        recovery.request(kind == .input)
        do {
            if kind == .input {
                try recovery.startInput(
                    target: target, pinch: preferences.experimentalPinch,
                    swipes: preferences.threeFingerSwipes)
                if let target { preferences.select(target) }
            } else {
                try session.start(kind: kind, target: target)
            }
            setMessage(
                kind == .input
                    ? "Touch input is active. Tap or drag with one finger; scroll with two; swipe with three."
                    : "Testing finger contacts. This test sends no clicks or scrolling.")
        } catch {
            setMessage(error.localizedDescription)
            diagnostics.record("app.start.error", ["error": error.localizedDescription])
            showSettings()
        }
        updatePresentation()
    }

    private func stop() {
        diagnostics.record("app.click", ["button": "Stop"])
        preferences.inputEnabled = false
        recovery.request(false)
        let wasRunning = session.state.isRunning
        session.stop()
        if !wasRunning { setMessage("Touch input stopped. Automatic resuming is disabled.") }
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
        let target = preferences.selectedTarget(in: targets)
        if allowResume {
            let result = recovery.refresh(
                available: permissions.canBridge && controllerAvailable && target?.geometry?.supported == true,
                suspended: suspended, target: target, pinch: preferences.experimentalPinch,
                swipes: preferences.threeFingerSwipes)
            switch result {
            case .idle: break
            case .waiting:
                setMessage(
                    !permissions.canBridge
                        ? "Allow both permissions to enable touch input."
                        : "Waiting for the selected ZenScreen and its USB touch controller.")
            case .started:
                if let target { preferences.select(target) }
                diagnostics.record("app.input.resumed")
                setMessage("Touch input resumed automatically.")
            case .failed(let error):
                diagnostics.record("app.input.retry", ["error": error])
                setMessage(error)
            }
        } else {
            session.poll()
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
        indicators.configure(
            enabled: preferences.showTouchIndicators, target: selected, active: session.state == .running(.input))
        menuBar?.update(
            state: session.state, permissions: permissions, targetAvailable: selected?.geometry?.supported == true,
            controllerAvailable: controllerAvailable, inputRequested: recovery.requested)
        settings?.update(
            state: session.state, permissions: permissions, targets: targets, selected: selected,
            controllerAvailable: controllerAvailable, experimentalPinch: preferences.experimentalPinch,
            threeFingerSwipes: preferences.threeFingerSwipes, showTouchIndicators: preferences.showTouchIndicators,
            inputRequested: recovery.requested, message: message
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
            (NSWorkspace.screensDidSleepNotification, .displaySleep),
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
            (NSWorkspace.screensDidWakeNotification, .displaySleep),
        ]
        for (name, reason) in resumes {
            observe(workspace, name) { [weak self] in
                guard let self else { return }
                self.suspension.remove(reason)
                if reason == .displaySleep {
                    // Reapply multi-touch mode even if USB stayed enumerated
                    // while the monitor's firmware powered its controller down.
                    self.session.stop(reason: "Reinitializing touch input after display wake.")
                }
                self.recovery.request(self.preferences.inputEnabled)
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
        indicators.stop()
        dockTrace?.stop()
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
            var bottomPadding: [String: CGFloat] = [:]
            var scenario = ""
            func inspect(_ view: NSView) {
                if view.hasAmbiguousLayout { ambiguous.append("\(scenario): \(type(of: view))") }
                if view !== root, !view.isHidden {
                    let frame = view.convert(view.bounds, to: root)
                    if let button = view as? NSButton, button.title == "Open Logs Folder" {
                        bottomPadding[scenario] = root.isFlipped ? root.bounds.height - frame.maxY : frame.minY
                    }
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
            var overlayChecks: [String: Bool] = [:]
            if let target = self.preferences.selectedTarget(in: ScreenTarget.all) {
                var clock = 0.0
                let overlay = TouchIndicatorOverlay(now: { clock })
                let keyWindow = NSApp.keyWindow
                overlay.configure(enabled: true, target: target, active: true)
                overlay.update(
                    TouchFrame(
                        scanTime: 1,
                        touches: [
                            Touch(id: 1, x: 0.25, y: 0.35), Touch(id: 2, x: 0.7, y: 0.65),
                        ]))
                overlayChecks["visibleForTwoContacts"] = overlay.isVisible && overlay.indicatorCount == 2
                overlayChecks["mouseTransparentAndNonactivating"] =
                    overlay.isNonInteractive
                    && NSApp.keyWindow === keyWindow
                overlayChecks["respectsReduceMotion"] =
                    overlay.pulseCount
                    == (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 2)
                do {
                    try overlay.writePreview(to: output.deletingPathExtension().appendingPathExtension("png"))
                    overlayChecks["renderedPreview"] = true
                } catch { overlayChecks["renderedPreview"] = false }
                overlay.update(TouchFrame(scanTime: 2, touches: [Touch(id: 2, x: 0.5, y: 0.5)]))
                overlayChecks["removesLiftedFinger"] = overlay.indicatorCount == 1 && overlay.positions[1] == nil
                overlay.update(TouchFrame(scanTime: 3, touches: []))
                overlayChecks["hidesOnLift"] = !overlay.isVisible && overlay.indicatorCount == 0
                overlay.update(TouchFrame(scanTime: 4, touches: [Touch(id: 1, x: 0.5, y: 0.5)]))
                clock = 2.1
                overlay.poll()
                overlayChecks["clearsStalledContacts"] = !overlay.isVisible && overlay.indicatorCount == 0
                overlay.update(TouchFrame(scanTime: 5, touches: [Touch(id: 1, x: 0.5, y: 0.5)]))
                overlay.update(TouchFrame(scanTime: 6, touches: [Touch(id: 1, x: .nan, y: 0.5)]))
                overlayChecks["rejectsInvalidCoordinates"] = !overlay.isVisible && overlay.indicatorCount == 0
                overlay.update(TouchFrame(scanTime: 7, touches: [Touch(id: 1, x: 0.5, y: 0.5)]))
                overlay.configure(enabled: false, target: target, active: true)
                overlayChecks["clearsWhenDisabled"] = !overlay.isVisible && overlay.indicatorCount == 0
                overlay.configure(enabled: true, target: target, active: true)
                overlay.update(TouchFrame(scanTime: 8, touches: [Touch(id: 1, x: 0.5, y: 0.5)]))
                overlay.configure(enabled: true, target: target, active: false)
                overlayChecks["clearsWhenStopped"] = !overlay.isVisible && overlay.indicatorCount == 0
            }
            // A paused/absent controller must not trap the user in auto-resume.
            self.menuBar?.update(
                state: .stopped, permissions: .current, targetAvailable: false,
                controllerAvailable: false, inputRequested: true)
            self.settings?.update(
                state: .stopped, permissions: .current, targets: [], selected: nil,
                controllerAvailable: false, experimentalPinch: false, threeFingerSwipes: true,
                showTouchIndicators: false,
                inputRequested: true, message: "Waiting for the controller.")
            let report: [String: Any] = [
                "name": AppIdentity.name, "version": AppIdentity.version,
                "bundleID": Bundle.main.bundleIdentifier ?? "",
                "accessory": NSApp.activationPolicy() == .accessory,
                "menuBarPresent": self.menuBar?.isVisible == true, "settingsTitle": window.title,
                "inputMonitoringGranted": PermissionState.current.inputMonitoring,
                "accessibilityGranted": PermissionState.current.accessibility,
                "eventPostingGranted": PermissionState.current.eventPosting,
                "closingWindowKeepsAppRunning": !self.applicationShouldTerminateAfterLastWindowClosed(NSApp),
                "waitingInputCanBeStopped": self.menuBar?.requestedInputCanBeStopped == true
                    && self.settings?.canStop == true,
                "ambiguousViews": ambiguous, "clippedViews": clipped,
                "contentBottomPadding": bottomPadding,
                "touchIndicatorChecks": overlayChecks,
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
