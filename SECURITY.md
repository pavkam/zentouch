<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Security

ZenTouch reads the supported USB touch controller and posts mouse/scroll events after macOS grants permission. Permission handling, input cancellation, controller matching and bundled-code integrity are security-relevant.

Report a vulnerability through [GitHub's private vulnerability reporting](https://github.com/pavkam/zentouch/security/advisories/new). Include the affected version, reproduction steps and expected impact. Do not put private logs or signing material in public issues.

The current 0.x preview is maintained on `main`; fixes target the latest preview. Earlier previews have no separate support branch. This project does not currently promise response times.

CI has read-only permissions except the job creating draft releases. Pull requests do not receive signing credentials. Package checks use an ephemeral certificate on a disposable GitHub-hosted runner; that identity is never used for a distributed release.
