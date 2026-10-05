// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

public enum DeviceProfile {
    public static let vendorID = 0x0eef
    public static let productID = 0xc000
    public static let productPrefix = "eGalaxTouch EXC3200-2505"
    public static let descriptor: Data? = {
        // Packaged from the live IORegistry, not inferred from a related model.
        // The GUI and nested CLI must both work without the SwiftPM build folder.
        var container = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<4 {
            if container.pathExtension == "app" {
                let url = container.appendingPathComponent("Contents/Resources/exc3200-descriptor.bin")
                return try? Data(contentsOf: url)
            }
            container.deleteLastPathComponent()
        }
        guard
            let url = Bundle.main.url(forResource: "exc3200-descriptor", withExtension: "bin")
                ?? Bundle.module.url(forResource: "exc3200-descriptor", withExtension: "bin")
        else { return nil }
        return try? Data(contentsOf: url)
    }()
}
