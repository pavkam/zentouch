#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Publish verified main artifacts; safely resume an interrupted draft on rerun."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess


class GitHub:
    def call(self, *args):
        result = subprocess.run(["gh", *args], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout

    def optional(self, *args):
        try:
            return json.loads(self.call(*args))
        except RuntimeError as error:
            if "404" in str(error) or "release not found" in str(error).lower():
                return None
            raise


def verify_archives(directory, version):
    stem = f"ZenTouch-{version}-arm64"
    paths = [directory / f"{stem}{suffix}" for suffix in (".dmg", ".zip", ".sha256")]
    if any(not path.is_file() or path.stat().st_size == 0 for path in paths):
        raise ValueError("Release requires nonempty DMG, ZIP and SHA-256 manifest")
    expected = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths[:2]}
    actual = {}
    for line in paths[2].read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64})  ([^/\\]+)", line)
        if not match or match[2] in actual:
            raise ValueError("Invalid checksum manifest")
        actual[match[2]] = match[1]
    if actual != expected:
        raise ValueError("Archive checksums do not match")
    return paths


def publish(gh, repo, version, sha, directory):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Expected numeric version and full commit SHA")
    paths = verify_archives(directory, version)
    tag = f"v{version}"
    ref = gh.optional("api", f"repos/{repo}/git/ref/tags/{tag}")
    if ref and (ref["object"]["type"] != "commit" or ref["object"]["sha"] != sha):
        raise ValueError("Existing release tag points to a different commit")
    release = gh.optional("api", f"repos/{repo}/releases/tags/{tag}")
    if release and not ref and release["target_commitish"] != sha:
        raise ValueError("Existing draft targets a different commit")
    if release and not release["draft"]:
        if not ref or {path.name for path in paths} != {asset["name"] for asset in release["assets"]}:
            raise ValueError("Published release has unexpected assets; refusing to modify it")
        remote = {asset["name"]: asset.get("digest") for asset in release["assets"]}
        for path in paths:
            if remote[path.name] != "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest():
                raise ValueError("Published release asset differs; refusing to modify it")
        print(f"Release {tag} is already published; nothing changed.")
        return
    if not release:
        gh.call("release", "create", tag, "--repo", repo, "--target", sha, "--draft",
                "--title", f"ZenTouch {version}", "--generate-notes", "--notes",
                "Apple silicon · macOS 14 or later. Open the DMG and drag ZenTouch into Applications. "
                "These builds use the same maintainer signing certificate across updates, preserving "
                "existing permissions when you replace the installed copy. They are not notarized by Apple. "
                "If macOS blocks the app, use System Settings → Privacy & Security → Open Anyway.")
    gh.call("release", "upload", tag, *map(str, paths), "--repo", repo, "--clobber")
    gh.call("release", "edit", tag, "--repo", repo, "--draft=false")
    print(f"Published https://github.com/{repo}/releases/tag/{tag}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--directory", type=pathlib.Path, default=pathlib.Path("dist"))
    args = parser.parse_args()
    publish(GitHub(), args.repo, args.version, args.sha, args.directory)
