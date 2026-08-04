---
name: yomi-sim
description: Build, install, launch, and screenshot the Yomi iOS app on its pinned simulator, and toggle AppSettings without tapping the UI. Use whenever asked to run, screenshot, or visually verify Yomi in the simulator — especially for design-fidelity comparisons against the mockup.
---

# Running and inspecting Yomi in the simulator

## Preferred path: mobile-mcp / XcodeBuildMCP

If `mcp__mobile-mcp__*` or `mcp__XcodeBuildMCP__*` tools are available (check via
`ToolSearch` — `select:mcp__mobile-mcp__mobile_take_screenshot` etc., or they may already be
listed as available tools), **use those first**. They give reliable tap/element-inspection —
`mobile_click_on_screen_at_coordinates`, `mobile_list_elements_on_screen`,
`mobile_take_screenshot`, `build_run_sim`, `screenshot`. See `CLAUDE.md`'s "MCP tools" section for
the full command list.

**Do not** try to drive the simulator by guessing raw screen coordinates with AppleScript /
`osascript ... System Events ... click at {x,y}`. This was attempted in S84 when mobile-mcp wasn't
loaded in-session (it was connected per `claude mcp list` but stale in that session's tool index)
and it mis-clicked into an unrelated desktop app instead of the Simulator window twice. If
mobile-mcp genuinely isn't available, fall back to the read-only + settings-file approach below
rather than blind coordinate clicking — screenshot and inspect, ask the user to tap through
manually for anything that needs real navigation.

## Fallback path: plain `simctl`, no MCP needed

Works for build/install/launch/screenshot and reading current app state. Cannot tap/navigate —
only reaches whatever screen the app opens to, plus any settings you can toggle without a tap.

**Pinned simulator UDID** (avoids the S76 bug where two "iPhone 17 Pro" simulator instances have
isolated app data and diverge from what the user actually sees in Xcode):
```
34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97   # iPhone 17 Pro — matches .xcodebuildmcp/config.yaml
```

Boot + build + install + launch:
```bash
SIM_ID="34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97"
xcrun simctl boot "$SIM_ID"                 # no-op if already booted
open -a Simulator

cd "/Users/martingamberg/Desktop/Projects/Yomi/iOS"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

APP_PATH="/Users/martingamberg/Library/Developer/Xcode/DerivedData/Yomi-dpankitqhugautcutqgzzdikdkbb/Build/Products/Debug-iphonesimulator/Yomi.app"
xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" pacodealer.Yomi
```
(If the DerivedData hash differs, `find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "Yomi-*"`.)

Screenshot (safe, no risk, use freely):
```bash
xcrun simctl io "$SIM_ID" screenshot /path/to/out.png
```
Screenshots come out at 3x the simulator's logical point size (e.g. 1206×2622 px for the
402×874pt iPhone 17 Pro screen).

## Reading/writing AppSettings without tapping

`AppSettings` persists to plain `UserDefaults.standard` — real key names live in
`Yomi/AppSettings.swift` (grep `defaults.set(...forKey:`). **Don't trust
`xcrun simctl spawn "$SIM_ID" defaults read pacodealer.Yomi`** — it reported "Domain does not
exist" in S84 even though real, previously-saved user settings existed on disk (a cfprefsd
caching quirk specific to fresh simulator boots). Read the actual container file instead:

```bash
SIM_ID="34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97"
DATA_DIR=$(xcrun simctl get_app_container "$SIM_ID" pacodealer.Yomi data)
PLIST="$DATA_DIR/Library/Preferences/pacodealer.Yomi.plist"
plutil -p "$PLIST"        # read everything
```

To change a setting and see the result (e.g. switch library display mode to compare grid vs.
list without navigating), **write through the `defaults` CLI, not by editing the plist file
directly** — a direct `PlistBuddy`/file edit was tried in S84 and silently didn't take effect
(same cfprefsd caching issue in reverse); `defaults write` goes through the proper path and does:

```bash
xcrun simctl terminate "$SIM_ID" pacodealer.Yomi
xcrun simctl spawn "$SIM_ID" defaults write pacodealer.Yomi libraryDisplayMode -string grid
xcrun simctl launch "$SIM_ID" pacodealer.Yomi
```

Known real key names (from `Yomi/AppSettings.swift`): `libraryDisplayMode` ("grid"/"list"),
`canvas` ("Ink"/"Midnight"/"Paper"/"Sepia"/"" follow-device), `accentColor` (hex string), `theme`
(legacy "Dark"/"Light"/"System"), `novelTheme`. Grep the file for the full ~40-property list
before assuming a key name.

**This session's actual saved values (2026-08-04, for reference — will drift):**
`accentColor: "#006BA6"` (user's own custom blue, not the design system's Vermilion default —
this is correct, expected personalization, not a bug), `libraryDisplayMode: "list"` (the user's
real daily-driver view), `novelTheme: "AMOLED"`, `theme: "Dark"`, no `canvas` key set.
