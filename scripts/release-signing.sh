#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF:-}" == refs/heads/main &&
   -n "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || {
    print -u2 'Release signing is restricted to main on disposable Actions runners.'
    exit 1
}
[[ -n "${ZENTOUCH_CERTIFICATE_P12:-}" && -n "${ZENTOUCH_CERTIFICATE_PASSWORD:-}" &&
   "${ZENTOUCH_CERTIFICATE_SHA1:-}" =~ ^[A-Fa-f0-9]{40}$ ]] || {
    print -u2 'Configure the three ZENTOUCH_CERTIFICATE_* repository secrets before publishing.'
    exit 1
}
umask 077
zentouch_release_dir=$(mktemp -d "$RUNNER_TEMP/zentouch-release-signing.XXXXXX")
zentouch_release_keychain="$zentouch_release_dir/release.keychain-db"
zentouch_release_password=$(openssl rand -hex 24)
print "::add-mask::$zentouch_release_password"
trap 'rm -f "$zentouch_release_dir/identity.p12" "$zentouch_release_dir/certificate.pem"' EXIT
print -rn -- "$ZENTOUCH_CERTIFICATE_P12" | base64 --decode > "$zentouch_release_dir/identity.p12"
security create-keychain -p "$zentouch_release_password" "$zentouch_release_keychain"
security set-keychain-settings -lut 21600 "$zentouch_release_keychain"
security unlock-keychain -p "$zentouch_release_password" "$zentouch_release_keychain"
security import "$zentouch_release_dir/identity.p12" -k "$zentouch_release_keychain" \
    -P "$ZENTOUCH_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
# This project's stable certificate is self-signed, rather than Developer ID.
security find-certificate -a -p "$zentouch_release_keychain" > "$zentouch_release_dir/certificate.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k "$zentouch_release_keychain" "$zentouch_release_dir/certificate.pem"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$zentouch_release_password" "$zentouch_release_keychain" >/dev/null
security list-keychains -d user -s "$zentouch_release_keychain"
security find-identity -v -p codesigning "$zentouch_release_keychain" | \
    /usr/bin/grep -Fqi -- "$ZENTOUCH_CERTIFICATE_SHA1" || { print -u2 'Release certificate fingerprint mismatch.'; exit 1; }
print "ZENTOUCH_SIGNING_IDENTITY=$ZENTOUCH_CERTIFICATE_SHA1" >> "$GITHUB_ENV"
print 'Stable release signing identity ready.'
