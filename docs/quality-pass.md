<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# ZenTouch 0.2.0 quality pass

The working touch bridge is now a menu bar app with separate protocol, macOS, UI and diagnostic targets. Alex confirmed clicks and two-finger scrolling continue with Settings closed on the attached MB16AMTR.

## Changes and findings

| Area | Finding and correction |
| --- | --- |
| App lifecycle | The menu bar owns the session. Closing Settings keeps input running; Quit releases gestures, requests the previous controller mode and flushes logs. Sleep and inactive-session reasons are tracked separately. |
| Input delivery | HID callbacks and timers use common run-loop modes, so opening a menu does not pause capture. Permission and display geometry are checked before translating each frame. |
| Gesture recovery | Invalid reports, stalled active gestures and extra fingers cancel input and suppress residual contacts until lift. Idle periods do not suppress the next fresh touch. Scroll/pinch cancellation uses the original gesture anchor. |
| Event fields | Coordinates include the display origin and clamp to its last pixel. Right-clicks and drags clear double-click history. Integer pixel scroll fields and fractional 16.16 fields are set separately, with overflow bounds. |
| Hardware mode | The controller accepts multi-touch mode but reads back mode 0 while emitting multiple contacts. Capture confirms the mode using actual reports instead of rejecting a successful write on readback alone. |
| Logs | Thread and process locks coordinate JSON-line writes and rotation. Writers reopen the current inode after another process rotates it. Retention is 8 MiB per file, three files total. Invalid JSON values and oversized records cannot crash or grow the log without bounds. |
| Packaging | Explicit names, metadata, icons, help and notices replace prototype defaults. GUI and CLI executable names are distinct: case-only names collided on this Mac's filesystem. The packaged helper locates its controller profile inside the app instead of relying on SwiftPM's development resource path. |
| Permissions | The bundle ID remains `org.pavkam.zentouch`. Builds reuse the pinned signing certificate; installation refuses a changed designated requirement. Settings and the menu show live permission checks. |

The scroll field distinction follows Apple's definitions of [integer pixel deltas](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventpointdeltaaxis1) and [fractional fixed-point deltas](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventfixedptdeltaaxis1). Experimental pinch remains isolated and opt-in because its event fields are undocumented.

## Verification

`make check` passes **33 checks**, strict Swift formatting, builds with warnings treated as errors, and CLI help/version/invalid-command checks. The deliberate invalid-JSON test prints one logging-failure message and verifies that subsequent valid records still succeed.

Checks cover captured one-, two-, three-contact and lift packets; synthetic ten-contact continuation; malformed reports; gesture phases and recovery; thread/process log rotation; bounded oversized records; permissions; failed/duplicate startup; stop cleanup; disconnects; display changes; timeouts; coordinate mapping; click counts; scroll event fields; and independent suspension reasons. The event-posting tests capture events in memory and send no system input.

The build verifies bundle metadata, resources, both executable versions, the helper's hardware profile and strict signatures for the app and nested helper. Packaging verifies the compressed DMG and creates a ZIP with SHA-256 checksums. The package check extracts the ZIP and mounts the DMG read-only, verifies the relocated apps and architecture, checks all release checksums and confirms clean failure with a missing controller profile. Installation stages the replacement, waits for clean shutdown and verifies the installed bundle.

The app's `--smoke-test` option checks its own menu bar, activation policy, icons, permission state, close-window policy and Settings layout at default, minimum and larger window sizes. It does not start hardware capture or inspect other applications.

## Remaining limits

- Live clicks, scrolling, multiple contacts and operation with Settings closed are confirmed. Six-to-ten-finger hybrid reports are covered synthetically; those contact counts still need live capture.
- Sleep/lock ordering, display changes and unplug cleanup are covered with injected environments. A full physical sleep/unplug stress run remains separate from these checks.
- Public mouse and scroll events provide the tested behavior. Native Apple trackpad parity, macOS direct-touch production and experimental pinch remain unverified.
- Display rotation is restricted to 0°. Other ZenScreen controllers are rejected unless their exact profile is supported.
- The app is locally certificate-signed, with hardened runtime enabled. It is not a notarized Developer ID release for public distribution. The release artifacts target this Mac's arm64 architecture.
- Command Line Tools lacks the test frameworks in this environment, so the standalone check runner supplies deterministic failures without external dependencies. The selected native SwiftPM backend currently emits a deprecation warning.
