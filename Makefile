# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

.PHONY: check build package install format artwork

check:
	./scripts/check.sh

build:
	./scripts/build-app.sh

package: check
	./scripts/package-app.sh

install: build
	python3 scripts/install-app.py

format:
	xcrun swift-format format --in-place --recursive Sources Tests Package.swift Resources/Branding/Artwork.swift

artwork:
	swift Resources/Branding/Artwork.swift .build/artwork
	cp .build/artwork/app-icon.png .build/artwork/readme-banner.png .build/artwork/gestures.png docs/assets/
