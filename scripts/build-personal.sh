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
xcodebuild -project Yomi.xcodeproj -scheme Yomi -configuration "$CONFIG" -destination "id=$DEVICE_UDID" \
  -xcconfig Config/Personal.xcconfig -derivedDataPath "$DD" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)" || true
APP="$DD/Build/Products/$CONFIG-iphoneos/Yomi.app"
[ -d "$APP" ] || exit 1
xcrun devicectl device install app --device "$DEVICE_CORE" "$APP" 2>&1 | grep -E "installed|ERROR"
if [[ $LAUNCH == 1 ]]; then
  xcrun devicectl device process launch --device "$DEVICE_CORE" --terminate-existing --console pacodealer.Yomi
fi
