<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# ZenTouch

ZenTouch adds clicks, dragging, right-clicks and two-finger scrolling to the ASUS ZenScreen Touch MB16AMTR on macOS. It lives in the menu bar; closing Settings keeps input running. Clicks and two-finger scrolling have been physically verified on the attached Mac.

The supported controller is **eGalaxTouch EXC3200-2505**, USB **0eef:c000**. ZenTouch checks its exact HID descriptor before changing the controller or translating contacts. Experimental pinch is opt-in; complete Apple trackpad gesture behavior remains unverified.

## Install and run

Apple Command Line Tools, Swift and an existing local code-signing identity are sufficient.

```sh
make check
make install
open ~/Applications/ZenTouch.app
```

The installer verifies the bundle, checks that an existing app has the same signing requirement, requests a clean quit, and stages the replacement before installing it at **~/Applications/ZenTouch.app**. It registers that path with LaunchServices.

The build pins the signing certificate's public fingerprint in ignored **.zentouch-signing-identity**. Later builds reuse the key and fail if it is unavailable. There is no ad-hoc fallback. To choose an identity on the first build, set **ZENTOUCH_SIGNING_IDENTITY** to its name or fingerprint.

1. Open **Settings…** from the ZenTouch menu bar icon.
2. Allow **Input Monitoring** and **Accessibility** in macOS Settings. Quit and reopen if macOS requests it. Green checks show grants seen by the running app.
3. Select the ZenScreen, keep its rotation at **0°**, and click **Start Touch Input**.
4. Tap to click, move one finger to drag, move two fingers together to scroll, or tap with two fingers to right-click. A stationary long touch also right-clicks on release.

Settings uses one **Start Touch Input / Stop Touch Input** button and a live contact preview. Controller report/frame counts remain in the logs rather than the Settings form. Developers can use **--test-touch** for contact-only capture without posting input.

ZenTouch remembers the display, experimental pinch preference, and whether input was enabled. Sleep or locking pauses input; wake or session activation resumes it once all suspension reasons clear. USB disconnects, permission loss and display changes pause capture; input resumes when the selected display and permissions return.

Turning off **Active** in the menu (or clicking **Stop Touch Input** in Settings) releases active gestures, cancels pending recovery and requests the previous controller mode. **Quit ZenTouch** performs the same cleanup and exits. An abrupt kill cannot run cleanup; reconnect the USB cable if the controller needs resetting.

If the app is missing from Privacy & Security, use **+** to add the installed app. The initial prototype used an ad-hoc signature; migration to the stable certificate required one app-scoped TCC reset. Normal updates preserve the signing requirement and do not reset permissions.

## Packaging

```sh
make package
```

This runs the checks and produces **dist/ZenTouch.app**, a compressed DMG with an Applications shortcut, a ZIP, and SHA-256 checksums. The artifact name includes the version and build architecture. This Mac builds **arm64**.

The package check extracts the ZIP and mounts the DMG read-only, verifies both relocated apps, checks signatures and checksums, and tests clean failure when the helper's controller profile is missing.

The bundle includes explicit ZenTouch names, version/build metadata, custom app and menu bar artwork, menu bar activation settings, bundled help, third-party notices, the hardware profile, and a separately signed **zentouch-cli** helper. The helper has a distinct filename because macOS filesystems commonly treat case-only names as the same file.

These are local certificate-signed builds. They are not notarized Developer ID releases; public distribution requires the appropriate Apple signing identity and notarization.

## Logs

Logs live at **~/Library/Logs/ZenTouch/events.jsonl**. The current file and two archives are each limited to **8 MiB**, for **24 MiB** of retained event data. Oversized records become a bounded diagnostic entry. Files use mode **0600**, and the directory uses **0700**.

The log records permission changes, controller enumeration/open/mode operations, every received controller report, decoded contacts, translated actions, posting attempts, heartbeat totals and cleanup. Each entry identifies its process and session. It does not monitor other input devices.

A file lock coordinates GUI/CLI writers during rotation, while a thread lock protects each logger. Normal quit flushes writes. **Open Logs Folder** is available in the menu and Settings.

## Source layout and verification

