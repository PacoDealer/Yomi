#!/bin/bash
# Stages the big PoC artefacts (built by scripts/keiyoushi-poc/setup.sh + build-runtime-framework.sh, outside git)
# into Vendor/ (gitignored), then regenerates the Xcode project.
set -euo pipefail
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/Vendor"
rm -rf "$V" && mkdir -p "$V/BridgeFiles"
cp -R "$WORK/build/OpenJDKRuntime.framework" "$V/"
cp "$(ls "$WORK"/M-Extension-Server/server/build/MExtensionServer-*.jar | head -1)" "$V/BridgeFiles/MExtensionServer.jar"
cp "$WORK/harness/java-logging-shim.jar" "$V/BridgeFiles/"
cp "$WORK"/apks/*.apk "$V/BridgeFiles/"
xattr -cr "$V"  # Desktop copies carry xattrs; codesign rejects them ("detritus not allowed")
cd "$HERE" && xcodegen generate --quiet
echo "Staged $(du -sh "$V" | cut -f1) into $V"
