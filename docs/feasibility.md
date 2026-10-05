<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# ZenScreen multi-touch on macOS

An app can read this screen's touch reports and translate them into macOS input. Exact Apple-trackpad behavior remains a separate investigation.

## Hardware evidence

The live IORegistry exposed one USB HID device with these properties on 2026-10-05:

| Property | Value |
| --- | --- |
| Display | ASUS MB16AMTR, 1920×1080 |
| Controller | eGalaxTouch EXC3200-2505-09.00.00.00 |
| Vendor / product | 0x0eef / 0xc000 |
| Primary usage | Digitizer / Touch Screen (0x0d / 0x04) |
| Maximum input buffer | 64 bytes |
| Contact coordinate range | 0…4095 on each axis |
| Multi-touch report | ID 6, 56 declared bytes including ID |
| Mode feature report | ID 5, Device Mode and Device Identifier |

Report 6 starts with a report ID and contact count. Each of its five finger collections occupies ten bytes: one tip-switch byte, one contact-ID byte, two little-endian X bytes, two Y bytes and four reserved bytes. A four-byte scan time follows the slots. More than five contacts require hybrid-frame assembly across packets; that interpretation needs confirmation with live six-to-ten-finger captures.

[ASUS advertises ten-point touch for this model and single-point macOS support](https://www.asus.com/uk/displays-desktops/monitors/zenscreen/asus-zenscreen-touch-mb16amtr/). The advertised capability isn't proof of the attached controller's runtime behavior.

[Microsoft defines HID Device Mode 0 as mouse, 1 as single input and 2 as multiple input](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/using-report-descriptors-to-support-capability-discovery). That gives us a standard mode-switch experiment, with the original mode retained for cleanup.

## Translation app

The first route is `IOHIDManager → report decoder → complete contact frames → gesture recognizer → CGEvent`.

[Core Graphics documents mouse, keyboard and scroll event creation and system event posting](https://developer.apple.com/documentation/coregraphics/cgevent). The app requires macOS permission to read the controller and Accessibility permission to post events. It can map absolute coordinates to the ZenScreen's display bounds without a kernel extension.

[Touch-Up implements this approach for touchscreens](https://github.com/shueber/Touch-Up). Its pinch emitter uses private gesture fields. [macos-trackpad-companion](https://github.com/scottlamb/macos-trackpad-companion) demonstrates a more elaborate gesture event serializer and animated Dock swipes, while explicitly describing its implementation as a prototype. These are useful primary-source implementations, not a supported Apple contract.

The local implementation uses public mouse/scroll posting and isolates a small experimental pinch adapter. It doesn't silently replace a pinch with a keyboard zoom shortcut.

## Virtual trackpad

[CoreHID can create virtual HID devices](https://developer.apple.com/documentation/corehid/creatingvirtualdevices), and Apple documents the [virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device). Publishing a generic HID touchpad is not evidence that Apple's gesture stack will treat it as a Magic Trackpad.

A [developer's report on Apple's forums](https://developer.apple.com/forums/thread/768586) describes standard touchpad reports reaching the HID stack without producing gestures, both with Apple's default driver and a custom DriverKit driver. This is a concrete counterexample to assuming that a generic virtual trackpad descriptor is sufficient. It doesn't prove that every virtual-device route is impossible.

This route needs an independently verified report format and driver binding, plus an authorized entitlement/signing path. It isn't necessary for the translation app and shouldn't gate testing the screen.

## macOS 27 direct touch

The attached Mac runs macOS 27. Apple now documents [direct Sidecar touch input through AppKit gesture recognizers](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support). That changes the old blanket claim that macOS has no direct touch support.

The documented APIs describe receiving Sidecar touches. They don't document a producer API for third-party USB touchscreen drivers. Feeding the ZenScreen into that pipeline is an unresolved experiment; the current bridge doesn't claim to do so.

## Next live experiments

1. Extend verified one-, two-, three-finger and lift capture to six-to-ten fingers. The first successful live test decoded 1,370 report-6 frames without errors. Feature report 5 writes succeed but its readback remains mode 0 despite simultaneous contacts, so input packets confirm multi-touch. Verify restoration after stopping.
2. Verify pointer alignment at all four corners of the ZenScreen and exclusive access without duplicate mouse clicks.
3. Verify tap, drag cancellation, two-finger scroll, sequential finger lift and unplug during a drag.
4. Test the experimental pinch adapter in Safari, Preview, Photos and Maps. If gesture recognizers reject it, implement and validate the serialized HID gesture payload separately.
5. Investigate the macOS 27 direct-touch producer path and virtual trackpad binding only against live evidence; neither is established by this prototype.

The hardware descriptor gives us a concrete input path. Native trackpad parity remains unverified.
