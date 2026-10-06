// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "ZenTouch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ZenTouch", targets: ["ZenTouchApp"]),
        .executable(name: "zentouch-cli", targets: ["ZenTouchCLI"]),
        .executable(name: "zentouch-checks", targets: ["ZenTouchChecks"]),
    ],
    targets: [
        .target(
            name: "ZenTouchCore",
            resources: [
                .copy("Resources/exc3200-descriptor.bin"), .copy("Resources/exc3200-descriptor.bin.license"),
                .copy("Resources/supported-models.json"), .copy("Resources/supported-models.json.license"),
            ]),
        .target(name: "ZenTouchMac", dependencies: ["ZenTouchCore"]),
        .executableTarget(name: "ZenTouchApp", dependencies: ["ZenTouchMac", "ZenTouchCore"]),
        .executableTarget(name: "ZenTouchCLI", dependencies: ["ZenTouchMac", "ZenTouchCore"]),
        // Command Line Tools lacks XCTest/Testing. A standalone executable
        // keeps the protocol and gesture checks runnable without full Xcode.
        .executableTarget(
            name: "ZenTouchChecks", dependencies: ["ZenTouchCore", "ZenTouchMac"], path: "Tests/ZenTouchChecks",
            resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
