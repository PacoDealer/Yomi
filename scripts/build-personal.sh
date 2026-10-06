#!/bin/bash
# Builds Yomi signed by the free Personal Team (Config/Personal.xcconfig) and installs it on Martin's iPhone 17.
# Needed because the on-device Keiyoushi runtime has no simulator slice. Free-team builds expire after 7 days.
# Pass --launch to also start it and stream its console (the phone must be unlocked).
# Pass --release for an optimized build (use it for performance measurements — Debug SwiftUI is much slower).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_UDID=00008150-00187C4A1EF3401C          # xcodebuild -destination
DEVICE_CORE=270B9EDA-7298-5206-9E67-71C0E8F60CF6   # devicectl
DD="$HOME/Library/Developer/Xcode/DerivedData/Yomi-personal"
cd "$ROOT"
CONFIG=Debug; LAUNCH=0
for a in "$@"; do case "$a" in --release) CONFIG=Release;; --launch) LAUNCH=1;; esac; done
# Xcode reuses a cached profile until it expires, so an install can inherit one with hours left (S135: "unavailable"
# the day after installing). Drop Yomi profiles with < 6 days left so every install gets the full 7.
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
for p in "$PROFILES"/*; do
  [ -f "$p" ] || continue
  plist=$(security cms -D -i "$p" 2>/dev/null) || continue
  case "$(plutil -extract Entitlements.application-identifier raw - <<<"$plist" 2>/dev/null)" in *.pacodealer.Yomi*) ;; *) continue;; esac
  exp=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$(plutil -extract ExpirationDate raw - <<<"$plist")" +%s 2>/dev/null) || continue
  (( exp - $(date +%s) < 6*86400 )) && rm "$p"
done
LOG=$(mktemp)
xcodebuild -project Yomi.xcodeproj -scheme Yomi -configuration "$CONFIG" -destination "id=$DEVICE_UDID" \
  -xcconfig Config/Personal.xcconfig -derivedDataPath "$DD" -allowProvisioningUpdates build >"$LOG" 2>&1 || true
grep -E "error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)" "$LOG" || true
# A failed build leaves the PREVIOUS Yomi.app in place — installing it would silently run old code (S144).
grep -q "BUILD SUCCEEDED" "$LOG" || { echo "Build failed — nothing installed."; exit 1; }
APP="$DD/Build/Products/$CONFIG-iphoneos/Yomi.app"
[ -d "$APP" ] || exit 1
echo "Profile expires: $(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -)"
xcrun devicectl device install app --device "$DEVICE_CORE" "$APP" 2>&1 | grep -E "installed|ERROR"
if [[ $LAUNCH == 1 ]]; then
  xcrun devicectl device process launch --device "$DEVICE_CORE" --terminate-existing --console pacodealer.Yomi
fi
