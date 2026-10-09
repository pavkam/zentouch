#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Exercise version assignment and interrupted publishing without network access."""
import contextlib
import hashlib
import importlib.util
import io
import pathlib
import plistlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


versioning = load("set-ci-version")
publishing = load("publish-release")


class FakeGitHub:
    def __init__(self, paths):
        self.calls = []
        self.ref = None
        self.release = None
        self.fail_upload = False
        self.paths = paths

    def optional(self, *args):
        return self.ref if "/git/ref/" in args[1] else self.release

    def call(self, *args):
        self.calls.append(args)
        if args[:2] == ("release", "create"):
            self.release = {"draft": True, "assets": [], "target_commitish": "a" * 40}
        elif args[:2] == ("release", "upload"):
            if self.fail_upload:
                raise RuntimeError("Interrupted upload")
            self.release["assets"] = [
                {"name": p.name, "digest": "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in self.paths]
        elif args[:2] == ("release", "edit"):
            self.release["draft"] = False
            self.ref = {"object": {"type": "commit", "sha": "a" * 40}}


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.paths = [self.root / f"ZenTouch-0.4.123-arm64{suffix}" for suffix in (".dmg", ".zip", ".sha256")]
        for path in self.paths[:2]:
            path.write_bytes(b"signed archive fixture " + path.suffix.encode())
        self.paths[2].write_text("".join(
            f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in self.paths[:2]))
        self.gh = FakeGitHub(self.paths)

    def publish(self):
        with contextlib.redirect_stdout(io.StringIO()):
            publishing.publish(self.gh, "pavkam/zentouch", "0.4.123", "a" * 40, self.root)

    def test_upload_failure_keeps_draft_and_retry_reuses_it(self):
        self.gh.fail_upload = True
        with self.assertRaises(RuntimeError):
            self.publish()
        self.assertTrue(self.gh.release["draft"])
        self.assertFalse(any(c[:2] == ("release", "edit") for c in self.gh.calls))
        self.gh.fail_upload = False
        self.publish()
        self.assertFalse(self.gh.release["draft"])
        self.assertEqual(sum(c[:2] == ("release", "create") for c in self.gh.calls), 1)
        before = len(self.gh.calls)
        self.publish()
        self.assertEqual(len(self.gh.calls), before)

    def test_corrupt_or_missing_archives_never_reach_github(self):
        self.paths[0].write_bytes(b"corrupted")
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.gh.calls, [])
        self.paths[1].unlink()
        with self.assertRaises(ValueError):
            self.publish()

    def test_mismatched_tag_and_draft_are_rejected(self):
        self.gh.ref = {"object": {"type": "commit", "sha": "b" * 40}}
        with self.assertRaises(ValueError):
            self.publish()
        self.gh.ref = None
        self.gh.release = {"draft": True, "assets": [], "target_commitish": "b" * 40}
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.gh.calls, [])

    def test_published_assets_are_never_overwritten(self):
        self.publish()
        self.gh.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        before = len(self.gh.calls)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(len(self.gh.calls), before)

    def test_version_matches_source_bundle_and_build(self):
        for relative in ("Resources/Info.plist", "Sources/ZenTouchCore/AppVersion.swift"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())
        self.assertEqual(versioning.set_version(self.root, "123"), "0.4.123")
        info = plistlib.loads((self.root / "Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleVersion"], "123")
        self.assertEqual(info["CFBundleShortVersionString"], "0.4.123")
        self.assertIn('current = "0.4.123"', (self.root / "Sources/ZenTouchCore/AppVersion.swift").read_text())
        self.assertIn("SPDX-License-Identifier: MIT", (self.root / "Resources/Info.plist").read_text())

    def test_invalid_run_numbers_do_not_modify_source(self):
        for run in ("0", "-1", "1.2", "01", "1000000000", "123\n"):
            with self.subTest(run=run), self.assertRaises(ValueError):
                versioning.set_version(self.root, run)
        self.assertFalse((self.root / "Resources").exists())


if __name__ == "__main__":
    unittest.main()
