// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

/// Layout verified against the connected EXC3200's HID descriptor.
/// Five 10-byte slots per packet; up to ten contacts per hybrid frame.
public struct EXC3200Decoder {
    private var pending: (scan: UInt32, expected: Int, slots: [(Touch, Bool)])?
    public init() {}

    public mutating func reset() { pending = nil }

    public mutating func decode(_ bytes: [UInt8]) throws -> TouchFrame? {
        guard bytes.first == 6 else { return nil }
        guard bytes.count >= 56 else {
            reset()
            throw DecodeError.truncated
        }
        let count = Int(bytes[1])
        guard count <= 10 else {
            reset()
            throw DecodeError.invalidCount
        }
        let scan = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[52 + $1]) << (8 * $1) }
        var slots: [(Touch, Bool)] = []
        let needed: Int
        if count > 0 {
            // A new header supersedes an incomplete previous frame.
            pending = nil
            needed = min(count, 5)
        } else if let p = pending, p.scan == scan {
            needed = min(p.expected - p.slots.count, 5)
        } else {
            pending = nil
            return TouchFrame(scanTime: scan, touches: [])
        }
        for index in 0..<needed {
            let offset = 2 + index * 10
            let x = Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8
            let y = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            guard x <= 4095, y <= 4095, bytes[offset + 1] <= 31 else {
                reset()
                throw DecodeError.invalidContact
            }
            slots.append(
                (
                    Touch(
                        id: Int(bytes[offset + 1]), x: Double(x) / 4095,
                        y: Double(y) / 4095), bytes[offset] & 1 != 0
                ))
        }
        if count > 5 {
            pending = (scan, count, slots)
            return nil
        }
        if let p = pending {
            slots = p.slots + slots
            if slots.count < p.expected {
                pending = (scan, p.expected, slots)
                return nil
            }
        }
        pending = nil
        guard Set(slots.map { $0.0.id }).count == slots.count else {
            throw DecodeError.duplicateID
        }
        return TouchFrame(scanTime: scan, touches: slots.filter { $0.1 }.map { $0.0 }.sorted { $0.id < $1.id })
    }

    public enum DecodeError: Error { case truncated, invalidCount, invalidContact, duplicateID }
}
