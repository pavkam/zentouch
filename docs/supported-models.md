<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Supported monitors

**ZenTouch currently supports the ASUS ZenScreen Touch MB16AMTR.** It's the monitor we've tested with the app. Connect its USB data cable and keep the display at 0° rotation; see the [setup guide](../README.md#first-run) to get started.

| Tested model | ASUS family | More about the monitor |
| --- | --- | --- |
| **MB16AMTR** | ZenScreen Touch | [ASUS product page](https://www.asus.com/displays-desktops/monitors/zenscreen/asus-zenscreen-touch-mb16amtr/) |

Clicks, two-finger scrolling, three-finger Mission Control and recovery after turning the monitor off and on have been confirmed on macOS 27. Some gestures still need testing; the [README](../README.md#gestures) explains which ones.

## Other ASUS touchscreens — not tested yet

ASUS documents touch input for these models, but **they aren't supported by ZenTouch yet**. They appear in our model catalog so we can track future compatibility work. Listing them doesn't give the app a driver for their controller.

| Model | ASUS family | ASUS source |
| --- | --- | --- |
| MB16AMT | ZenScreen Touch | [Product page](https://www.asus.com/us/displays-desktops/monitors/portable/zenscreen-touch-mb16amt/) |
| MB16AHT | ZenScreen Touch | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-touch-mb16aht/) |
| MB14AHD | ZenScreen Ink | [Product page](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-ink-mb14ahd/) |
| PA148CTV | ProArt | [Touchscreen FAQ](https://www.asus.com/global/support/faq/1047313/) |
| PA169CDV | ProArt | [Product page](https://www.asus.com/displays-desktops/monitors/proart/proart-display-pa169cdv/) |
| BE24ECSBT | Business | [Product page](https://www.asus.com/displays-desktops/monitors/business/be24ecsbt/) |
| VT229H | Touch | [Touchscreen FAQ](https://www.asus.com/global/support/faq/1047313/) |
| VT168HR | Touch | [Product page](https://www.asus.com/displays-desktops/monitors/touch/vt168hr/) |
| VT168H | Touch (legacy) | [Touchscreen FAQ](https://www.asus.com/global/support/faq/1047313/) |
| VT168N | Touch (legacy) | [Touchscreen FAQ](https://www.asus.com/global/support/faq/1047313/) |
| VT207N | Touch (legacy) | [2016 monitor brochure (PDF)](https://www.asus.com/event/2016/productguide/id/Product%20Guide%20monitor_projector%202016_issue01.pdf) |
| XG129C | ROG Strix | [Product page](https://rog.asus.com/au/monitors/accessories/rog-strix-xg129c/) |

ASUS lists ten touch points for each monitor in this catalog. That describes the hardware's advertised capability, not the gestures ZenTouch has verified. The ASUS sources were checked on **6 October 2026**; this list may not include every regional or discontinued model.

## Have another model?

[Open an issue](https://github.com/pavkam/zentouch/issues) with its exact model name and your macOS version. We need to identify its USB touch controller and test its reports on real hardware before adding support. If you're comfortable working on that, start with the [developer guide](development.md#adding-a-monitor-model).

Model names and test status live in one [catalog file](../Sources/ZenTouchCore/Resources/supported-models.json), shared by the app and diagnostic helper. In that file, `verified` means tested with ZenTouch and linked to an implemented controller profile; `unverified` means compatibility work is still needed.
