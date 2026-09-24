#!/bin/bash
# Runs the patched M-Extension-Server on the Mac the way the iPhone will: java.base-only runtime, interpreter only
# (-Xint approximates OpenJDK Zero, but Zero on the phone will be slower), our java.logging stand-in, IPv4, 8 MB stacks.
# Same JVM options the iOS host will pass to JNI_CreateJavaVM. Log: $WORK/server.log. Port 18765.
set -euo pipefail
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
cd "$WORK"
SERVER_JAR=$(ls M-Extension-Server/server/build/MExtensionServer-*.jar | head -1)

pkill -f "Launcher 18765" 2>/dev/null || true
for _ in $(seq 1 20); do lsof -i :18765 -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.5; done

jre-base/bin/java -Xint -XX:+UseSerialGC -Xms128m -Xmx512m -Xss8m \
  -Xbootclasspath/a:harness/java-logging-shim.jar \
  -Djava.net.preferIPv4Stack=true -Djava.awt.headless=true -Dfile.encoding=UTF-8 \
  -Djava.io.tmpdir="$WORK/tmp" -Duser.home="$WORK/appdir" \
  -cp "harness:$SERVER_JAR" Launcher 18765 "$WORK/appdir" > server.log 2>&1 &

for _ in $(seq 1 60); do grep -q BRIDGE_READY server.log 2>/dev/null && break; sleep 1; done
grep BRIDGE_READY server.log || { tail -20 server.log; exit 1; }
