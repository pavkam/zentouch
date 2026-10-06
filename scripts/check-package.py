#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Verify archived releases after relocation, without opening the touch controller."""
import hashlib
import pathlib
import plistlib
import subprocess
import tempfile
import time

repo = pathlib.Path(__file__).resolve().parent.parent
with (repo / "dist/ZenTouch.app/Contents/Info.plist").open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
architecture = subprocess.check_output(["uname", "-m"], text=True).strip()
release = repo / "dist" / f"ZenTouch-{version}-{architecture}"


def artifact(extension):
    return pathlib.Path(str(release) + extension)


for line in artifact(".sha256").read_text().splitlines():
    digest, name = line.split(maxsplit=1)
    assert pathlib.Path(name).name == name, f'Checksum must use a downloadable artifact basename: {name}'
    file = repo / 'dist' / name
    assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, f"Checksum mismatch: {name}"


def verify(app):
    subprocess.run(["python3", str(repo / "scripts/verify-bundle.py"), str(app)], check=True)
    arches = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/ZenTouch")], text=True).split()
    assert arches == [architecture], f"Unexpected release architecture: {arches}"


def detach_validation_mount(mount):
    # macOS may briefly hold a relocated app after signature/resource checks.
    for attempt in range(3):
        try:
            result = subprocess.run(
                ["hdiutil", "detach", str(mount)], capture_output=True, text=True, timeout=30,
            )
            if result.returncode == 0:
                return
        except subprocess.TimeoutExpired:
            pass
        if attempt < 2:
            time.sleep(1)
    # Only our private, read-only validation mount is eligible for forced cleanup.
    subprocess.run(
        ["hdiutil", "detach", "-force", str(mount)], check=True, timeout=30, stdout=subprocess.DEVNULL,
    )


with tempfile.TemporaryDirectory(prefix="zentouch-release-") as directory:
    root = pathlib.Path(directory)
    extracted = root / "zip"
    subprocess.run(["ditto", "-x", "-k", str(artifact(".zip")), str(extracted)], check=True)
    app = extracted / "ZenTouch.app"
    verify(app)
    # A packaged helper must fail cleanly instead of falling back to development resources.
    profile = app / "Contents/Resources/exc3200-descriptor.bin"
    captured_profile = profile.read_bytes()
    profile.unlink()
    result = subprocess.run(
        [str(app / "Contents/Helpers/zentouch-cli"), "self-check"],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 1 and "controller profile is missing" in result.stderr, result
    profile.write_bytes(captured_profile)
    (app / "Contents/Resources/supported-models.json").unlink()
    result = subprocess.run(
        [str(app / "Contents/Helpers/zentouch-cli"), "self-check"],
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 1 and "model catalog is missing or invalid" in result.stderr, result
    mount = root / "dmg"
    mount.mkdir()
    subprocess.run(
        ["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(artifact(".dmg"))],
        check=True, stdout=subprocess.DEVNULL,
    )
    try:
        verify(mount / "ZenTouch.app")
        assert (mount / "Applications").is_symlink()
        assert (mount / "Applications").readlink() == pathlib.Path("/Applications")
        for name in ("LICENSE", "README.md", "THIRD-PARTY-NOTICES.md", "docs/quality-pass.md", "docs/feasibility.md"):
            assert (mount / name).is_file(), f"Missing release documentation: {name}"
    finally:
        detach_validation_mount(mount)
print("PASS DMG/ZIP relocation, signatures, resources, architecture, checksums and missing-profile/catalog recovery")
