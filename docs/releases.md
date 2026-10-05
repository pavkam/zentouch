<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Releases

Public preview binaries currently use the maintainer's stable local signing certificate and are not notarized. CI's ephemeral identity is for package tests only. Do not distribute its artifacts as a release or replace an installed working app with them.

1. Update the app's version/build in `Resources/Info.plist`, CLI version strings and `CHANGELOG.md`.
2. Run `make check` and `make package` with the stable maintainer identity. Verify the installed menu bar, grants and hardware behavior separately.
3. Commit the release, wait for all CI checks, and tag that exact commit with `v<version>`.
4. Push the tag. The release workflow checks the version and creates a **draft source release**.
5. Attach the locally verified DMG, ZIP and SHA-256 manifest to that draft. Include the supported controller, architecture, actual hardware checks and signing/notarization status in the notes. Publish 0.x previews as prereleases.

Changing the distributed signing identity can invalidate existing privacy grants. A Developer ID/notarized release needs an explicit signing migration and a secure release-signing workflow; neither should export the local development private key into this repository.
