#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Validate the shipped app, including nested code and actual executable names."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
with (app / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
expected = {
    "CFBundleName": "ZenTouch",
    "CFBundleDisplayName": "ZenTouch",
    "CFBundleIdentifier": "org.pavkam.zentouch",
    "CFBundleExecutable": "ZenTouch",
    "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "ZenTouch.icns",
    "LSUIElement": True,
    "LSMultipleInstancesProhibited": True,
    "LSApplicationCategoryType": "public.app-category.utilities",
    "NSPrincipalClass": "NSApplication",
}
for key, value in expected.items():
    if info.get(key) != value:
        sys.exit(f"Invalid bundle metadata: {key}")
for key in ("CFBundleVersion", "CFBundleShortVersionString", "NSHumanReadableCopyright", "NSInputMonitoringUsageDescription"):
    if not info.get(key):
        sys.exit(f"Missing metadata: {key}")
for relative in (
    "Contents/MacOS/ZenTouch",
    "Contents/Helpers/zentouch-cli",
    "Contents/Resources/ZenTouch.icns",
    "Contents/Resources/MenuBarTemplate.png",
    "Contents/Resources/ZenTouchHelp.html",
    "Contents/Resources/THIRD-PARTY-NOTICES.md",
    "Contents/Resources/LICENSE",
    "Contents/Resources/exc3200-descriptor.bin",
):
    if not (app / relative).is_file() or (app / relative).stat().st_size == 0:
        sys.exit(f"Missing bundle content: {relative}")
if len((app / "Contents/Resources/exc3200-descriptor.bin").read_bytes()) != 559:
    sys.exit("Wrong HID profile resource")
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--strict", str(app / "Contents/Helpers/zentouch-cli")], check=True)
version = subprocess.check_output([str(app / "Contents/Helpers/zentouch-cli"), "--version"], text=True, timeout=10).strip()
if version != f"ZenTouch CLI {info['CFBundleShortVersionString']}":
    sys.exit("GUI and CLI versions disagree")
app_version = subprocess.check_output([str(app / "Contents/MacOS/ZenTouch"), "--version"], text=True, timeout=10).strip()
if app_version != f"ZenTouch {info['CFBundleShortVersionString']}":
    sys.exit("GUI executable is missing or reports the wrong version")
profile = subprocess.check_output([str(app / "Contents/Helpers/zentouch-cli"), "self-check"], text=True, timeout=10).strip()
if profile != "ZenTouch CLI: controller profile verified (559 bytes)":
    sys.exit("Nested CLI cannot load the packaged controller profile")
print(f"PASS ZenTouch {info['CFBundleShortVersionString']} bundle metadata, resources and signatures")
