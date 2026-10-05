#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Install the verified bundle without changing its TCC signing requirement."""
import os
import pathlib
import shutil
import signal
import subprocess
import tempfile
import time

repo = pathlib.Path(__file__).resolve().parent.parent
source = repo / "dist/ZenTouch.app"
destination = pathlib.Path.home() / "Applications/ZenTouch.app"
subprocess.run(["python3", str(repo / "scripts/verify-bundle.py"), str(source)], check=True)

def requirement(path):
    result = subprocess.run(["codesign", "-d", "-r-", str(path)], capture_output=True, text=True, check=True)
    return next(line for line in (result.stdout + result.stderr).splitlines() if line.startswith("designated =>"))

if destination.exists() and requirement(source) != requirement(destination):
    raise SystemExit("The installed app uses a different signing requirement. Refusing to replace it and invalidate grants.")
destination.parent.mkdir(parents=True, exist_ok=True)
stage = pathlib.Path(tempfile.mkdtemp(prefix=".zentouch-install-", dir=destination.parent))
backup = stage / "previous.app"
try:
    staged_app = stage / "ZenTouch.app"
    subprocess.run(["ditto", str(source), str(staged_app)], check=True)
    processes = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
    pids = []
    for row in processes.splitlines():
        fields = row.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid, command = fields
        if any(command == str(destination / f"Contents/MacOS/{name}") or
               command.startswith(str(destination / f"Contents/MacOS/{name}") + " ")
               for name in ("ZenTouch", "zentouch")):
            pids.append(int(pid))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 15
    while pids:
        alive = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            break
        if time.monotonic() > deadline:
            raise SystemExit("ZenTouch did not quit cleanly. The installed app was left intact.")
        pids = alive
        time.sleep(0.1)
    if destination.exists():
        destination.rename(backup)
    try:
        staged_app.rename(destination)
        subprocess.run(["python3", str(repo / "scripts/verify-bundle.py"), str(destination)], check=True)
    except BaseException:
        if destination.exists():
            shutil.rmtree(destination)
        if backup.exists():
            backup.rename(destination)
        raise
    register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    for stale in (repo / ".build/ZenTouch.app", source):
        if stale.exists():
            # A source bundle may already be unregistered; that is not an install failure.
            subprocess.run([register, "-u", str(stale)], check=False, capture_output=True)
    subprocess.run([register, "-f", str(destination)], check=True)
    print(f"Installed {destination}. Signing requirement unchanged.")
finally:
    shutil.rmtree(stage)
