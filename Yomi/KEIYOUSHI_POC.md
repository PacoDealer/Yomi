# Keiyoushi on-device proof of concept (S123 → next session)

**Goal:** run real Keiyoushi (Mihon) extensions **inside Yomi on Martin's iPhone**, no server — the way Tachimanga and
Madomi do. This doc is the single source of truth for the PoC: what's already proven, what's ready, and the exact
steps for next session. Background research: `RESEARCH.md` §22.1–22.3 and §22.12.

**Martin's instruction for next session:** when he says *"Lets continue with yomi"*, execute **Phase 1** below
immediately — no questions first. Report results at the end. (Decided S123, 2026-09-24.)

---

## Decisions already made (don't re-ask)

| Question | Answer |
|---|---|
| PoC first or stutter fixes first? | **PoC first** |
| Device | **iPhone 17 (iPhone18,3), iOS 26.6.1** — paired with this Mac, Developer Mode ON, wired. CoreDevice id `270B9EDA-7298-5206-9E67-71C0E8F60CF6` (for `devicectl`), hardware UDID `00008150-00187C4A1EF3401C` (for `xcodebuild -destination id=`) |
| Signing | **Free Personal Team** `F9R33MN82P` (identity "Apple Development: tintin@gamberg.com.ar") — 7-day builds; paid Program later |
| Test sources | **Asura Scans** (`en.asurascans` v1.6.69) and **MangaFire** (`all.mangafire` v1.6.34). **Not MangaDex** — Martin: too many languages/duplicate translations stacked per chapter, "feels like clones", always breaks |
| JDK | Homebrew **`openjdk@21`** formula at `/opt/homebrew/opt/openjdk@21` (the `temurin@21` cask needs sudo; not on global PATH — scripts set `JAVA_HOME`) |
| App for the test | A **separate small lab app** ("YomiBridgeLab"), not Yomi itself — Yomi's entitlements need push + iCloud/CloudKit, which a free Personal Team cannot sign |

## Phase 0 — Mac validation ✅ DONE (S123, 2026-09-24)

