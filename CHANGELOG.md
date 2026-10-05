<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Changelog

## 0.4.0 — unreleased

- Add optional pulsating touch indicators on the selected ZenScreen. The overlay follows each finger, lets clicks pass through, stays visible with Settings closed and clears on lift, Stop, disconnect or stalled input. Respect Reduce Motion and save the setting.
- Simplify Settings to one Start/Stop button and a live touch preview. Remove contact-test controls and report/frame counters from the UI, fit the window to its contents and use the preview to fill extra height when resized.
- Add three-finger desktop, Mission Control and App Exposé swipes using native Dock gestures and commands.
- Include the raw IOHID payload required by macOS 27, isolated from public mouse/scroll posting.
- Recognize sequential finger placement and suppress residual contacts after lift or cancellation.
- Add a saved Settings toggle, per-phase swipe logs and active Space change diagnostics.
- Restore input after monitor power saving or USB/display loss without restarting the app. Keep independent HID discovery open while capture stops, preserve Active intent, back off reopen failures and match the selected screen by stable UUID.
- Add recognition, cancellation, event encoding, session failure and wake/reconnect tests (51 checks total).
- Use the Dock’s native commands for vertical swipes on lift; avoid the unresponsive animated vertical event path. Short, reversed or cancelled swipes do not toggle Mission Control.
- Three-finger swipe up opening Mission Control and touch recovery after a monitor power cycle are confirmed on the attached MB16AMTR. Desktop switching and App Exposé still need live confirmation.

## 0.3.0 — 2026-10-05

- Replace separate menu status and stop/enable entries with one checked **Active** toggle.
- Make contact testing a separate checked toggle that can also stop a test.
- Add matching app icon, README banner and gesture illustrations from editable artwork.
- Publish the project under MIT with file headers, build instructions and contributor docs.
- Add macOS CI, archive checks, dependency updates and repository protection.

## 0.2.0 — 2026-10-05

- Move the working bridge into a persistent menu bar app with Settings.
- Split protocol, macOS, GUI and CLI sources; add 33 checks and real report fixtures.
- Add bounded, thread/process-safe JSON logging and lifecycle recovery.
- Package the app, helper, help and notices as signed app, DMG and ZIP.
- Preserve Input Monitoring and Accessibility grants across stable-key updates.

Clicks, scrolling and operation with Settings closed are confirmed on the attached MB16AMTR. Native trackpad parity and experimental pinch remain unverified.
