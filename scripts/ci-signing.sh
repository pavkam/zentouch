#!/bin/zsh
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
# SPDX-License-Identifier: MIT

set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && -n "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || {
    print -u2 'This script is restricted to disposable GitHub Actions runners.'
    exit 1
}
zentouch_ci_dir=$(mktemp -d "$RUNNER_TEMP/zentouch-signing.XXXXXX")
zentouch_ci_password=$(openssl rand -hex 24)
print "::add-mask::$zentouch_ci_password"
zentouch_ci_keychain="$zentouch_ci_dir/ci.keychain-db"
cat > "$zentouch_ci_dir/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = ZenTouch CI
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 -config "$zentouch_ci_dir/certificate.cnf" \
    -keyout "$zentouch_ci_dir/key.pem" -out "$zentouch_ci_dir/certificate.pem" 2>/dev/null
# Use the PKCS#12 algorithms supported by the macOS Keychain importer.
openssl pkcs12 -export -inkey "$zentouch_ci_dir/key.pem" -in "$zentouch_ci_dir/certificate.pem" \
    -out "$zentouch_ci_dir/identity.p12" -passout "pass:$zentouch_ci_password" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security create-keychain -p "$zentouch_ci_password" "$zentouch_ci_keychain"
security set-keychain-settings -lut 21600 "$zentouch_ci_keychain"
security unlock-keychain -p "$zentouch_ci_password" "$zentouch_ci_keychain"
security import "$zentouch_ci_dir/identity.p12" -k "$zentouch_ci_keychain" -P "$zentouch_ci_password" -T /usr/bin/codesign
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$zentouch_ci_keychain" "$zentouch_ci_dir/certificate.pem"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$zentouch_ci_password" "$zentouch_ci_keychain" >/dev/null
security list-keychains -d user -s "$zentouch_ci_keychain"
print 'ZENTOUCH_SIGNING_IDENTITY=ZenTouch CI' >> "$GITHUB_ENV"
rm -f "$zentouch_ci_dir/key.pem" "$zentouch_ci_dir/identity.p12"
print 'Disposable CI signing identity ready; these packages are not release binaries.'
