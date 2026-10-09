<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# ZenTouch screenshots

These are real ZenTouch 0.5.0 windows captured on macOS 27. The three Settings tabs show a connected screen with touch input active; the menu shows the same Active state and granted permissions. They aren't mockups. The images retain the system appearance and the app's actual saved options.

| Image | Shows |
| --- | --- |
| [Touch](settings-touch.png) | Display selection, live surface, stationary pointer and touch indicators |
| [Gestures](settings-gestures.png) | Six independent switches and animated examples |
| [App](settings-app.png) | Launch at login and permission checks |
| [Menu](menu.png) | Active, Settings, permissions, logs, Help and Quit |

After installing a signed build, quit ZenTouch and reopen it with:

```sh
open ~/Applications/ZenTouch.app --args --capture-media "$PWD/.build/media-capture"
```

The developer-only export requires macOS 14.4 or later. It selects each tab, opens the menu, saves PNGs and restores the previously selected tab. It doesn't change saved gesture choices. ScreenCaptureKit's `currentProcess` API limits capture to ZenTouch's own windows; it neither requests Screen Recording permission nor captures other apps or the desktop. Check `capture-result.txt` or `capture-error.txt` before replacing the images. Review every image for private information before publishing.

The same PNGs are copied into the app's local Help. Keep filenames and captions in README and Help in sync when updating them. Screenshot sidecars declare the MIT license.
