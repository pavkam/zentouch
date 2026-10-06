// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import IOKit.hid
import ZenTouchCore
import ZenTouchMac

private let diagnostics = DiagnosticLog.shared

@main
struct ZenTouchCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        defer { diagnostics.flush() }
        diagnostics.record(
            "process.start",
            [
                "mode": args.first ?? "help",
                "bundle": Bundle.main.bundleIdentifier ?? "cli", "version": "0.4.0", "log": diagnostics.fileURL.path,
            ])
        diagnostics.record(
            "process.permissions",
            [
                "inputMonitoring": PermissionState.current.inputMonitoring,
                "accessibility": PermissionState.current.accessibility,
            ])
        do { try command(args) } catch {
            diagnostics.record("command.error", ["error": error.localizedDescription])
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            diagnostics.flush()
            exit(1)
        }
    }

    static func command(_ args: [String]) throws {
        switch args.first ?? "help" {
        case "self-check":
            guard args.count == 1, DeviceProfile.descriptor?.count == 559 else {
                throw ZenError(message: "ZenTouch's controller profile is missing or invalid.")
            }
            _ = try ModelCatalog.loadBundled()
            print("ZenTouch CLI: controller profile verified (559 bytes)")
        case "models":
            guard args.count == 1 else { throw ZenError(message: "models takes no options.") }
            let catalog = try ModelCatalog.loadBundled()
            print("Model\tFamily\tZenTouch\tASUS touch points\tASUS source")
            for model in catalog.models {
                print(
                    "\(model.model)\t\(model.family)\t\(model.status.rawValue)\t\(model.touchPoints)\t\(model.source.absoluteString)"
                )
            }
        case "--version":
            guard args.count == 1 else { throw ZenError(message: "--version takes no options.") }
            print("ZenTouch CLI 0.4.0")
        case "help", "--help", "-h":
            printUsage()
        case "inspect":
            guard args.count == 1 else { throw ZenError(message: "inspect takes no options.") }
            let reader = HIDReader()
            for device in reader.devices() {
                let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data
                print("\(name) | VID=0x0eef PID=0xc000 | descriptor matched=\(descriptor == DeviceProfile.descriptor)")
            }
            print(
                "Input Monitoring: \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue) (0=granted, 1=denied, 2=unknown)"
            )
            print("Event posting allowed: \(CGPreflightPostEventAccess())")
            for screen in ScreenTarget.all {
                print(
                    "display \(screen.id): \(screen.name) \(String(describing: screen.geometry?.bounds)), rotation \(CGDisplayRotation(screen.id))°"
                )
            }
        case "capture", "bridge":
            let allowed = Set(["--seconds", "--multitouch", "--experimental-pinch"])
            var seconds = 30.0
            var multitouch = args[0] == "bridge"
            var pinch = false
            var i = 1
            while i < args.count {
                guard allowed.contains(args[i]) else { throw ZenError(message: "Unknown option: \(args[i])") }
                switch args[i] {
                case "--seconds":
                    i += 1
                    guard i < args.count, let value = Double(args[i]), value.isFinite, value > 0 else {
                        throw ZenError(message: "--seconds requires a positive duration.")
                    }
                    seconds = value
                case "--multitouch": multitouch = true
                case "--experimental-pinch": pinch = true
                default: break
                }
                i += 1
            }
            let session = TouchSession()
            session.onStatus = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            session.onFrame = { frame in
                if let data = try? JSONEncoder().encode(frame) {
                    print(String(decoding: data, as: UTF8.self))
                    fflush(stdout)
                }
            }
            try session.start(
                kind: args[0] == "bridge" ? .input : .contacts, target: ScreenTarget.supportedTouchScreen, pinch: pinch,
                multitouch: multitouch)
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let sources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                source.setEventHandler { CFRunLoopStop(CFRunLoopGetMain()) }
                source.resume()
                return source
            }
            let deadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                CFRunLoopStop(CFRunLoopGetMain())
            }
            defer {
                deadline.invalidate()
                session.stop()
                for source in sources { source.cancel() }
            }
            CFRunLoopRun()
        default:
            throw ZenError(message: "Unknown command: \(args.first ?? ""). Run zentouch-cli --help.")
        }
    }

    static func printUsage() {
        print(
            """
            ZenTouch CLI: ZenScreen touch bridge
              zentouch-cli self-check                 Verify packaged controller profile
              zentouch-cli inspect                     Inspect device/displays/permissions
              zentouch-cli models                      List catalog models and verification status
              zentouch-cli capture [--seconds 30]       Read contacts without changing mode
              zentouch-cli capture --multitouch         Temporarily enable multi-touch
              zentouch-cli bridge [--seconds 30]        Enable input on the supported touchscreen
                [--experimental-pinch]             Opt into private gesture fields
            """)
    }
}
