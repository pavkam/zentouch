// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore
import ZenTouchMac

let diagnostics = DiagnosticLog.shared

enum AppIdentity {
    static let name = "ZenTouch"
    static let bundleID = "org.pavkam.zentouch"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}

@main
struct ZenTouchApp {
    static func main() {
        if CommandLine.arguments.contains("--version") {
            print("ZenTouch \(AppIdentity.version)")
            return
        }
        diagnostics.record(
            "process.start",
            [
                "mode": "menuBar", "bundle": Bundle.main.bundleIdentifier ?? "development",
                "version": AppIdentity.version, "log": diagnostics.fileURL.path,
            ])
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = ApplicationController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
