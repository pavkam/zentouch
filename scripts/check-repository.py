#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

"""Check SPDX coverage, documentation links and public repository configuration."""
import ast
import json
import pathlib
import plistlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
files = [file for file in root.iterdir() if file.is_file() and file.name not in ('.zentouch-signing-identity', '.git')]
for directory in ('Sources', 'Tests', 'Resources', 'docs', 'scripts', '.github'):
    files.extend(file for file in (root / directory).rglob('*') if file.is_file() and '__pycache__' not in file.parts)
for file in files:
    if file.name == 'LICENSE':
        continue
    try:
        content = file.read_text()
    except UnicodeDecodeError:
        content = ''
    if file.suffix in ('.png', '.bin') or file.suffix == '.json' or file.name == '.swift-format':
        sidecar = pathlib.Path(str(file) + '.license')
        assert sidecar.is_file(), f'Missing license sidecar: {file.relative_to(root)}'
        content = sidecar.read_text()
    identifiers = re.findall(r'SPDX-License-Identifier: ([^\r\n]+)', content[:600])
    assert len(identifiers) == 1 and identifiers[0] in ('MIT', 'MIT AND ISC'), f'Invalid SPDX header: {file.relative_to(root)}'
    if file.suffix == '.py':
        ast.parse(content, filename=str(file))
    if file.suffix == '.sh':
        subprocess.run(['zsh', '-n', str(file)], check=True)
    if file.suffix == '.json' or file.name == '.swift-format':
        json.loads(file.read_text())
    if file.suffix == '.md':
        for link in re.findall(r'\]\(([^)]+)\)', content):
            if '://' not in link and not link.startswith('#'):
                assert (file.parent / link.split('#')[0]).exists(), f'Broken link: {file.relative_to(root)} -> {link}'
    if file.parent.name == 'workflows':
        for reference in re.findall(r'uses:\s*([^\s]+)', content):
            assert re.fullmatch(r'[\w-]+/[\w-]+@[a-f0-9]{40}', reference), f'Unpinned action: {reference}'
        assert 'permissions:' in content and 'timeout-minutes:' in content, file
with (root / 'Resources/Info.plist').open('rb') as stream:
    version = plistlib.load(stream)['CFBundleShortVersionString']
assert f'public static let current = "{version}"' in (root / 'Sources/ZenTouchCore/AppVersion.swift').read_text()
print('PASS SPDX coverage, local links, script/config syntax, pinned Actions and version agreement')
