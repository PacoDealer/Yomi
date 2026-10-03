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
- App Store (Guideline 5.2.2): only `instantInstallSourceIDs` get one-tap install; everything else is
  Copy URL + manual add. Keep it a compiled-in allowlist, never a remote flag.
- Before testing a source, read the plugin's own `BASE_URL`/endpoints — don't test domains from memory.
