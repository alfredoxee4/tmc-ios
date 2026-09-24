#!/bin/bash
# Assemble an UNSIGNED .ipa from the xmake iphoneos build.
#
#   xmake f -p iphoneos -a arm64 -y
#   xmake build -y tmc_pc
#   ios/package_ipa.sh            # -> tmc-ios.ipa
#
# The resulting .ipa is intentionally UNSIGNED: SideStore / AltStore re-sign
# it with the installer's own Apple ID at install time (same distribution
# story as the Android APK, which Gradle signs with a debug/release key).
#
# NO game assets are packaged: the ROM the user imports on first launch is
# validated by hash and copied into the app's writable data dir, and the
# asset cache is extracted from that ROM on first boot.
set -euo pipefail

SRC_DIR="${1:-build/ios}"
OUT_IPA="${2:-tmc-ios.ipa}"
BIN="$SRC_DIR/tmc_pc"

if [ ! -f "$BIN" ]; then
    echo "error: $BIN not found — run 'xmake f -p iphoneos -a arm64 -y && xmake build -y tmc_pc' first" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Payload/TMC.app"
mkdir -p "$APP"
cp "$BIN" "$APP/tmc_pc"
cp ios/Info.plist "$APP/Info.plist"

# Stamp CFBundleShortVersionString from the version in xmake.lua so the
# plist never drifts from the build (fallback: leave the plist default).
if TMC_VERSION="$(grep -m1 'local TMC_PC_VERSION =' xmake.lua | sed 's/.*"\([^"]*\)".*/\1/')" && [ -n "$TMC_VERSION" ]; then
    python3 - "$APP/Info.plist" "$TMC_VERSION" <<'EOF'
import plistlib, sys
path, version = sys.argv[1], sys.argv[2]
with open(path, 'rb') as f:
    plist = plistlib.load(f)
plist['CFBundleShortVersionString'] = version
with open(path, 'wb') as f:
    plistlib.dump(plist, f)
print('stamped version', version)
EOF
fi

rm -f "$OUT_IPA"
(cd "$WORK" && zip -qr "$OLDPWD/$OUT_IPA" Payload)
echo "wrote $OUT_IPA ($(du -h "$OUT_IPA" | cut -f1))"
