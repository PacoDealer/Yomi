# Keiyoushi on-device PoC — scripts

Plan, results and next steps: **`Yomi/KEIYOUSHI_POC.md`**. Big downloads/builds live outside git in
`~/Desktop/Projects/Yomi/Tools/keiyoushi-poc` (override with `KEIYOUSHI_POC_WORK`).

| File | What it does |
|---|---|
| `setup.sh` | Rebuilds the workspace from zero (~1 min): M-Extension-Server at a pinned commit + our patch, built with `-PiosRuntime=true`; OpenJDK Mobile iOS runtime (SHA-256 checked); our `java.logging` stand-in; a `java.base`-only Mac JRE; the test APKs. Idempotent. |
| `run-server.sh` | Starts the bridge on the Mac exactly like the iPhone host will (java.base-only, `-Xint`, same JVM options), port 18765, log `$WORK/server.log`. Writes a fresh bridge token to `$WORK/bridge.token` (S191; every request needs `X-Yomi-Bridge-Token`). |
| `call.py` | Drives `POST /dalvik` like Yomi will: popular → search → details → chapters → pages → first image, with timings. `--newest` reads the newest chapter instead of the oldest. |
| `build-runtime-framework.sh` | Wraps OpenJDK Mobile's static `libdevice.a` into a device-only `OpenJDKRuntime.framework`, with the Java home at `lib/` (the only place iOS HotSpot looks). Consumed by `Labs/YomiBridgeLab/prepare.sh`. |
| `jni-harness.c` | A6 (S210): the iPhone host's JNI calls (RegisterNatives, `YomiHost.start/call/image`, callbacks on Java threads) against a jar on the Mac's java.base-only JRE. Build: `clang -o h jni-harness.c -I$JAVA_HOME/include -I$JAVA_HOME/include/darwin -L$WORK/jre-base/lib/server -ljvm -Wl,-rpath,$WORK/jre-base/lib/server`; run `h <jar> <shim> <apkDir> <apkInsideDir> <appDir>`. |
| `Launcher.java` | Mac stand-in for the iOS host: calls `mextensionserver.EmbeddedBridge.start(port, dir)`. |
| `jul-shim/` | Our 2-class `java.util.logging` stand-in (the iOS runtime has no `java.logging`). |
| `patches/m-extension-server-yomi.patch` | Our MPL-2.0 changes to M-Extension-Server (`NoZstdInterceptor`, jar cache, wire stats, iOS build without NewPipe, bridge token S191, S208 dex2jar fixes for R8/Kotlin 2.4 extensions + coroutines 1.11 / serialization 1.11 / OkHttp 5.4, S210 A6 `YomiHost` JNI entry point + `DalvikCore`). Publish with any build we distribute. |

Quick check that everything still works:

```bash
scripts/keiyoushi-poc/setup.sh && scripts/keiyoushi-poc/run-server.sh
python3 scripts/keiyoushi-poc/call.py ~/Desktop/Projects/Yomi/Tools/keiyoushi-poc/apks/tachiyomi-en.asurascans-v1.6.69.apk solo
pkill -f "Launcher 18765"
```

Licences: M-Extension-Server MPL-2.0 (our patch must stay public); OpenJDK GPLv2 + Classpath Exception;
NewPipe Extractor (GPLv3) is left out of the iOS jar since S150 (`compileOnly`; `stage-vendor.sh` refuses a jar that has it).
`kodjodevf/m_extension_server` (Mangayomi's Flutter plugin) has **no licence** — read for facts only, never copy.
