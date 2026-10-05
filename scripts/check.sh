#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/check-repository.py
xcrun swift-format lint --strict --recursive Sources Tests Package.swift Resources/Branding/Artwork.swift
swift build --build-system native -Xswiftc -warnings-as-errors
swift run --build-system native -Xswiftc -warnings-as-errors zentouch-checks
python3 - <<'PY'
import os, pathlib, subprocess
root = pathlib.Path.cwd()
binary_directory = subprocess.check_output(['swift', 'build', '--build-system', 'native', '--show-bin-path'], text=True).strip()
binary = pathlib.Path(binary_directory) / 'zentouch-cli'
assert not os.path.samefile(binary, pathlib.Path(binary_directory) / 'ZenTouch'), 'GUI and CLI binaries collide'
for argument in ('--help', '--version'):
    result = subprocess.run([str(binary), argument], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0 and 'ZenTouch' in result.stdout, (argument, result)
result = subprocess.run([str(binary), 'not-a-command'], capture_output=True, text=True, timeout=10)
assert result.returncode != 0 and 'Unknown command' in result.stderr, result
print('PASS CLI help, version and invalid-command exit status')
PY
