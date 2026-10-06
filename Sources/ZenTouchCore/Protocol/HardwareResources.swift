// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

/// Installed apps must never fall back to resources from a development build.
enum HardwareResources {
    static func data(named name: String, extension suffix: String) -> Data? {
        var container = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<4 {
            if container.pathExtension == "app" {
                return try? Data(contentsOf: container.appendingPathComponent("Contents/Resources/\(name).\(suffix)"))
            }
            container.deleteLastPathComponent()
        }
        guard
            let url = Bundle.main.url(forResource: name, withExtension: suffix)
                ?? Bundle.module.url(forResource: name, withExtension: suffix)
        else { return nil }
        return try? Data(contentsOf: url)
    }
}
