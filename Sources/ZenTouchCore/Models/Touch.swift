// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

public struct Touch: Equatable, Codable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct TouchFrame: Equatable, Codable, Sendable {
    public let scanTime: UInt32
    public let touches: [Touch]
    public init(scanTime: UInt32, touches: [Touch]) {
        self.scanTime = scanTime
        self.touches = touches
    }
}
