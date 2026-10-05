<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Changelog

## 0.4.0 — unreleased

- Add three-finger desktop, Mission Control and App Exposé swipes using native phased Dock events.
- Include the raw IOHID payload required by macOS 27, isolated from public mouse/scroll posting.
- Recognize sequential finger placement and suppress residual contacts after lift or cancellation.
- Add a saved Settings toggle, per-phase swipe logs and active Space change diagnostics.
- Add recognition, cancellation, event encoding and session failure tests (44 checks total).
- Live native swipe confirmation remains pending.

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