Built our patched M-Extension-Server in iOS mode and ran it on a Mac JRE cut down to **`java.base` only**
(what the phone's runtime has), **interpreter only** (`-Xint`), started through `EmbeddedBridge.start` exactly as
the iOS host will. Then drove both extensions end to end through the bridge's `POST /dalvik` API:

| Step | Asura Scans | MangaFire |
|---|---|---|
| getPopularManga | ✅ 20 items (5.5 s incl. first APK→JAR conversion) | ✅ 50 items (3.4–5.2 s incl. conversion) |
| getSearchManga | ✅ "solo" → 10 | ✅ "solo leveling" → 50 |
| getDetailsManga | ✅ author/artist/description | ✅ |
| getChapterList | ✅ 162 chapters | ✅ 1,516 chapters (see *duplicates* below) |
| getPageList | ✅ 27–28 pages | ✅ 10 pages |
| First page image (via bridge image proxy) | ✅ 205–252 KB WebP | ✅ 798 KB JPEG |

Reproducible from zero in **58 s**: `scripts/keiyoushi-poc/setup.sh` (verified in a fresh temp directory).
The iOS runtime framework also **links cleanly** for iphoneos (9.8 MB binary, 480 JNI natives exported,
`JNI_CreateJavaVM` present, deps = libz/libc++/Foundation/CoreFoundation/Security/libSystem only).

**Caveat:** Mac `-Xint` is HotSpot's template interpreter; the phone runs OpenJDK **Zero** (a C++ interpreter),
expected to be noticeably slower. The Mac numbers prove *correctness*, not phone speed — Phase 1 measures that.

### What broke on the way, and the fixes (all needed on the phone too)

1. **`java.logging` missing** (iOS runtime = `java.base` only) → NanoHTTPD/OkHttp crash with
   `NoClassDefFoundError: java/util/logging/Logger`. **Fix:** our own 2-class stand-in
   (`scripts/keiyoushi-poc/jul-shim/`, only the ~15 members `jdeps`+`javap` show are used), appended with
   `-Xbootclasspath/a:`. Written from scratch — not copied (Mangayomi's plugin repo has no licence).
2. **Keiyoushi now requests zstd** — its shared `KeiSource` base (updated 2026-09-24) adds
   `CompressionInterceptor(Brotli, Gzip, Zstd)`. okhttp-zstd decodes via a **JNI native library** that cannot load
   on iOS → every zstd response crashed the call. **Fix (our patch):** `NoZstdInterceptor`, a *network*
   interceptor in the bridge's base client that removes `zstd` from `Accept-Encoding`; sites fall back to br/gzip
   (pure Java). `scripts/keiyoushi-poc/patches/m-extension-server-yomi.patch`.
3. **User-Agent is copied from the caller.** The bridge sets extension requests' UA from the incoming HTTP
   request; a `Python-urllib` UA got **403** from Asura's Cloudflare. Yomi must send its WKWebView/Safari UA
   (the harness does). Also where Cloudflare **cookies** go in: `DalvikHandler` forwards the caller's `Cookie`
   header into the extension's cookie jar per domain.
4. Mac-only artefacts (not phone issues): no IPv6 route here → `-Djava.net.preferIPv4Stack=true` (Mangayomi sets it
   too); JDK 21 keeps EC crypto in `jdk.crypto.ec` → added to the Mac JRE (the phone's OpenJDK Mobile has
   `sun/security/ec/*` inside `java.base` — checked in its `lib/modules`).

### Known gaps still open (don't block Phase 1)

| Gap | Impact | Planned fix |
|---|---|---|
| **KeiSource filter cache writes zstd** (`zstdCompress` to disk) → background `ExceptionInInitializerError`, logged, request still succeeds | Filter cache never persists; noisy log | Replace `com.squareup.zstd` with a pure-Java stand-in (raw-block zstd frames are trivial to write/read), or statically link real libzstd + its JNI glue into the iOS framework |
| **Asura "tiles" pages** use `android.graphics.Bitmap/Canvas` → AndroidCompat implements those with **AWT/ImageIO**, absent on iOS | Only pages Asura serves scrambled (none of the 3 chapters tested) | Replace AndroidCompat's `Bitmap`/`BitmapFactory`/`Canvas` with a CoreGraphics-backed JNI implementation |
| **MangaFire shape-captcha** → extension calls `runWebViewBlocking` (Android WebView) | Only when MangaFire challenges (not seen in testing) | Yomi shows the site in a WKWebView, user solves, cookies forwarded via the bridge's Cookie header |
| **APK→JAR (dex2jar) runs every launch** (loader converts the base64 APK into a temp jar each time; only in-memory cache) | Slow first call per extension per launch on Zero | Persist converted jars, or load Keiyoushi's prebuilt `.jar` directly (index.pb publishes both) |
| **Duplicate translations** — MangaFire's Devil Butler: 1,516 chapters, all English, **592 chapter numbers twice** (`official` + `unofficial` scanlator) | Same "clones" problem Martin hit on MangaDex — it's a Keiyoushi-wide pattern, not a MangaDex quirk | **Yomi feature, not bridge:** per-title "one translation per chapter" (dedupe by chapter number, preferred scanlator), like Mihon's scanlator filter |
| NewPipe Extractor (GPLv3) is inside the server jar | Licence, only matters when shipping | Build variant without `org/schabi` before any App Store build |

## Phase 1 — on the iPhone (NEXT SESSION — do this immediately)

Everything below runs on this Mac; the phone is already paired. Workspace: `~/Desktop/Projects/Yomi/Tools/keiyoushi-poc`
(outside git; `setup.sh` rebuilds it). Scripts: `iOS/scripts/keiyoushi-poc/`.

1. **Warm up (2 min):** `scripts/keiyoushi-poc/setup.sh` (no-op if built) → `run-server.sh` →
   `python3 call.py <workspace>/apks/tachiyomi-en.asurascans-v1.6.69.apk solo` — confirms nothing drifted
   (Keiyoushi ships extension updates daily; if an APK 404s, get the current URL from `index.pb`). Kill the server after.
2. **Runtime framework:** `scripts/keiyoushi-poc/build-runtime-framework.sh` → `<workspace>/build/OpenJDKRuntime.framework`
   (already works; rerun only if the workspace was rebuilt).
3. **Create the lab app** at `iOS/Labs/YomiBridgeLab/` with **XcodeGen** (installed, v2.46.0): `project.yml` →
   iOS 26 app, bundle id **`pacodealer.YomiBridgeLab`**, team `F9R33MN82P`, automatic signing, **no capabilities**;
   embed+sign `OpenJDKRuntime.framework`; bundle resources: `MExtensionServer.jar` (from the workspace build),
   `java-logging-shim.jar`, the two APKs. `ENABLE_BITCODE` n/a; `DEAD_CODE_STRIPPING` irrelevant (dylib).
   Add `NSAppTransportSecurity → NSAllowsLocalNetworking = YES` (bridge is `http://127.0.0.1`).
4. **Write our own host (clean-room, ObjC++ `JVMHost.mm` + Swift wrapper)** — facts to use (from reading, not copying):
   - Create the VM on a **dedicated `NSThread` with an 8 MiB stack** (Zero puts its Java stack on the native stack;
     dispatch threads are too small and crash during bootstrap). Pass `-Xss8m` too.
   - JVM options: `-Djava.home=<framework>/java_home`, `-Djava.class.path=<bundle>/MExtensionServer.jar`,
     `-Xbootclasspath/a:<bundle>/java-logging-shim.jar`, `-Djava.io.tmpdir=<NSTemporaryDirectory>/MihonExtensions`,
     `-Duser.home=<Application Support>`, `-Djavax.net.ssl.trustStore=<java_home>/lib/security/cacerts`,
     `-Djava.awt.headless=true`, `-Dfile.encoding=UTF-8`, `-Djava.net.preferIPv4Stack=true`, `-XX:+UseSerialGC`,
     `-Xms128m -Xmx512m`, `-Dorg.slf4j.simpleLogger.defaultLogLevel=warn`.
   - `JNI_CreateJavaVM` (link the framework, or `dlsym`), then `FindClass("mextensionserver/EmbeddedBridge")`,
     `GetStaticMethodID(start,"(ILjava/lang/String;)I")`, call `start(0, appSupportDir)` → returns the port.
     Also expose `pause()` (on background) / `isRunning()`.
   - Only one JVM per process, ever — never destroy/recreate it.
5. **Lab UI (SwiftUI, one screen):** buttons "Start JVM", "Asura", "MangaFire"; each runs the same sequence as
   `call.py` (popular → search → details → chapters → pages → first image) over `URLSession` to
   `http://127.0.0.1:<port>/dalvik` with the **Safari UA**, showing per-step ms and rendering the first page image.
   Show resident memory (`task_info` phys_footprint) after each step.
6. **Build + install + launch** (XcodeBuildMCP has only simulator tools enabled — use CLI):
   `xcodebuild -project Labs/YomiBridgeLab/YomiBridgeLab.xcodeproj -scheme YomiBridgeLab -destination 'id=00008150-00187C4A1EF3401C' -allowProvisioningUpdates build`
   → `xcrun devicectl device install app --device 270B9EDA-7298-5206-9E67-71C0E8F60CF6 <.app>` →
   `xcrun devicectl device process launch --device 270B9EDA-7298-5206-9E67-71C0E8F60CF6 --terminate-existing --console pacodealer.YomiBridgeLab`
   (`--console` streams the app's stdout/stderr — JVM + bridge logs land there). **First launch needs Martin once:** iPhone Settings → General → VPN & Device
   Management → trust the developer profile (tell him exactly this if launch is refused).
7. **Record results** in the table below + RESEARCH.md §22.12, commit, push.

### Phase 1 measurements to fill in

| Metric | Result |
|---|---|
| JVM create time (JNI_CreateJavaVM → returns) | |
| `EmbeddedBridge.start` time | |
| Asura: first getPopularManga (incl. dex2jar) / warm call | |
| Asura: chapters / pages / first image | |
| MangaFire: first getPopularManga / warm | |
| Resident memory after JVM start / after both extensions | |
| App size (.ipa / installed) | |
| Any crash / signal (Zero has no stack-overflow signal path — watch for deep recursion) | |

### If it fails — first things to check
- Crash in bootstrap → stack size (must be the dedicated 8 MiB thread), `java.home` layout (`lib/modules` must exist
  under it), missing `conf/`.
- `ClassNotFoundException` for a JDK class → a module the iOS runtime lacks (it's `java.base` only); see the
  `jdeps` table in RESEARCH.md §22.12 — `java.xml`, `java.sql`, `java.desktop`, `java.logging` users exist in the jar.
- TLS errors → `javax.net.ssl.trustStore` path.
- 403 from a source → UA not forwarded, or Cloudflare needs a cookie → open the site in a WKWebView first.

## Phase 2+ (after the phone PoC works)
1. Close the gaps table above (zstd stand-in, Bitmap via CoreGraphics, captcha via WKWebView cookies, jar caching).
2. Integrate into Yomi: new source type "Keiyoushi repo" — parse `index.pb` (protobuf, gzipped), install = download
   APK/JAR into app storage, Browse/Detail/Reader route through the bridge (like the S120 `suwayomi://` path routing).
3. "One translation per chapter" dedupe in chapter lists.
4. Licence pass before shipping: publish our MPL-2.0 changes, drop NewPipe (GPLv3), OpenJDK GPLv2+CPE notices.
