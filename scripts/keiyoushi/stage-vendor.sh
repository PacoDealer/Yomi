#!/bin/bash
# Stages the on-device Keiyoushi runtime for Yomi into Vendor/Keiyoushi (gitignored):
# OpenJDKRuntime.framework (OpenJDK Mobile, device-only), our patched M-Extension-Server jar, and the
# java.logging stand-in. Built by scripts/keiyoushi-poc/setup.sh + build-runtime-framework.sh (outside git).
set -euo pipefail
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Vendor/Keiyoushi"
[ -d "$WORK/build/OpenJDKRuntime.framework" ] || { echo "Missing runtime — run scripts/keiyoushi-poc/setup.sh and build-runtime-framework.sh" >&2; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R "$WORK/build/OpenJDKRuntime.framework" "$OUT/"
rm -rf "$OUT/OpenJDKRuntime.framework/Headers"   # headers are only needed at compile time (Yomi/Keiyoushi/JNI)
cp "$(ls "$WORK"/M-Extension-Server/server/build/MExtensionServer-*.jar | head -1)" "$OUT/MExtensionServer.jar"
cp "$WORK/harness/java-logging-shim.jar" "$OUT/"
xattr -cr "$OUT"   # Desktop copies carry xattrs; codesign rejects them
echo "Staged $(du -sh "$OUT" | cut -f1) into $OUT"
