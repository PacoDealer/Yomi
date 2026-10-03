---
paths:
  - "Yomi/Features/Extensions/**"
  - "Yomi/Features/Keiyoushi/**"
  - "Yomi/Features/More/PluginsView.swift"
  - "scripts/keiyoushi/**"
  - "scripts/build-js-libs.mjs"
---

# Plugin / extension rules

- Never build `JSBridge(scriptURL: ext.sourceListURL)` (DB URL goes stale) — rebuild from FileManager + `ext.id`.
- `ExtensionManager.bridge(for:)` caches one JSBridge per source (rebuilt on script mtime change); JSBridge
  entry points hold an NSRecursiveLock. Main-actor callers use `await loadBridge(for:)`.
- JS libraries (cheerio, dayjs, URL polyfills) come from `Resources/yomi-js-libs.js`, built by
  `scripts/build-js-libs.mjs` — rerun after bumping devDependencies. Measure LNReader compatibility with
  the DEBUG harness (`-lnreaderHarness`, see ROADMAP S125) before/after changes.
- `#if DEBUG seedBundledPlugins()` only — never in Release.
- Keiyoushi: sourceId `keiyoushi_<Mihon id>`, chapter path `keiyoushi://…`; iOS HotSpot ignores
  `-Djava.home` (Java home = `OpenJDKRuntime.framework/lib`); runtime embedded only when
  `YOMI_EMBED_KEIYOUSHI=YES`. Covers load natively (`KeiyoushiCovers`), reader pages still via the JVM proxy.
- App Store (Guideline 5.2.2), Martin's S140 rule: Yomi ships with **no repositories** (fresh installs start
  empty) and suggests none; the user pastes every repository link. Inside an added repository every extension
  is one tap ("Add"). Removing = swipe → red trash (extensions and repositories). Replaced S104's
  `instantInstallSourceIDs` allowlist. Legal pass still to confirm (incl. the onboarding/README guide link).
- Updating a plugin keeps its INSTALLED id (`ExtensionManager.update(_:to:)`) — titles store the plugin id as
  `sourceId`; installing an update under the catalog id orphaned them (S140). `relinkOrphanedTitles` repairs
  old orphans after every catalog load (old ids = sha256(plugin URL) or sha256(file name)).
- Before testing a source, read the plugin's own `BASE_URL`/endpoints — don't test domains from memory.
