#!/bin/bash
# Re-signs the fake provisioning profiles in build-system/fake-codesigning/profiles
# with a new ExpirationDate. The profiles are only used to make the unsigned CI build
# pass rules_apple's checks; the .ipa is re-signed by Sideloadly on install.
#
# Usage: build-system/ayugram/refresh-fake-profiles.sh [expiration, default 2030-10-28T00:00:00Z]
# Needs OpenSSL 3 (the .p12 uses legacy algorithms, hence -legacy).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../fake-codesigning" && pwd)"
EXPIRATION="${1:-2030-10-28T00:00:00Z}"
CREATION="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl pkcs12 -legacy -in "$ROOT/certs/SelfSigned.p12" -passin pass: -nokeys -clcerts -out "$WORK/cert.pem"
openssl pkcs12 -legacy -in "$ROOT/certs/SelfSigned.p12" -passin pass: -nocerts -nodes -out "$WORK/key.pem"

for profile in "$ROOT"/profiles/*.mobileprovision; do
    name="$(basename "$profile")"
    openssl smime -verify -noverify -inform der -in "$profile" -out "$WORK/$name.plist" 2>/dev/null
    # Replace the <date> that follows each key (plists here are XML).
    sed -i.bak -E \
        -e "/<key>ExpirationDate<\/key>/{n;s#<date>[^<]*</date>#<date>$EXPIRATION</date>#;}" \
        -e "/<key>CreationDate<\/key>/{n;s#<date>[^<]*</date>#<date>$CREATION</date>#;}" \
        "$WORK/$name.plist"
done

python3 - "$WORK" <<'PY'
import os
import plistlib
import sys

work = sys.argv[1]
app_name = "Telegram.mobileprovision.plist"
with open(os.path.join(work, app_name), "rb") as file:
    aps_environment = plistlib.load(file)["Entitlements"]["aps-environment"]

for name in os.listdir(work):
    if not name.endswith(".mobileprovision.plist"):
        continue
    path = os.path.join(work, name)
    with open(path, "rb") as file:
        profile = plistlib.load(file)
    entitlements = profile["Entitlements"]
    if entitlements.get("aps-environment") == aps_environment:
        continue
    entitlements["aps-environment"] = aps_environment
    with open(path, "wb") as file:
        plistlib.dump(profile, file)
PY

for profile in "$ROOT"/profiles/*.mobileprovision; do
    name="$(basename "$profile")"
    openssl smime -sign -binary -nodetach -outform der -md sha256 \
        -signer "$WORK/cert.pem" -inkey "$WORK/key.pem" \
        -in "$WORK/$name.plist" -out "$profile"
    echo "$name: expires $EXPIRATION"
done
