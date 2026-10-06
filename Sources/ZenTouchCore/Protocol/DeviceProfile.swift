// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

public enum DeviceProfile {
    public static let identifier = "exc3200-2505"
    public static let vendorID = 0x0eef
    public static let productID = 0xc000
    public static let productPrefix = "eGalaxTouch EXC3200-2505"
    // Captured from the live controller, not inferred from a model name.
    public static let descriptor = HardwareResources.data(named: "exc3200-descriptor", extension: "bin")
}
