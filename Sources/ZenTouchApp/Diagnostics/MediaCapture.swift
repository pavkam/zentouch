// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Explicit developer export. Captures only this process's windows through
/// currentProcess, without requesting access to other apps or the desktop.
@available(macOS 14.4, *)
@MainActor
enum MediaCapture {
    static func image(of window: SCWindow, to destination: URL) async throws {
        guard window.owningApplication?.processID == getpid() else {
            throw NSError(
                domain: "ZenTouch.Media", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foreign window refused."])
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = false
        configuration.shouldBeOpaque = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "ZenTouch.Media", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed."])
        }
        try png.write(to: destination, options: .atomic)
    }

    // Menu tracking runs a nested AppKit loop. Keep capture callbacks off the
    // main actor so the menu stays open until the compositor completes.
    nonisolated static func captureMenu(folder: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        SCShareableContent.getCurrentProcessShareableContent { content, error in
            guard
                let window = content?.windows.first(where: {
                    $0.owningApplication?.processID == getpid() && $0.isOnScreen && $0.windowLayer > 0
                        && $0.frame.width > 180 && $0.frame.height > 200
                })
            else {
                completion(
                    .failure(
                        error
                            ?? NSError(
                                domain: "ZenTouch.Media", code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Menu window unavailable."])))
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.includeChildWindows = false
            configuration.shouldBeOpaque = false
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                guard let image,
                    let writer = CGImageDestinationCreateWithURL(
                        folder.appendingPathComponent("menu.png") as CFURL, UTType.png.identifier as CFString, 1, nil)
                else {
                    completion(
                        .failure(
                            error
                                ?? NSError(
                                    domain: "ZenTouch.Media", code: 5,
                                    userInfo: [NSLocalizedDescriptionKey: "Menu image unavailable."])))
                    return
                }
                CGImageDestinationAddImage(writer, image, nil)
                if CGImageDestinationFinalize(writer) {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "ZenTouch.Media", code: 6)))
                }
            }
        }
    }

    static func run(settings: SettingsWindowController, menu: MenuBarController, folder: URL) async {
        let previous = settings.selectedTab
        defer { settings.selectTab(previous) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("capture-error.txt"))
            settings.present()
            for (index, name) in ["settings-touch", "settings-gestures", "settings-app"].enumerated() {
                settings.selectTab(index)
                settings.setAnimationProgress(0.35)
                settings.window?.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 400_000_000)
                let content = try await SCShareableContent.currentProcess
                guard
                    let window = content.windows.first(where: {
                        $0.windowID == settings.window.map { CGWindowID($0.windowNumber) }
                    })
                else {
                    throw NSError(
                        domain: "ZenTouch.Media", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Settings window unavailable."])
                }
                try await image(of: window, to: folder.appendingPathComponent("\(name).png"))
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let finish: @MainActor @Sendable (Result<Void, Error>) -> Void = { result in
                    menu.closeForMediaCapture()
                    continuation.resume(with: result)
                }
                menu.openForMediaCapture {
                    captureMenu(folder: folder) { result in
                        RunLoop.main.perform(inModes: [.common]) {
                            MainActor.assumeIsolated { finish(result) }
                        }
                    }
                }
            }

            try "Captured ZenTouch's three Settings tabs and menu.\n".write(
                to: folder.appendingPathComponent("capture-result.txt"), atomically: true, encoding: .utf8)
        } catch {
            try? error.localizedDescription.write(
                to: folder.appendingPathComponent("capture-error.txt"), atomically: true, encoding: .utf8)
            diagnostics.record("app.media.error", ["error": error.localizedDescription])
        }
    }
}
