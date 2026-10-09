<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Supported monitors

**ZenTouch currently supports the ASUS ZenScreen Touch MB16AMTR.** It's the monitor we've tested with the app. Connect its USB data cable and keep the display at 0° rotation; see the [setup guide](../README.md#first-run) to get started.

| Product | ZenTouch status | ASUS source |
| --- | --- | --- |
| **ASUS ZenScreen Touch MB16AMTR** | Tested and supported | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/asus-zenscreen-touch-mb16amtr/) |

Clicks, two-finger scrolling, pinch to zoom, three-finger Mission Control and recovery after turning the monitor off and on have been confirmed on macOS 27. Some gestures still need testing; the [README](../README.md#gestures) explains which ones.

## Other ASUS touchscreens — not tested yet

These 14 monitors are potential candidates because ASUS documents ten-point touch for them. **Their compatibility with ZenTouch is unknown, and the current app doesn't enable them.** We haven't captured their USB controller identities or HID reports; they may need a new controller profile. Their catalog entries track that work and don't establish driver support.

| Product | ZenTouch status | ASUS source |
| --- | --- | --- |
| ASUS ZenScreen Touch MB16AMT | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-touch-mb16amt/) |
| ASUS ZenScreen Touch MB16AHT | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-touch-mb16aht/) |
| ASUS ZenScreen Ink MB14AHD | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-ink-mb14ahd/) |
| ASUS ProArt Display PA148CTV | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/proart/proart-display-pa148ctv/) |
| ASUS ProArt Display PA147CDV Creative Tool | Potential — untested | [Product page](https://www.asus.com/us/displays-desktops/monitors/proart/proart-display-pa147cdv/) |
| ASUS ProArt Display PA169CDV | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/proart/proart-display-pa169cdv/) |
| ASUS BE24ECSBT Multi-touch Monitor | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/business/be24ecsbt/) |
| ASUS VT229H Touch Monitor | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/touch/vt229h/) |
| ASUS VT169HE Touch Monitor | Potential — untested | [Product page](https://www.asus.com/displays-desktops/monitors/touch/vt169he/) |
| ASUS VT168HR Touch Monitor | Potential — untested | [Product page](https://www.asus.com/us/displays-desktops/monitors/touch/vt168hr/) |
| ASUS VT168H Touch Monitor | Potential — untested, discontinued | [Touchscreen FAQ](https://www.asus.com/support/faq/1047313/) |
| ASUS VT168N Touch Monitor | Potential — untested, discontinued | [Touchscreen FAQ](https://www.asus.com/support/faq/1047313/) |
| ASUS VT207N Touch Monitor | Potential — untested, legacy | [Product page](https://www.asus.com/uk/displays-desktops/monitors/all-series/vt207n/) |
| ROG Strix XG129C Touchscreen Gaming Monitor | Potential — untested | [Product page](https://rog.asus.com/au/monitors/accessories/rog-strix-xg129c/) |

ASUS lists ten touch points for each monitor in this catalog. That describes the hardware's advertised capability, not the gestures ZenTouch has verified. The ASUS sources were rechecked on **9 October 2026**, including the [ASUS Touch range](https://www.asus.com/us/displays-desktops/monitors/touch/filter?Series=Touch), ProArt and ZenScreen product pages, and ROG's touchscreen page. This pass adds PA147CDV and VT169HE; the list may not include every regional or discontinued model.

The Ink and ProArt entries refer to finger touch only. Pen input, pressure sensitivity, ASUS Dial and ASUS Control Panel integration aren't implemented by ZenTouch.

## Have another model?

[Open an issue](https://github.com/pavkam/zentouch/issues) with its exact model name and your macOS version. We need to identify its USB touch controller and test its reports on real hardware before adding support. If you're comfortable working on that, start with the [developer guide](development.md#adding-a-monitor-model).

Model names and test status live in one [catalog file](../Sources/ZenTouchCore/Resources/supported-models.json), shared by the app and diagnostic helper. In that file, `verified` means tested with ZenTouch and linked to an implemented controller profile; `unverified` means compatibility work is still needed.
