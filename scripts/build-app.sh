#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

set -euo pipefail
cd "${0:A:h:h}"

zentouch_signing_identity=$(python3 - <<'PY'
import os, pathlib, re, subprocess, sys
pin = pathlib.Path('.zentouch-signing-identity')
result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], check=True, capture_output=True, text=True)
identities = re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"', result.stdout, re.M)
requested = os.environ.get('ZENTOUCH_SIGNING_IDENTITY', '')
pinned = pin.read_text().strip() if pin.exists() else ''
if requested:
    matches = [sha for sha, name in identities if requested.upper() == sha.upper() or requested == name]
    if len(matches) != 1:
        sys.exit('ZENTOUCH_SIGNING_IDENTITY must name exactly one valid existing signing identity.')
    selected = matches[0]
    if pinned and selected.upper() != pinned.upper():
        sys.exit('The requested key differs from the pinned signing key. Refusing to invalidate existing permissions.')
elif pinned:
    if pinned.upper() not in [sha.upper() for sha, _ in identities]:
        sys.exit('The pinned signing identity is unavailable. Restore it before rebuilding; no ad-hoc fallback is allowed.')
    selected = pinned
elif len(identities) == 1:
    selected = identities[0][0]
else:
    sys.exit('Select a valid local signing key with ZENTOUCH_SIGNING_IDENTITY. This app requires stable certificate signing.')
if not pinned:
    pin.write_text(selected + '\n')
print(selected)
PY
)

swift build --build-system native -c release --product ZenTouch -Xswiftc -warnings-as-errors
swift build --build-system native -c release --product zentouch-cli -Xswiftc -warnings-as-errors
zentouch_bin_dir=$(swift build --build-system native -c release --show-bin-path)
zentouch_stage="$PWD/.build/package"
zentouch_app="$zentouch_stage/ZenTouch.app"
rm -rf "$zentouch_stage"
mkdir -p "$zentouch_app/Contents/MacOS" "$zentouch_app/Contents/Resources" "$zentouch_app/Contents/Helpers"
cp "$zentouch_bin_dir/ZenTouch" "$zentouch_app/Contents/MacOS/ZenTouch"
cp "$zentouch_bin_dir/zentouch-cli" "$zentouch_app/Contents/Helpers/zentouch-cli"
cp Resources/Info.plist "$zentouch_app/Contents/Info.plist"
cp Sources/ZenTouchCore/Resources/exc3200-descriptor.bin "$zentouch_app/Contents/Resources/"
cp LICENSE THIRD-PARTY-NOTICES.md Resources/ZenTouchHelp.html "$zentouch_app/Contents/Resources/"
swift Resources/Branding/Artwork.swift "$zentouch_stage/artwork"
iconutil -c icns "$zentouch_stage/artwork/ZenTouch.iconset" -o "$zentouch_app/Contents/Resources/ZenTouch.icns"
cp "$zentouch_stage/artwork/MenuBarTemplate.png" "$zentouch_app/Contents/Resources/"
codesign --force --sign "$zentouch_signing_identity" --timestamp=none --options runtime --identifier org.pavkam.zentouch.cli "$zentouch_app/Contents/Helpers/zentouch-cli"
codesign --force --sign "$zentouch_signing_identity" --timestamp=none --options runtime --identifier org.pavkam.zentouch "$zentouch_app"
python3 scripts/verify-bundle.py "$zentouch_app"
mkdir -p dist
rm -rf dist/ZenTouch.app
ditto "$zentouch_app" dist/ZenTouch.app
print "Built $PWD/dist/ZenTouch.app"
