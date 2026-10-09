#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Assign main builds a unique patch version without committing generated files."""
import argparse
import pathlib
import plistlib
import re


def set_version(root, run_number):
    if not re.fullmatch(r"[1-9][0-9]{0,8}", run_number):
        raise ValueError("Run number must be a positive integer of at most nine digits")
    plist = root / "Resources/Info.plist"
    source = root / "Sources/ZenTouchCore/AppVersion.swift"
    info = plistlib.loads(plist.read_bytes())
    base = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", base):
        raise ValueError("Source version must have three numeric components")
    major, minor, patch = base.split(".")
    version = f"{major}.{minor}.{int(patch) + int(run_number)}"
    text = source.read_text()
    declaration = f'public static let current = "{base}"'
    if text.count(declaration) != 1:
        raise ValueError("Source and bundle versions disagree")
    # Preserve the plist's comments, including its SPDX header.
    xml = plist.read_text()
    for key, value in (("CFBundleShortVersionString", version), ("CFBundleVersion", run_number)):
        xml, count = re.subn(
            rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)",
            lambda match: match[1] + value + match[2], xml)
        if count != 1:
            raise ValueError(f"Expected exactly one {key}")
    plist.write_text(xml)
    source.write_text(text.replace(declaration, f'public static let current = "{version}"'))
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_number")
    args = parser.parse_args()
    print(set_version(pathlib.Path(__file__).resolve().parent.parent, args.run_number))
