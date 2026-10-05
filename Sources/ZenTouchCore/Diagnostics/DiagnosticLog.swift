// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Darwin
import Foundation

/// Synchronous JSON lines with bounded rotation. flush() requests durable storage.
/// A file lock coordinates the GUI and CLI; NSLock serializes local threads.
public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog()
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("events.jsonl") }
    public let sessionID = UUID().uuidString
    public let maxBytes: UInt64
    public let archiveCount: Int
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()
    private var handle: FileHandle?
    private var lockHandle: FileHandle?
    private var reportedFailure = false

    public init(directory: URL? = nil, maxBytes: UInt64 = 8 * 1024 * 1024, archiveCount: Int = 2) {
        self.directory =
            directory
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ZenTouch", isDirectory: true)
        self.maxBytes = max(512, maxBytes)
        self.archiveCount = max(0, min(10, archiveCount))
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    @discardableResult public func record(_ event: String, _ fields: [String: Any] = [:]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            var entry = fields
            entry["event"] = event
            entry["time"] = formatter.string(from: Date())
            entry["uptime"] = ProcessInfo.processInfo.systemUptime
            entry["pid"] = ProcessInfo.processInfo.processIdentifier
            entry["session"] = sessionID
            var data = try encode(entry)
            if UInt64(data.count) > maxBytes {
                entry = [
                    "event": "logging.oversize", "originalEvent": String(event.prefix(16)),
                    "bytes": data.count, "session": sessionID, "time": formatter.string(from: Date()),
                ]
                data = try encode(entry)
            }
            try prepareLock()
            guard let lockHandle, flock(lockHandle.fileDescriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
            defer { _ = flock(lockHandle.fileDescriptor, LOCK_UN) }
            try openCurrent()
            guard let handle else { throw CocoaError(.fileWriteUnknown) }
            let size = try handle.seekToEnd()
            if size > 0, size + UInt64(data.count) > maxBytes { try rotate() }
            guard let destination = self.handle else { throw CocoaError(.fileWriteUnknown) }
            try destination.write(contentsOf: data)
            return true
        } catch {
            if !reportedFailure {
                reportedFailure = true
                FileHandle.standardError.write(Data("ZenTouch logging failed: \(error.localizedDescription)\n".utf8))
            }
            return false
        }
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.synchronize()
    }

    private func encode(_ entry: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(entry) else { throw CocoaError(.propertyListWriteInvalid) }
        var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        data.append(10)
        return data
    }

    private func prepareLock() throws {
        guard lockHandle == nil else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent(".rotation.lock")
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        lockHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func openCurrent() throws {
        var current = stat()
        var opened = stat()
        if let handle, fstatat(AT_FDCWD, fileURL.path, &current, 0) == 0,
            fstat(handle.fileDescriptor, &opened) == 0, current.st_ino == opened.st_ino
        {
            return
        }
        try handle?.close()
        handle = nil
        let descriptor = Darwin.open(fileURL.path, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EACCES)
        }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let fm = FileManager.default
        if archiveCount > 0 {
            let oldest = directory.appendingPathComponent("events.\(archiveCount).jsonl")
            if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
            if archiveCount > 1 {
                for index in stride(from: archiveCount - 1, through: 1, by: -1) {
                    let source = directory.appendingPathComponent("events.\(index).jsonl")
                    let destination = directory.appendingPathComponent("events.\(index + 1).jsonl")
                    if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: destination) }
                }
            }
            try fm.moveItem(at: fileURL, to: directory.appendingPathComponent("events.1.jsonl"))
        } else {
            try fm.removeItem(at: fileURL)
        }
        try openCurrent()
    }

    deinit {
        try? handle?.close()
        try? lockHandle?.close()
    }
}
