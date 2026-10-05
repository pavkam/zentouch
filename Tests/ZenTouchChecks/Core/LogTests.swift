// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore

func loggerWritesCompleteConcurrentJSONRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "zentouch-log-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let logger = DiagnosticLog(directory: directory, maxBytes: 1024 * 1024)
    DispatchQueue.concurrentPerform(iterations: 100) { i in
        logger.record("test.record", ["index": i, "bytes": "06 02 01 ff"])
    }
    let lines = try String(contentsOf: logger.fileURL, encoding: .utf8).split(separator: "\n")
    try expect(lines.count == 100)
    let records = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    try expect(Set(records.compactMap { $0["index"] as? Int }).count == 100)
    try expect(
        records.allSatisfy { $0["event"] as? String == "test.record" && $0["session"] as? String == logger.sessionID })
}

func loggerRotationRetainsReadableBoundedFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "zentouch-log-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let logger = DiagnosticLog(directory: directory, maxBytes: 400)
    for i in 0..<10 { logger.record("test.rotate", ["index": i]) }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
        $0.pathExtension == "jsonl"
    }
    try expect(files.count == 3)
    for file in files {
        let data = try Data(contentsOf: file)
        try expect(data.count <= logger.maxBytes)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            _ = try JSONSerialization.jsonObject(with: Data(line.utf8))
        }
    }
    let current = try String(contentsOf: logger.fileURL, encoding: .utf8)
    try expect(current.contains("\"index\":9"))
}

func loggerCoordinatesMultipleWritersAcrossRotation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "zentouch-log-writers-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writers = [
        DiagnosticLog(directory: directory, maxBytes: 1024), DiagnosticLog(directory: directory, maxBytes: 1024),
    ]
    DispatchQueue.concurrentPerform(iterations: 400) { i in
        writers[i % 2].record("test.concurrentRotation", ["index": i])
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
        $0.pathExtension == "jsonl"
    }
    try expect(files.count == 3)
    for file in files {
        let data = try Data(contentsOf: file)
        try expect(data.count <= 1024)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            _ = try JSONSerialization.jsonObject(with: Data(line.utf8))
        }
    }
}

func loggerBoundsOversizedRecordsAndRecoversFromInvalidFields() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "zentouch-log-size-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let logger = DiagnosticLog(directory: directory, maxBytes: 512)
    try expect(logger.record("oversized", ["payload": String(repeating: "x", count: 10000)]))
    try expect(!logger.record("invalid", ["value": Double.nan]))
    try expect(logger.record("recovered"))
    let data = try Data(contentsOf: logger.fileURL)
    try expect(data.count <= 512)
    let records = try String(decoding: data, as: UTF8.self).split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
    try expect(records.contains { $0["event"] as? String == "logging.oversize" })
    try expect(records.contains { $0["event"] as? String == "recovered" })
    let permissions =
        try FileManager.default.attributesOfItem(atPath: logger.fileURL.path)[.posixPermissions] as? NSNumber
    try expect(permissions?.intValue == 0o600)
}

func loggerCoordinatesProcessWriters() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "zentouch-log-processes-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let processes = (0..<2).map { index -> Process in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--log-worker", directory.path, "\(index)"]
        return process
    }
    for process in processes { try process.run() }
    for process in processes {
        process.waitUntilExit()
        try expect(process.terminationStatus == 0)
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
        $0.pathExtension == "jsonl"
    }
    try expect(files.count == 3)
    for file in files {
        let data = try Data(contentsOf: file)
        try expect(data.count <= 1024)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            try expect(row["event"] as? String == "test.processWriter")
        }
    }
}
