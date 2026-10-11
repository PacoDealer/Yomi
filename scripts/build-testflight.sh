#!/bin/bash
# Archives Yomi (Release, paid team, Keiyoushi runtime embedded — Config/TestFlight.xcconfig) and uploads the build
# to App Store Connect for TestFlight. Needs: the paid Team ID in Config/TestFlight.xcconfig, Xcode signed in to
# that account (Settings → Accounts), and an app record for pacodealer.Yomi in App Store Connect.
# Pass --archive-only to stop before the upload (checks signing without sending anything to Apple).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM = //p' Config/TestFlight.xcconfig)
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Put the paid Team ID in Config/TestFlight.xcconfig first (found: $TEAM)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes — commit first, so the build number names a commit." >&2; exit 1; }
[ -d Vendor/Keiyoushi/OpenJDKRuntime.framework ] || { echo "Vendor/Keiyoushi missing — run scripts/keiyoushi/stage-vendor.sh" >&2; exit 1; }
# App Store Connect wants a build number that only goes up: the commit count does, and maps back to a commit.
BUILD=$(git rev-list --count HEAD)
OUT="$HOME/Library/Developer/Xcode/DerivedData/Yomi-testflight"
ARCHIVE="$OUT/Yomi-$BUILD.xcarchive"
LOG=$(mktemp)
echo "Archiving build $BUILD ($(git rev-parse --short HEAD)) for team $TEAM…"
xcodebuild -project Yomi.xcodeproj -scheme Yomi -configuration Release -destination 'generic/platform=iOS' \
  -xcconfig Config/TestFlight.xcconfig -derivedDataPath "$OUT" -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates archive >"$LOG" 2>&1 || true
grep -E "error:|warning: .*\.swift|ARCHIVE (SUCCEEDED|FAILED)" "$LOG" || true
grep -q "ARCHIVE SUCCEEDED" "$LOG" || { echo "Archive failed — full log: $LOG"; exit 1; }
APP="$ARCHIVE/Products/Applications/Yomi.app"
[ -d "$APP/Frameworks/OpenJDKRuntime.framework" ] || { echo "Archive has no Keiyoushi runtime — not uploading." >&2; exit 1; }
echo "Archive: $ARCHIVE ($(du -sh "$APP" | cut -f1))"
[[ "${1:-}" == "--archive-only" ]] && exit 0
OPTS=$(mktemp).plist
cat >"$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
# Export locally first and check every signature: Xcode's CLOUD signing writes "Martín" decomposed into the designated
# requirement and Apple rejects the upload as "Invalid Signature" (S151). The local Apple Distribution certificate in
# the keychain signs correctly — this guard catches the day it is missing or expired.
CHECK="$OUT/check-$BUILD"; mkdir -p "$CHECK"
sed 's|<string>upload</string>|<string>export</string>|' "$OPTS" > "$CHECK/opts.plist"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$CHECK/opts.plist" -exportPath "$CHECK" \
  -allowProvisioningUpdates >"$LOG" 2>&1 || { echo "Local export failed — full log: $LOG"; exit 1; }
( cd "$CHECK" && unzip -q -o Yomi.ipa )
for b in Yomi.app Yomi.app/PlugIns/YomiWidget.appex Yomi.app/Frameworks/OpenJDKRuntime.framework; do
  codesign --verify --strict -vv "$CHECK/Payload/$b" 2>&1 | grep -q "satisfies its Designated Requirement" \
    || { echo "Bad signature on $b — not uploading (is the local Apple Distribution certificate in the keychain?)" >&2; exit 1; }
done
echo "Signatures verified; uploading…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" -exportPath "$OUT/export-$BUILD" \
  -allowProvisioningUpdates 2>&1 | tee "$LOG" | grep -E "error|Upload|EXPORT (SUCCEEDED|FAILED)" || true
grep -q "EXPORT SUCCEEDED" "$LOG" || { echo "Upload failed — full log: $LOG"; exit 1; }
echo "Uploaded build $BUILD. It appears in App Store Connect → TestFlight after Apple finishes processing."
