#!/bin/bash
# Xcode build phase (Yomi target): embeds the on-device Keiyoushi runtime into the app — only for device builds
# that opt in with YOMI_EMBED_KEIYOUSHI=YES (Config/Personal.xcconfig). Every other build (simulator, CI, the
# normal Release config) skips it, and Yomi then reports Keiyoushi as unavailable at runtime instead of failing.
# The framework is loaded with dlopen (never linked), because OpenJDK Mobile has no simulator slice.
set -euo pipefail
if [[ "${YOMI_EMBED_KEIYOUSHI:-NO}" != "YES" || "${PLATFORM_NAME}" != "iphoneos" ]]; then
  echo "Keiyoushi runtime not embedded (YOMI_EMBED_KEIYOUSHI=${YOMI_EMBED_KEIYOUSHI:-NO}, ${PLATFORM_NAME})"
  exit 0
fi
SRC="${SRCROOT}/Vendor/Keiyoushi"
if [[ ! -d "$SRC/OpenJDKRuntime.framework" ]]; then
  echo "error: ${SRC} missing — run scripts/keiyoushi/stage-vendor.sh" >&2
  exit 1
fi
APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
mkdir -p "$APP/Frameworks" "$APP/Keiyoushi"
rsync -a --delete "$SRC/OpenJDKRuntime.framework" "$APP/Frameworks/"
cp "$SRC/MExtensionServer.jar" "$SRC/java-logging-shim.jar" "$APP/Keiyoushi/"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "$APP/Frameworks/OpenJDKRuntime.framework"
echo "Embedded Keiyoushi runtime into $APP"
