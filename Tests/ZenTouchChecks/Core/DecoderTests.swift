// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore

private func packet(count: Int, scan: UInt32 = 10, contacts: [(Int, Int, Int, Bool)]) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 56)
    bytes[0] = 6
    bytes[1] = UInt8(count)
    for (i, c) in contacts.enumerated() {
        let p = 2 + i * 10
        bytes[p] = c.3 ? 1 : 0
        bytes[p + 1] = UInt8(c.0)
        bytes[p + 2] = UInt8(c.1 & 255)
        bytes[p + 3] = UInt8(c.1 >> 8)
        bytes[p + 4] = UInt8(c.2 & 255)
        bytes[p + 5] = UInt8(c.2 >> 8)
    }
    for i in 0..<4 { bytes[52 + i] = UInt8((scan >> (8 * i)) & 255) }
    return bytes
}

func decodesCoordinatesAndLiftContacts() throws {
    var decoder = EXC3200Decoder()
    let frame = try require(decoder.decode(packet(count: 2, contacts: [(2, 4095, 0, true), (1, 0, 4095, false)])))
    try expect(frame.touches == [Touch(id: 2, x: 1, y: 0)])
    try expect(try decoder.decode([1, 0, 0]) == nil)
    try expect(try decoder.decode(packet(count: 0, contacts: []))?.touches == [])
}

func assemblesTenContactHybridFrames() throws {
    var decoder = EXC3200Decoder()
    try expect(try decoder.decode(packet(count: 10, contacts: (0..<5).map { ($0, 100, 200, true) })) == nil)
    let result = try require(decoder.decode(packet(count: 0, contacts: (5..<10).map { ($0, 300, 400, true) })))
    try expect(result.touches.map(\.id) == Array(0..<10))
}

func dropsIncompleteFramesWhenScanChanges() throws {
    var decoder = EXC3200Decoder()
    try expect(try decoder.decode(packet(count: 6, contacts: (0..<5).map { ($0, 100, 200, true) })) == nil)
    try expect(try decoder.decode(packet(count: 0, scan: 11, contacts: []))?.touches == [])
    try expect(try decoder.decode(packet(count: 1, scan: 12, contacts: [(9, 0, 0, true)]))?.touches.count == 1)
}

func rejectsMalformedReportsAndDuplicates() throws {
    var decoder = EXC3200Decoder()
    try expectThrows(EXC3200Decoder.DecodeError.self) { try decoder.decode([6, 1]) }
    try expectThrows(EXC3200Decoder.DecodeError.self) { try decoder.decode(packet(count: 11, contacts: [])) }
    try expectThrows(EXC3200Decoder.DecodeError.self) {
        try decoder.decode(packet(count: 1, contacts: [(0, 5000, 0, true)]))
    }
    try expectThrows(EXC3200Decoder.DecodeError.self) {
        try decoder.decode(packet(count: 2, contacts: [(0, 1, 2, true), (0, 3, 4, true)]))
    }
}

func profileIsPackaged() throws {
    let descriptor = try require(DeviceProfile.descriptor)
    try expect(descriptor.count == 559)
    try expect(Array(descriptor.prefix(2)) == [5, 13])
}

func decodesLiveEXC3200Packets() throws {
    // Physical one-, two-, three-finger and lift packets captured 2026-10-05.
    struct Contact: Decodable {
        let id: Int
        let x: Int
        let y: Int
    }
    struct Sample: Decodable {
        let bytes: String
        let scanTime: UInt32
        let contacts: [Contact]
    }
    let url = try require(
        Bundle.module.url(forResource: "exc3200-live", withExtension: "json", subdirectory: "Fixtures"))
    let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: url))
    try expect(samples.count == 4)
    for sample in samples {
        var decoder = EXC3200Decoder()
        let bytes = try sample.bytes.split(separator: " ").map { try require(UInt8($0, radix: 16)) }
        let frame = try require(decoder.decode(bytes))
        try expect(frame.scanTime == sample.scanTime)
        try expect(
            frame.touches == sample.contacts.map { Touch(id: $0.id, x: Double($0.x) / 4095, y: Double($0.y) / 4095) })
    }
}
