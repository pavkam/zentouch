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

## 0.4.0 three-finger update

The suite now passes 51 checks, adding staged three-finger placement, coherent movement, axis locking, cumulative phases, lift suppression, reversal, stale-velocity avoidance, unexpected-contact cancellation and session failure cleanup. Native Dock event tests inspect field encoding, explicit packed HID byte offsets, both compatibility paths, invalid input rejection and injected session-tap routing without posting real input.

The installed signed 0.4.0 bundle retains its designated signing requirement and all three permission checks. Settings passes the default/minimum/large layout smoke check with the new toggle. Local DMG/ZIP checks pass relocation, signatures, profile recovery and checksums. Monitor wake/reconnect recovery is covered by retained Active intent, stable UUID selection, connectivity polling and retry tests. A physical power cycle exposed a gap these injected checks cannot catch: keeping a closed HID manager scheduled did not detect the returning controller. Discovery now stays open with independent devices; capture opens, schedules and closes only its device. Recovery is physically confirmed: the same process detects removal and re-add, reopens within about half a second of re-add and receives new contact reports. The user confirmed touch works without restarting ZenTouch. This verifies a monitor power cycle, not a full Mac sleep/unplug stress run.

Vertical commands commit Mission Control/App Exposé on lift through the Dock, with cancellation and duplicate-end coverage; horizontal swipes keep the isolated event serializer. The attached MB16AMTR’s three-finger swipe up opening Mission Control is confirmed by the user and a native Dock transition. App Exposé and desktop switching still need physical confirmation; these checks do not establish complete trackpad parity.

Settings now has one Start/Stop button and a live contact preview. Contact-test controls and report/frame counters are removed from the UI. The signed build 6 smoke check passes default, minimum and enlarged layouts without ambiguity or clipping; the logs button stays 24 pixels from the bottom in each size. Stopping pending recovery remains enabled, and all existing privacy grants survive installation.

Build 7 adds an optional display overlay with a steady center and a pulsating ring for each contact. It uses the selected screen's AppKit frame and the bridge's coordinate clamping. The overlay cannot receive mouse input, become key or become main. It clears on lift, disabled input, target loss, invalid frames and stalled reports; Reduce Motion uses steady rings. The preference is saved and defaults to off.

The signed GUI smoke check passes ten overlay checks: two visible contacts, mouse transparency and unchanged key window, Reduce Motion, rendering the app's own layers, removal of one lifted finger, full lift, stalled-frame cleanup, invalid coordinates, disabling the option and stopping input. The rendered preview was visually inspected. Settings retains unambiguous, unclipped layouts and 24-pixel bottom padding at all three tested sizes, with all privacy grants intact. The 51 behavior checks still pass. Physical alignment and gesture use with the overlay enabled remain pending user testing.

Package validation retries temporary read-only DMG cleanup before forcing removal of its own validation mount. This handles a transient busy volume after signature checks without leaving a mounted image behind.

## 0.4.0 attachment state and model catalog

Build 8 shows a slashed screen icon when the selected display or supported USB controller is unavailable. Start, gesture options and touch indicators disable accordingly; Stop remains available to cancel retained Active intent. Reconnection restores the icon and controls. Display notifications and HID discovery callbacks trigger coalesced refreshes after their snapshots update, with one-second polling as a fallback. Losing availability stops input even before the session's own snapshots catch up. Availability transitions and refresh reasons are logged.

The [model catalog](supported-models.md) holds model names, exact aliases, ASUS sources and verification status. It includes 13 researched touch models, with the attached/tested model linked to the implemented controller profile and the other entries unverified. Display/UI/CLI code contains no model literals or shared-prefix matching. Unverified models do not become automatic input targets. The app and helper use the same packaged JSON; missing or invalid data disables input, and resource loading cannot fall back to development files. USB availability also requires one controller with the exact implemented identity and captured descriptor.

The suite now passes 57 checks, including hardware loss before session snapshots change, both display/USB attachment orders, exact model matching, ambiguity, unverified selection and catalog validation. The signed GUI smoke check passes 11 hardware/catalog checks and the existing ten overlay checks. It verifies disconnected, display-only, USB-only, attached, running, denied-permission and suspended states; Stop during detach; display/controller refresh handlers; and catalog availability. The disconnected artwork was visually inspected. Default, minimum and enlarged Settings layouts remain unclipped and unambiguous with 24-pixel bottom padding. All existing privacy grants survive installation.

These attachment checks simulate state changes and invoke the app's handlers; they do not establish a new physical attach/detach run. Prior monitor power-cycle recovery remains physically verified, and testing this build's icon/control transitions on reconnect is pending. Packaging also checks missing-catalog failure alongside missing-profile recovery.

## 0.4.0 stationary-pointer mode

Build 9 adds a saved, opt-in **Keep pointer stationary (experimental)** checkbox. It is disabled while input runs and when the display/controller is unavailable. New sessions and automatic recovery construct the chosen event backend; normal input and the CLI retain their existing mouse behavior.

The suite passes 66 checks. Nine new checks cover drag capture through window movement, disappearance and ID reuse, scroll and pinch capture/cancellation, front-to-back selection, per-window click counts, activation ordering, rapid touches across apps, queued-input cleanup and bypassing the global pointer poster. Injected environments capture events without clicking other apps.

The production router also passed ten local native-control checks in a separate, owned AppKit receiver process: button, checkbox after a confirmed inactive-to-active transition, slider, text selection, scrolling, custom drag, custom right-click handling, popup opening, click after window movement, and menu selection. The cursor was sampled every 10 ms; maximum movement was zero in each check. A mouse-transparent utility overlay exposed an initial discovery bug; Accessibility hit testing now identifies the interactive window below it, with a regular-app metadata fallback. App activation uses cooperative activation plus the trusted Accessibility frontmost/raise attributes.

The earlier hardware prototype reached the receiver and the user reported taps, slider dragging and two-finger scrolling with the mouse stationary. Its live counters independently confirmed dragging, but did not independently confirm all three reported control effects; the automated native tests provide that separate control baseline. The user then confirmed tapping and scrolling in their usual apps with the installed build 9 while the pointer stayed still. App names were not recorded; this confirms that live use without establishing a compatibility matrix.

The backend uses a hidden borderless AppKit window to encode correct foreign-window coordinates, changes destination window metadata (including undocumented field 51) and posts directly to the owning PID. It never falls back to global mouse posting. The mode is experimental: wider framework compatibility, desktop/menu bar controls, window-title dragging and cross-application file drops still need live testing. Native-control checks do not establish universal app support or Apple-trackpad parity.

Build 9 also passes the signed Settings smoke check at default, minimum and enlarged sizes without ambiguous or clipped views. Footer spacing stays 24 pixels, the new option disables/enables with hardware and session state, and the existing overlay and permission checks pass. DMG/ZIP validation passes relocated signatures, resources, architecture, checksums and missing-profile/catalog failures. The installed app retains all privacy grants under the original signing requirement.

Build 10 tightens double-click history across overlapping windows: switching targets starts at one click, and the next tap in that window becomes two, even if the upstream global counter already reached three. Down/up counts remain paired. The regression is covered in the window click-boundary check.