| Target | Responsibility |
| --- | --- |
| **ZenTouchCore** | Touch models, exact HID decoder, gesture state machine, bounded JSON logger, suspension reasons |
| **ZenTouchMac** | HID access, permissions, display geometry, event posting, injectable session lifecycle |
| **ZenTouchApp** | Menu bar, Settings, preferences, sleep/lock handling, app entry point |
| **ZenTouchCLI** | Explicit diagnostic commands; shipped as zentouch-cli |
| **ZenTouchChecks** | Protocol, gesture, logging and mocked session checks, plus real packet fixtures |

```sh
make check       # Formatting, warnings-as-errors builds, checks and CLI behavior
make format      # Apply the repository's Swift format
make build       # Signed app and nested CLI; validate metadata/resources/signatures
```

Command Line Tools does not provide XCTest/Swift Testing in this environment, so checks use a standalone Swift executable with a nonzero failure status. No external dependencies are required. The native SwiftPM backend is selected explicitly for this Command Line Tools setup; Swift currently warns that this backend is deprecated.

The tests cover real one-, two-, three-contact and lift packets; synthetic ten-contact hybrid frames; invalid reports; gesture phases and cancellation; residual-finger suppression; concurrent and multi-process log rotation; oversized/invalid log records; session permission gates; failed and duplicate startup; idempotent cleanup; permission revocation; display changes; timeouts; disconnect errors; and independent sleep/lock reasons.

The packaged GUI also has a smoke check for its own menu bar state, permissions, icons, Settings layout and close-window behavior:

```sh
open ~/Applications/ZenTouch.app --args --smoke-test /tmp/zentouch-smoke.json
```

Run this with ZenTouch stopped. It opens Settings, writes a report and quits without starting a touch session.

## Diagnostic commands

```sh
~/Applications/ZenTouch.app/Contents/Helpers/zentouch-cli --help
~/Applications/ZenTouch.app/Contents/Helpers/zentouch-cli inspect
~/Applications/ZenTouch.app/Contents/Helpers/zentouch-cli capture --multitouch --seconds 30
~/Applications/ZenTouch.app/Contents/Helpers/zentouch-cli bridge --seconds 30
```

Plain capture leaves the mode unchanged. Multi-touch capture writes feature report 5 and restores the read mode on stop. This controller returns mode 0 even while reporting multiple contacts, so actual input packets confirm multi-touch. When launched from a terminal, macOS can attribute grants to the terminal; use the signed GUI for normal operation.

## Three-finger swipes

`ThreeFingerSwipe` recognizes three contacts moving together, locks the dominant axis after 24 pixels, and maps 240 pixels to one unit of cumulative swipe progress. Right/down are positive in the recognizer; the Dock adapter negates both axes. A first lift finishes the gesture. A fourth finger, contact replacement, lost report, Stop, timeout or environment failure cancels it and suppresses residual contacts until all fingers lift. Three-finger taps have no action. Staged placement promotes an uncommitted one/two-finger tap within 250 ms; an active drag, scroll or pinch never becomes navigation.

`DockSwipeEvents` isolates the private horizontal Dock event ABI. It posts paired DockControl/Gesture events to the session tap, with began/changed/ended/cancelled phases, cumulative progress and bounded lift velocity. macOS 27 additionally requires the packed IOHID fluid-gesture payload in serialized field 4205. Explicit little-endian records avoid Swift struct padding; the outer field header is big-endian. Unknown CGEvent serialization versions fail closed and log `input.swipe.error`.

`VerticalSwipeCommit` commits Mission Control (up) or App Exposé (down) once on lift after at least 0.2 progress, provided the final movement is away from the origin. Reversal, cancellation, invalid input or short travel discards the command. `DockActions` resolves `CoreDockSendNotification` in HIServices at runtime; this native Dock command opens the same system view but is discrete rather than a finger-tracked animation. The vertical serialized event path did not respond in live testing on this Mac, so it is not posted alongside the command.

The checkbox is enabled by default and saved separately from macOS trackpad preferences. Stop input before changing it. Automated checks use injected posters and never trigger Mission Control or switch desktops. The normal app logs horizontal `input.swipe.post`, vertical `input.systemGesture.post` and `app.activeSpace.changed`; the latter can corroborate a horizontal desktop transition but does not identify which input device caused it. A three-finger upward swipe opening Mission Control is confirmed on the attached MB16AMTR; desktop switching and App Exposé still need live confirmation.

