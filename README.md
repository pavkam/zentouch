<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

![ZenTouch — Multi-touch for your ZenScreen](docs/assets/readme-banner.png)

[![CI](https://github.com/pavkam/zentouch/actions/workflows/ci.yml/badge.svg)](https://github.com/pavkam/zentouch/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-4ce7c5)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-142536)
![Swift 6+](https://img.shields.io/badge/Swift-6%2B-f7a66f)

ZenTouch lets you use your ASUS touchscreen on a Mac: tap to click, drag with one finger, and scroll with two. It lives in the menu bar, so you can close Settings and get on with using the screen.

## Supported monitors

| Monitor | Support |
| --- | --- |
| **ASUS ZenScreen Touch MB16AMTR** | Tested with ZenTouch on macOS 27 |

That's the supported model today. The [full model list](docs/supported-models.md) also covers 12 other ASUS touchscreens, clearly marked **not tested**. They need compatibility testing before ZenTouch can support them. A similar model name doesn't mean the same touch controller.

You need **macOS 14 or later** and a USB connection that carries data as well as the screen's video connection. The downloadable preview is for **Apple silicon Macs**. Keep the touchscreen at **0° rotation**; rotated displays aren't supported yet.

## Install

Download the DMG from [Releases](https://github.com/pavkam/zentouch/releases), open it, and drag ZenTouch into Applications. Use that installed copy when granting permissions and updating the app.

These are preview builds, signed with the maintainer's local certificate rather than notarized by Apple. If macOS blocks the app, you can allow it through **System Settings → Privacy & Security → Open Anyway**.

**This README describes the current source build.** The downloadable 0.3 preview doesn't yet include the three-finger swipes, stationary-pointer mode, touch indicators or reconnect improvements described below. Check the [release notes](CHANGELOG.md) for differences, or [build from source](docs/development.md#build-from-source) to use the latest changes.

## First run

1. Connect your ZenScreen's **USB data cable**. A video-only connection won't send touches to the Mac.
2. Open ZenTouch. Click its menu bar icon and choose **Settings…**.
3. Use the permission buttons to allow **Input Monitoring** and **Accessibility** in System Settings. These let ZenTouch read the touchscreen and send clicks and gestures. Quit and reopen the app if macOS asks you to. Green checks show when the permissions are ready.
4. Select your ZenScreen and click **Start Touch Input**.

Touch the screen. You'll see your fingers in the Settings preview, and taps should click where you touch. By default, ZenTouch moves the mouse pointer to your touch position.

## Gestures

![One finger taps and drags; two fingers move together to scroll](docs/assets/gestures.png)

| Use your fingers to… | What happens |
| --- | --- |
| Tap with one finger | Click |
| Move one finger while touching | Drag |
| Move two fingers together | Scroll up, down, left or right |
| Tap with two fingers | Right-click |
| Hold one finger still, then lift | Right-click |
| Swipe up with three fingers, then lift | Open Mission Control |
| Swipe down with three fingers, then lift | Open App Exposé; still needs live testing |
| Swipe left or right with three fingers | Switch desktops or full-screen apps; still needs live testing |
| Pinch with two fingers | Experimental zoom gesture; app compatibility isn't verified |

Three-finger swipes are on by default. Place three fingers on the screen, move them together, then lift. Up and down trigger their action when you lift; the view doesn't follow your fingers as it does on a trackpad. Three-finger dragging isn't supported.

To change **Enable three-finger swipes** or **Enable experimental pinch**, stop touch input first, change the checkbox in Settings, then start again. Pinch is off by default. These options are separate from your Mac's trackpad settings.

## Keep the mouse pointer where it is

Stop touch input, enable **Keep pointer stationary (experimental)** in Settings, then start again. Taps, dragging and scrolling go to the window under your finger while your mouse pointer stays where you left it. Your choice is saved and used after reconnects.

This mode is still experimental. Native AppKit controls have passed a separate-process test, and tapping and scrolling have been confirmed in live use on macOS 27. Compatibility still varies by app and control. Desktop, menu bar and some menu controls may not respond. If a window closes during a drag, ZenTouch drops the remaining events rather than sending them to another app. It never switches back to moving the pointer on its own. Turn the option off to restore normal pointer behavior.

## Everyday use

The menu's **Active** checkmark is your on/off switch. You can also use **Start Touch Input / Stop Touch Input** in Settings. Closing Settings keeps touch working; **Quit ZenTouch** stops it and exits.

If the screen sleeps or disconnects, ZenTouch waits for it to return. **Active** stays checked while waiting, so input can resume without restarting the app. A slashed menu bar icon means the selected screen or its USB touch connection is missing. Open Settings or hover over the icon to see what's missing. Touch controls become available when the hardware returns. You can always stop input to cancel automatic resuming.

Want to see where your fingers are? Turn on **Show touch indicators** in Settings. Teal rings follow each touch on the screen, including with Settings closed. You can toggle them while input is running. They're off by default; macOS Reduce Motion makes them steady instead of pulsing.

## If something doesn't work

| What you see | What to try |
| --- | --- |
| No fingers in the Settings preview | Check the USB data cable, Input Monitoring permission, and that touch input is running. |
| Fingers appear, but nothing clicks | Check Accessibility permission and the selected display. |
| ZenTouch isn't listed in Privacy & Security | Use **+** to add the installed ZenTouch app, then enable it. |
| Start is disabled or the icon is slashed | Make sure the selected screen is awake and its USB data cable is connected. Settings explains which connection is missing. |
| The pointer doesn't line up with your finger | Stop input, select the correct display, and check that its rotation is 0°. |
| A control ignores stationary-pointer touch | Stop input, turn off **Keep pointer stationary (experimental)** and start again. Include the app and control in a bug report. |
| Touch stops after a forced quit | Reconnect the USB cable. A normal Stop or Quit lets ZenTouch restore the controller's previous mode. |

Still stuck? Choose **Open Logs Folder** and [open an issue](https://github.com/pavkam/zentouch/issues). Include your monitor model, macOS version and what you tried. Logs live in `~/Library/Logs/ZenTouch`; they rotate automatically and use at most 24 MiB. They include touch positions and actions from the touchscreen, so review any excerpt before sharing it.

## What works, and what still needs testing

Clicks, two-finger scrolling, three-finger Mission Control, use with Settings closed, and touch recovery after a monitor power cycle have been tested on an MB16AMTR with macOS 27. Desktop switching, App Exposé and pinch still need live testing. The latest attach/detach icon and control changes have automated coverage; physical testing is pending.

ZenTouch translates touches into mouse and scroll events. It doesn't turn the screen into an Apple trackpad or add direct-touch support to Mac apps. Stationary-pointer routing, three-finger gestures and pinch rely on undocumented macOS behavior, which can change with OS updates. See the [quality notes](docs/quality-pass.md) for the detailed test record.

## Build or contribute

The [developer guide](docs/development.md) covers building, signing, packaging and diagnostics. Start with [CONTRIBUTING.md](CONTRIBUTING.md) if you'd like to help, especially with another monitor model. There are no external runtime dependencies.

Questions go in [Discussions](https://github.com/pavkam/zentouch/discussions); bugs go in [Issues](https://github.com/pavkam/zentouch/issues). Report security problems through [private reporting](SECURITY.md).

ZenTouch is an independent project, unaffiliated with ASUS or Apple. Its code and artwork use the [MIT License](LICENSE), with [upstream notices](THIRD-PARTY-NOTICES.md) for the gesture adapters.
