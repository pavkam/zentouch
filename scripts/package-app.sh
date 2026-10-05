#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-app.sh
zentouch_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/ZenTouch.app/Contents/Info.plist)
zentouch_arch=$(uname -m)
zentouch_name="ZenTouch-${zentouch_version}-${zentouch_arch}"
zentouch_dmg_stage="$PWD/.build/dmg"
rm -rf "$zentouch_dmg_stage"
mkdir -p "$zentouch_dmg_stage"
ditto dist/ZenTouch.app "$zentouch_dmg_stage/ZenTouch.app"
ln -s /Applications "$zentouch_dmg_stage/Applications"
cp LICENSE README.md THIRD-PARTY-NOTICES.md CHANGELOG.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md "$zentouch_dmg_stage/"
ditto docs "$zentouch_dmg_stage/docs"
hdiutil create -volname "ZenTouch ${zentouch_version}" -srcfolder "$zentouch_dmg_stage" -format UDZO -ov "dist/${zentouch_name}.dmg"
hdiutil verify "dist/${zentouch_name}.dmg"
ditto -c -k --sequesterRsrc --keepParent dist/ZenTouch.app "dist/${zentouch_name}.zip"
(
    cd dist
    shasum -a 256 "${zentouch_name}.dmg" "${zentouch_name}.zip" > "${zentouch_name}.sha256"
)
python3 scripts/check-package.py
print "Packaged $PWD/dist/${zentouch_name}.dmg"
