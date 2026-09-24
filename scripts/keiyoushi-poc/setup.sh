#!/bin/bash
# Rebuilds the Keiyoushi on-device PoC workspace (outside git — it holds ~300 MB of downloads and builds).
# Idempotent: every step is skipped when its output already exists. See Yomi/KEIYOUSHI_POC.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
JDK=/opt/homebrew/opt/openjdk@21
MES_COMMIT=6685bdce895bce5ff7311c76a93f4fd77971e1be   # kodjodevf/M-Extension-Server, v1.0.7+ (2026-09)
OPENJDK_TAG=embedded-openjdk-ios13-v16                  # 1Selxo/Mangatan release; SHA-256s below from its SHA256SUMS
OPENJDK_XCF_SHA=f21681caae40e508647e7f18c9082f27fa9aa67ee7f1376725eae528fa2d38cb
JAVA_BUNDLE_SHA=15369b9bb9dfdd400c18c56b30e2f6cf316b81d4e0bae5ddd6b1fe72355c4b0b
APKS=(
  "https://github.com/keiyoushi/extensions/releases/download/4217666-0/tachiyomi-en.asurascans-v1.6.69.apk"
  "https://github.com/keiyoushi/extensions/releases/download/4217666-0/tachiyomi-all.mangafire-v1.6.34.apk"
)

[ -x "$JDK/bin/java" ] || brew install openjdk@21   # formula, not the temurin cask (the cask needs sudo)
export JAVA_HOME="$JDK/libexec/openjdk.jdk/Contents/Home" PATH="$JDK/bin:$PATH"
mkdir -p "$WORK"/{apks,harness,openjdk-ios,tmp,appdir}
cd "$WORK"

# 1. M-Extension-Server at the pinned commit + Yomi patch, built in iOS mode.
if [ ! -d M-Extension-Server ]; then
  git clone -q https://github.com/kodjodevf/M-Extension-Server.git
  git -C M-Extension-Server checkout -q "$MES_COMMIT"
  git -C M-Extension-Server apply "$HERE/patches/m-extension-server-yomi.patch"
fi
if ! ls M-Extension-Server/server/build/MExtensionServer-*.jar >/dev/null 2>&1; then
  (cd M-Extension-Server && ./AndroidCompat/getAndroid.sh && \
   ./gradlew :server:shadowJar -PiosRuntime=true --no-daemon --max-workers=4 -q)
fi
SERVER_JAR=$(ls M-Extension-Server/server/build/MExtensionServer-*.jar | head -1)

# 2. OpenJDK Mobile for iOS (Zero interpreter, java.base only). Device-only: there is no simulator slice.
if [ ! -d openjdk-ios/OpenJDK.xcframework ]; then
  (cd openjdk-ios && gh release download "$OPENJDK_TAG" -R 1Selxo/Mangatan --clobber && \
   echo "$OPENJDK_XCF_SHA  OpenJDK.xcframework.zip" | shasum -a 256 -c - && \
   echo "$JAVA_BUNDLE_SHA  java_bundle-device.zip" | shasum -a 256 -c - && \
   unzip -q -o OpenJDK.xcframework.zip && unzip -q -o java_bundle-device.zip -d bundle)
fi

# 3. Our java.logging stand-in (the iOS runtime has no java.logging module; NanoHTTPD and OkHttp need it).
if [ ! -f harness/java-logging-shim.jar ]; then
  rm -rf harness/jul-classes
  javac --patch-module java.logging="$HERE/jul-shim" -d harness/jul-classes "$HERE"/jul-shim/java/util/logging/*.java
  jar --create --file harness/java-logging-shim.jar -C harness/jul-classes .
fi

# 4. Mac harness: Launcher starts the bridge exactly like the iOS host will (EmbeddedBridge.start, no main()).
javac --release 21 -proc:none -cp "$SERVER_JAR" -d harness "$HERE/Launcher.java"

# 5. A java.base-only JRE that mimics the phone's runtime (+ jdk.crypto.ec, which JDK 22+ folds into java.base).
[ -d jre-base ] || jlink --add-modules java.base,jdk.crypto.ec --output jre-base --strip-debug --no-header-files --no-man-pages

# 6. Test extensions (Keiyoushi index: https://github.com/keiyoushi/extensions/raw/repo/index.pb).
for u in "${APKS[@]}"; do [ -f "apks/$(basename "$u")" ] || curl -sL -o "apks/$(basename "$u")" "$u"; done

echo "Workspace ready: $WORK"
echo "Next: $HERE/run-server.sh && python3 $HERE/call.py $WORK/apks/tachiyomi-en.asurascans-v1.6.69.apk solo"
