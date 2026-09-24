#!/bin/bash
# Wraps OpenJDK Mobile's static libdevice.a into a signed-able dynamic OpenJDKRuntime.framework (device only).
# Why dynamic: HotSpot finds JNI natives (Java_*) by symbol lookup at runtime; linking the .a straight into the app
# lets the linker dead-strip them. -all_load keeps every object; a dylib exports its globals by default.
# The framework also carries the Java home (lib/modules, tzdb.dat, security, conf). Its location is NOT configurable:
# on iOS HotSpot ignores -Djava.home and uses "<directory of the JVM binary>/lib" (os_bsd.cpp,
# init_system_properties_values, __IOS__ + static build), so the Java home must be OpenJDKRuntime.framework/lib
# and the module image OpenJDKRuntime.framework/lib/lib/modules. Anywhere else: "Failed setting boot class path".
set -euo pipefail
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
SRC="$WORK/openjdk-ios"
OUT="$WORK/build/OpenJDKRuntime.framework"
LIB="$SRC/OpenJDK.xcframework/ios-arm64/libdevice.a"
HOME_SRC="$SRC/bundle/java_bundle-device"

rm -rf "$OUT" && mkdir -p "$OUT/Headers" "$OUT/lib/lib"
cp "$SRC"/OpenJDK.xcframework/ios-arm64/Headers/*.h "$OUT/Headers/"
cp -R "$SRC"/OpenJDK.xcframework/ios-arm64/Headers/ios "$OUT/Headers/" 2>/dev/null || true
cp "$HOME_SRC/lib/modules" "$HOME_SRC/lib/tzdb.dat" "$OUT/lib/lib/"
cp -R "$HOME_SRC/lib/security" "$OUT/lib/lib/"
cp -R "$HOME_SRC/conf" "$HOME_SRC/release" "$OUT/lib/"

xcrun --sdk iphoneos clang++ -target arm64-apple-ios15.0 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -dynamiclib -Wl,-all_load "$LIB" \
  -Wl,-install_name,@rpath/OpenJDKRuntime.framework/OpenJDKRuntime \
  -lz -framework Foundation -framework CoreFoundation -framework Security \
  -o "$OUT/OpenJDKRuntime"

cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>OpenJDKRuntime</string>
  <key>CFBundleIdentifier</key><string>pacodealer.OpenJDKRuntime</string>
  <key>CFBundleName</key><string>OpenJDKRuntime</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST

SYMS=$(xcrun nm -gU "$OUT/OpenJDKRuntime")
grep " _JNI_CreateJavaVM$" <<<"$SYMS" >/dev/null
echo "Built $OUT ($(du -sh "$OUT" | cut -f1)); exported Java_* natives: $(grep -c ' _Java_' <<<"$SYMS")"
