<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Display models

The authoritative catalog is [supported-models.json](../Sources/ZenTouchCore/Resources/supported-models.json). The app and diagnostic helper load the same packaged file. Model names, exact display aliases, ASUS sources, advertised touch points and ZenTouch verification status belong there, rather than in display or UI code. ASUS specifications were checked on 2026-10-06; this is a researched list, not a guarantee that every regional or discontinued model is represented.

**Verified** means tested with ZenTouch and linked to an implemented controller profile. **Unverified** means ASUS documents touch capability, but ZenTouch needs a hardware capture and compatibility test. Adding a catalog entry does not supply a driver or authorize interpreting its reports with another model's decoder. The active controller still must match the captured product identity and HID descriptor exactly.

| Model | ASUS family | Advertised touch points | ZenTouch status | ASUS source |
| --- | --- | --- | --- | --- |
| MB16AMTR | ZenScreen Touch | 10 | Verified | [Specification](https://www.asus.com/displays-desktops/monitors/zenscreen/asus-zenscreen-touch-mb16amtr/) |
| MB16AMT | ZenScreen Touch | 10 | Unverified | [Specification](https://www.asus.com/us/displays-desktops/monitors/portable/zenscreen-touch-mb16amt/) |
| MB16AHT | ZenScreen Touch | 10 | Unverified | [Specification](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-touch-mb16aht/) |
| MB14AHD | ZenScreen Ink | 10 | Unverified | [Specification](https://www.asus.com/displays-desktops/monitors/zenscreen/zenscreen-ink-mb14ahd/) |
| PA148CTV | ProArt | 10 | Unverified | [Specification](https://www.asus.com/global/support/faq/1047313/) |
| PA169CDV | ProArt | 10 | Unverified | [Specification](https://www.asus.com/displays-desktops/monitors/proart/proart-display-pa169cdv/) |
| BE24ECSBT | Business | 10 | Unverified | [Specification](https://www.asus.com/displays-desktops/monitors/business/be24ecsbt/) |
| VT229H | Touch | 10 | Unverified | [Specification](https://www.asus.com/global/support/faq/1047313/) |
| VT168HR | Touch | 10 | Unverified | [Specification](https://www.asus.com/displays-desktops/monitors/touch/vt168hr/) |
| VT168H | Touch (legacy) | 10 | Unverified | [Specification](https://www.asus.com/global/support/faq/1047313/) |
| VT168N | Touch (legacy) | 10 | Unverified | [Specification](https://www.asus.com/global/support/faq/1047313/) |
| VT207N | Touch (legacy) | 10 | Unverified | [Specification](https://www.asus.com/event/2016/productguide/id/Product%20Guide%20monitor_projector%202016_issue01.pdf) |
| XG129C | ROG Strix | 10 | Unverified | [Specification](https://rog.asus.com/au/monitors/accessories/rog-strix-xg129c/) |

Display matching uses complete model tokens, ignoring case and punctuation. A shorter model name cannot match a longer model sharing its prefix. Unverified entries are recognized for research but never selected automatically for input. A saved display UUID remains authoritative across reconnects; its disappearance cannot redirect input to another display.

To add support, add or update the catalog entry, capture the controller identity and descriptor, implement or confirm its protocol profile, then verify contacts, input, disconnect and reconnect on the actual hardware before marking it verified. The catalog loader rejects duplicate names/aliases, invalid touch counts, unsupported schema versions, unofficial source URLs and invalid controller-profile associations.

Inspect the installed catalog without touching hardware:

```sh
~/Applications/ZenTouch.app/Contents/Helpers/zentouch-cli models
```
