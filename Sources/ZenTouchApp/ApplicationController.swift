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
    private var environmentRefreshScheduled = false
    private var pendingEnvironmentReasons: Set<String> = []
    private var environmentRefreshCounts: [String: Int] = [:]
    private var lastHardwareState: String?

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
        reader.onDevicesChanged = { [weak self] in self?.scheduleEnvironmentRefresh(reason: "touchController") }
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
        controllerAvailable = reader.hasSupportedController
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
                available: ModelCatalog.current != nil && permissions.canBridge && controllerAvailable
                    && target?.geometry?.supported == true,
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

    private func scheduleEnvironmentRefresh(reason: String) {
        guard !isTerminating else { return }
        pendingEnvironmentReasons.insert(reason)
        guard !environmentRefreshScheduled else { return }
        environmentRefreshScheduled = true
        // Let AppKit/HID finish updating their snapshots before enumerating.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTerminating else { return }
            self.environmentRefreshScheduled = false
            let reasons = self.pendingEnvironmentReasons.sorted()
            self.pendingEnvironmentReasons.removeAll()
            for reason in reasons { self.environmentRefreshCounts[reason, default: 0] += 1 }
            diagnostics.record("app.environment.changed", ["reasons": reasons])
            self.refresh()
        }
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
        let geometry = selected?.geometry
        let targetAvailable = ModelCatalog.current != nil && geometry?.supported == true
        let hardwareState: String
        let unavailableReason: String?
        if ModelCatalog.current == nil {
            hardwareState = "catalogUnavailable"
            unavailableReason = "ZenTouch's model catalog is missing or invalid. Reinstall the app."
        } else if selected == nil {
            hardwareState = "displayMissing"
            unavailableReason =
                preferences.displayID != nil
                ? "The selected ZenScreen display is not connected."
                : "Connect your ZenScreen and select its display."
        } else if geometry == nil {
            hardwareState = "displayUnavailable"
            unavailableReason = "The selected display is asleep or disconnected."
        } else if !targetAvailable {
            hardwareState = "displayUnsupported"
            unavailableReason = "Set the selected display to 0° rotation before enabling touch input."
        } else if !controllerAvailable {
            hardwareState = "controllerMissing"
            unavailableReason = "No supported USB touch controller is connected."
        } else {
            hardwareState = "available"
            unavailableReason = nil
        }
        if hardwareState != lastHardwareState {
            lastHardwareState = hardwareState
            diagnostics.record(
                "app.hardware.changed",
                [
                    "state": hardwareState, "displayID": selected?.id ?? 0,
                    "displayAvailable": targetAvailable, "controllerAvailable": controllerAvailable,
                ])
        }
        indicators.configure(
            enabled: preferences.showTouchIndicators, target: selected, active: session.state == .running(.input))
        menuBar?.update(
            state: session.state, permissions: permissions, targetAvailable: targetAvailable,
            controllerAvailable: controllerAvailable, inputRequested: recovery.requested,
            suspended: suspended, unavailableReason: unavailableReason)
        settings?.update(
            state: session.state, permissions: permissions, targets: targets, selected: selected,
            controllerAvailable: controllerAvailable, experimentalPinch: preferences.experimentalPinch,
            threeFingerSwipes: preferences.threeFingerSwipes, showTouchIndicators: preferences.showTouchIndicators,
            inputRequested: recovery.requested, targetAvailable: targetAvailable, suspended: suspended,
            message: unavailableReason ?? message
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
                self.updatePresentation()
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
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.scheduleEnvironmentRefresh(reason: "displays")
        }
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
        let previousScreenRefreshes = environmentRefreshCounts["displays", default: 0]
        let previousControllerRefreshes = environmentRefreshCounts["touchController", default: 0]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        reader.onDevicesChanged?()
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
            var hardwareChecks: [String: Bool] = [:]
            hardwareChecks["modelCatalogAvailable"] = ModelCatalog.current?.supportedModels.isEmpty == false
            let testTarget = ScreenTarget(
                id: 0, name: ModelCatalog.current?.supportedModels.first?.model ?? "Synthetic Touch Display")
            let granted = PermissionState(inputMonitoring: true, accessibility: true, eventPosting: true)
            func presentHardware(
                display: Bool, controller: Bool, requested: Bool = false,
                state: SessionState = .stopped, permissions: PermissionState? = nil, suspended: Bool = false
            ) {
                self.menuBar?.update(
                    state: state, permissions: permissions ?? granted, targetAvailable: display,
                    controllerAvailable: controller, inputRequested: requested, suspended: suspended)
                self.settings?.update(
                    state: state, permissions: permissions ?? granted,
                    targets: display ? [testTarget] : [ScreenTarget(id: 1, name: "Built-in Retina Display")],
                    selected: display ? testTarget : nil, controllerAvailable: controller,
                    experimentalPinch: false, threeFingerSwipes: true, showTouchIndicators: true,
                    inputRequested: requested, targetAvailable: display, suspended: suspended,
                    message: "Hardware state check.")
            }
            func touchOptionsDisabled() -> Bool {
                self.settings?.displaySelectionEnabled == false && self.settings?.gestureOptionsEnabled == false
                    && self.settings?.touchIndicatorsEnabled == false
            }
            presentHardware(display: false, controller: false)
            hardwareChecks["disconnectedIconAndDisabledControls"] =
                self.menuBar?.hasDisconnectedIcon == true
                && self.menuBar?.canStart == false && self.settings?.canStart == false && touchOptionsDisabled()
            presentHardware(display: true, controller: false)
            hardwareChecks["displayWithoutUSBIsUnavailable"] =
                self.menuBar?.hasDisconnectedIcon == true
                && self.menuBar?.canStart == false && self.settings?.canStart == false && touchOptionsDisabled()
            presentHardware(display: false, controller: true)
            hardwareChecks["USBWithoutSelectedDisplayIsUnavailable"] =
                self.menuBar?.hasDisconnectedIcon == true
                && self.menuBar?.canStart == false && self.settings?.canStart == false && touchOptionsDisabled()
            presentHardware(display: true, controller: true)
            hardwareChecks["reattachRestoresIconAndControls"] =
                self.menuBar?.hasDisconnectedIcon == false
                && self.menuBar?.canStart == true && self.settings?.canStart == true
                && self.settings?.displaySelectionEnabled == true && self.settings?.gestureOptionsEnabled == true
                && self.settings?.touchIndicatorsEnabled == true
            presentHardware(display: true, controller: true, requested: true, state: .running(.input))
            hardwareChecks["runningKeepsLiveIndicatorToggle"] =
                self.menuBar?.hasDisconnectedIcon == false
                && self.menuBar?.requestedInputCanBeStopped == true && self.settings?.canStop == true
                && self.settings?.displaySelectionEnabled == false && self.settings?.gestureOptionsEnabled == false
                && self.settings?.touchIndicatorsEnabled == true
            let denied = PermissionState(inputMonitoring: false, accessibility: false, eventPosting: false)
            presentHardware(display: true, controller: true, permissions: denied)
            hardwareChecks["connectedStartStillRequiresPermissions"] =
                self.menuBar?.hasDisconnectedIcon == false
                && self.menuBar?.canStart == false && self.settings?.canStart == false
            presentHardware(display: true, controller: true, suspended: true)
            hardwareChecks["sleepDisablesStartAndTouchOptions"] =
                self.menuBar?.canStart == false
                && self.settings?.canStart == false && touchOptionsDisabled()
            presentHardware(display: false, controller: false, requested: true)
            hardwareChecks["detachPreservesStopWhileDisablingTouchOptions"] =
                self.menuBar?.hasDisconnectedIcon == true
                && self.menuBar?.requestedInputCanBeStopped == true && self.settings?.canStop == true
                && touchOptionsDisabled()
            hardwareChecks["displayNotificationRefreshes"] =
                self.environmentRefreshCounts["displays", default: 0]
                > previousScreenRefreshes
            hardwareChecks["controllerNotificationRefreshes"] =
                self.environmentRefreshCounts["touchController", default: 0]
                > previousControllerRefreshes
            var overlayChecks: [String: Bool] = [:]
            // Synthetic rendering can use an awake display without a ZenScreen.
            // Production indicators still require the selected input session.
            if let target = self.preferences.selectedTarget(in: ScreenTarget.all).flatMap({
                $0.geometry?.supported == true ? $0 : nil
            }) ?? ScreenTarget.all.first(where: { $0.geometry?.supported == true }) {
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
                inputRequested: true, targetAvailable: false, message: "Waiting for the controller.")
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
                "hardwareAvailabilityChecks": hardwareChecks,
                "appIconPresent": Bundle.main.url(forResource: "ZenTouch", withExtension: "icns") != nil,
                "menuIconPresent": Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png") != nil,
                "disconnectedMenuIconPresent": Bundle.main.url(
                    forResource: "MenuBarDisconnectedTemplate", withExtension: "png") != nil,
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
