<!--
SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
SPDX-License-Identifier: MIT
-->

# Contributing to ZenTouch

Small, focused changes are welcome. Include the behavior you changed and how you verified it. Hardware support needs captured report fixtures and an exact descriptor; the model name alone is insufficient.

1. Fork and clone the repository. Install Apple Command Line Tools with `xcode-select --install` if needed. Swift 6 or newer is required.
2. Run `make check`. This builds all targets, checks formatting, licensing and repository files, and runs the standalone tests. Full Xcode is optional.
3. Make the change and run `make format` followed by `make check`.
4. For UI or packaging changes, build with your own stable code-signing identity and run the packaged smoke check described in [development.md](docs/development.md).
5. Open a pull request. CI checks macOS 15 and 26 and verifies a disposable signed package on macOS 26.

## Signing and hardware

Never commit a private key, certificate export, signing pin, capture directory or user log. Builds pin the selected public certificate fingerprint locally. Reuse that key for updates to retain permissions; don't replace the installed app with a CI artifact signed by a disposable identity.

Unit checks use injected readers and event sinks; they do not control the user's Mac. Live hardware tests require the supported controller and macOS grants. Record which device, OS and gestures you actually tested. Synthetic success is not a substitute for a hardware claim.

## License and artwork

Contributions use the [MIT License](LICENSE). Keep SPDX headers and upstream attribution. Non-commentable files use adjacent `.license` files; `scripts/check-repository.py` verifies coverage.

`Resources/Branding/Artwork.swift` is the editable source for the app and README graphics. Run `make artwork` after changing it. The generated repository PNGs are committed so GitHub can render them without a build.

See [the code of conduct](CODE_OF_CONDUCT.md). Report security problems privately as described in [SECURITY.md](SECURITY.md).