## Monitor sleep and reconnect recovery

The HID manager uses `IOHIDManagerOptions.independentDevices` and stays open and scheduled in the main run loop’s common modes for its entire lifetime, including while waiting or stopped. Each capture session opens, schedules, unschedules and closes its device directly. Manager operations therefore cannot close or schedule a capture connection, and stopping capture cannot stop discovery. `hid.discovery.open` records the watcher’s result independently of `hid.open`/`hid.close` for capture. The session polls connectivity as a backup when a removal callback is delayed. Merely leaving a closed manager scheduled did not detect the controller’s return in live testing. The independent discovery path is physically confirmed: removal, re-add, reopen and fresh touch reports occur in the same app process after turning the monitor off and on.

`SessionRecovery` keeps the user’s Active intent across monitor power saving, USB/display loss and permission changes. It revalidates resources before reopening; failures back off from one to fifteen seconds without repeatedly opening Settings. Explicit Stop and contact testing clear the intent, and separate Mac sleep, screen sleep and session-lock suspension reasons prevent resuming early. Screen wake reapplies multi-touch mode even if USB remained connected. The selected display is saved by UUID because its numeric ID may change on wake; a reused ID never overrides a saved UUID.

`--trace-dock-swipes` enables a developer-only, two-minute event trace for comparing real trackpad Dock swipes with translated swipes. It listens only to event type 30 and records gesture metadata/serialized envelopes, never keyboard, mouse or ordinary scrolling. It stops automatically or on quit and is disabled by default.

`--probe-system-gesture up` or `down` runs one real Dock command under the signed GUI’s existing grants, then exits. Unlike the no-input smoke check, this changes Mission Control/App Exposé and is an explicit developer test.

Developer launch options **--enable-input**, **--test-touch** and **--show-settings** start input, show a contact test, or open Settings explicitly.

Display configuration notifications and HID discovery callbacks queue a coalesced main-thread refresh after their snapshots update. Discovery callbacks remain installed while capture is stopped. The one-second refresh remains a fallback. Losing availability stops input even if the session's own geometry/USB snapshot has not caught up. The UI uses the same availability checks for the slashed menu bar icon and Start/gesture/indicator controls. Stop can cancel pending recovery; the display chooser remains usable when a connected controller and a catalog-supported display need selection. Availability transitions and refresh reasons are logged as `app.hardware.changed` and `app.environment.changed`.

Model strings and ASUS product sources live in [the model catalog](supported-models.md). `ModelCatalog` validates its schema and matches complete display-name tokens. Automatic target selection considers verified entries with an implemented profile; saved UUID selection still wins. Both packaged executables load the same JSON, and packaged resource loading never falls back to SwiftPM development files. The CLI's `models` command prints the catalog with verification status. USB availability requires one controller with the implemented product identity and exact captured descriptor.

The GUI smoke check exercises display-only, USB-only, fully detached, attached, running, permission-denied and suspended states, plus detach with retained Active intent. It invokes the screen notification and controller-change handler without touching physical hardware or posting input. Synthetic overlay checks use the selected awake screen or another awake display when the ZenScreen is absent.

## Touch indicators

`TouchIndicatorOverlay` renders keyed Core Animation layers in one transparent, nonactivating panel on the selected display. Normalized top-left controller coordinates map to AppKit's bottom-left display coordinates with the bridge's edge clamping. Existing layers move without implicit position animation; each finger has a steady center and an expanding, fading outer ring. Reduce Motion disables the pulse. Idle/lift removes all animated layers and hides the panel; Stop, display loss or disabling the option closes it. A two-second contact timeout also clears stalled reports.

The **Show touch indicators** checkbox can change while input runs, persists independently and defaults off. **--show-touch-indicators** enables it explicitly for a developer launch. The signed GUI smoke check exercises synthetic contacts, focus preservation, pulse configuration, lift, opt-out, stopped state, invalid coordinates and stale-contact cleanup without capturing touch reports or posting input. It also renders only the overlay's own layer into a sibling PNG for visual inspection.

See [the platform investigation](feasibility.md) and [the quality pass](quality-pass.md) for verified behavior and remaining limits.
