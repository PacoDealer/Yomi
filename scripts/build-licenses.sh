#!/bin/bash
# Collects the licence texts of everything Yomi bundles into Yomi/Resources/Licenses (committed), shown in
# More → About → Open Source Licenses (Features/More/LicensesView.swift). Texts are copied from the exact copies
# we build from — never typed by hand. Re-run after changing a Swift package, a JS library or the Keiyoushi runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${KEIYOUSHI_POC_WORK:-$HOME/Desktop/Projects/Yomi/Tools/keiyoushi-poc}"
PKGS="${YOMI_SOURCE_PACKAGES:-$HOME/Library/Developer/Xcode/DerivedData/Yomi-personal/SourcePackages/checkouts}"
JAR="$ROOT/Vendor/Keiyoushi/MExtensionServer.jar"
OUT="$ROOT/Yomi/Resources/Licenses"
TP="$ROOT/scripts/third-party-licences"   # committed copies, so the build needs no network
for need in "$PKGS/GRDB.swift/LICENSE" "$PKGS/Unrar.swift/Sources/Cunrar/license.txt" "$ROOT/Vendor/PLzmaSDK/LICENSE" "$ROOT/node_modules/cheerio/LICENSE" "$JAR" "$WORK/jre-base/legal/java.base/LICENSE" \
            "$WORK/M-Extension-Server/LICENSE" "$WORK/openjdk-ios/SOURCE_MANIFEST.txt" "$TP/ported/mihon-LICENSE.txt"; do
  [ -e "$need" ] || { echo "Missing $need" >&2; exit 1; }
done
rm -rf "$OUT" && mkdir -p "$OUT"
rule() { printf '\n\n%s\n%s\n%s\n\n' "────────────────────────────────────────" "$1" "────────────────────────────────────────"; }

# Swift packages
cp "$PKGS/GRDB.swift/LICENSE"  "$OUT/licence-grdb.txt"
cp "$PKGS/Kingfisher/LICENSE"  "$OUT/licence-kingfisher.txt"
cp "$PKGS/Pulse/LICENSE.md"    "$OUT/licence-pulse.txt"
# Unrar.swift (MIT) wraps RARLAB's UnRAR source, whose licence asks for its own text to be shown (RESEARCH §27).
{ cat "$PKGS/Unrar.swift/LICENSE.txt"
  rule "UnRAR source code (RARLAB) — its licence"; cat "$PKGS/Unrar.swift/Sources/Cunrar/license.txt"
  rule "UnRAR source code (RARLAB) — acknowledgments"; cat "$PKGS/Unrar.swift/Sources/Cunrar/acknow.txt"
} > "$OUT/licence-unrar.txt"
# PLzmaSDK (MIT, vendored in Vendor/PLzmaSDK) wraps Igor Pavlov's LZMA SDK (public domain) — CB7/7z, S175.
{ cat "$ROOT/Vendor/PLzmaSDK/LICENSE"
  rule "LZMA SDK (Igor Pavlov)"
  echo "The LZMA SDK is placed in the public domain (https://www.7-zip.org/sdk.html); its source files say so."
  echo "Version built into Yomi: LZMA SDK $(sed -n 's/.*MY_VERSION_NUMBERS "\(.*\)".*/\1/p' "$ROOT/Vendor/PLzmaSDK/src/C/7zVersion.h")."
} > "$OUT/licence-plzmasdk.txt"

# JS libraries bundled into Resources/yomi-js-libs.js (scripts/build-js-libs.mjs): each one plus everything it pulls in.
( cd "$ROOT" && node -e '
const fs = require("fs"), path = require("path");
const seen = new Map();
function walk(name, from) {
  // Not require.resolve: packages with an "exports" map hide their package.json from it.
  let dir = null;
  for (let d = from; ; d = path.dirname(d)) {
    const c = path.join(d, "node_modules", name);
    if (fs.existsSync(path.join(c, "package.json"))) { dir = c; break; }
    if (d === path.dirname(d)) break;
  }
  if (!dir) throw new Error(`${name} (needed from ${from}) is not installed — run npm install`);
  if (seen.has(dir)) return;
  const pkg = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8"));
  const file = fs.readdirSync(dir).find(f => /^licen[sc]e/i.test(f));
  seen.set(dir, { name: pkg.name, version: pkg.version, license: pkg.license, text: file ? fs.readFileSync(path.join(dir, file), "utf8") : null });
  for (const dep of Object.keys(pkg.dependencies || {})) walk(dep, dir);
}
for (const root of ["cheerio", "dayjs", "core-js"]) {
  seen.clear(); walk(root, process.cwd());
  let out = "";
  for (const p of seen.values()) {
    out += `${p.name} ${p.version} — ${p.license}\n\n${(p.text || "(no licence file in the package; see its repository)").trim()}\n\n\n`;
  }
  fs.writeFileSync(`Yomi/Resources/Licenses/licence-${root}.txt`, out.trim() + "\n");
}' )

# OpenJDK (Mobile port, Zero interpreter): GPLv2 + Classpath Exception, with where the source is.
{
  echo "OpenJDK is licensed under the GNU General Public License, version 2, with the Classpath Exception."
  echo "Yomi runs it unmodified as a separate runtime (OpenJDKRuntime.framework). Corresponding source:"
  echo
  cat "$WORK/openjdk-ios/SOURCE_MANIFEST.txt"
  for f in LICENSE ASSEMBLY_EXCEPTION ADDITIONAL_LICENSE_INFO; do rule "$f"; cat "$WORK/jre-base/legal/java.base/$f"; done
  for f in "$WORK"/jre-base/legal/java.base/*.md; do rule "Third-party notice: $(basename "$f" .md)"; cat "$f"; done
  rule "libffi (linked into the runtime)"; cat "$TP/libffi.txt"
} > "$OUT/licence-openjdk.txt"

# M-Extension-Server (MPL-2.0) — we ship a modified build; MPL requires saying where the changes are.
{
  echo "M-Extension-Server (https://github.com/kodjodevf/M-Extension-Server) is licensed under the Mozilla Public"
  echo "License 2.0. Yomi ships a modified build. Our changes, under the same licence:"
  echo "https://github.com/PacoDealer/Yomi/blob/main/scripts/keiyoushi-poc/patches/m-extension-server-yomi.patch"
  rule "Mozilla Public License 2.0"; cat "$WORK/M-Extension-Server/LICENSE"
} > "$OUT/licence-m-extension-server.txt"

# Code ported into Yomi's own sources (S170). MPL: the one ported file stays under the MPL and its source is linked;
# Apache: the licence text goes with derivative code. The repo must stay public for the MPL link to work.
{
  echo "Yomi/Features/Reader/PageBorders.swift (crop borders) is a Swift port of borders.cpp and borders.h from"
  echo "tachiyomiorg/image-decoder (https://github.com/tachiyomiorg/image-decoder), licensed under the Mozilla Public"
  echo "License 2.0. That file alone is under the MPL; its source code:"
  echo "https://github.com/PacoDealer/Yomi/blob/main/Yomi/Features/Reader/PageBorders.swift"
  rule "Mozilla Public License 2.0"; cat "$WORK/M-Extension-Server/LICENSE"
} > "$OUT/licence-image-decoder.txt"
{
  echo "Parts of Yomi are ported from or based on Mihon (https://github.com/mihonapp/mihon), Apache License 2.0,"
  echo "changed for Yomi (Swift, Yomi's own types):"
  echo "  Core/ChapterRecognition.swift — ChapterRecognition"
  echo "  Core/FetchInterval.swift — FetchInterval, ReleaseSchedule, ReleasePattern"
  echo "  Features/Reader/PageAnalysis.swift — ImageUtil.chooseBackground; two-page rules from WebGpuViewer"
  echo "  Features/More/TallPageSplitter.swift — TallImageSplitCalculator"
  echo "  Features/Reader/ReaderPagePrefetcher.swift — page order idea from HttpPageLoader"
  rule "Apache License 2.0"; cat "$TP/ported/mihon-LICENSE.txt"
} > "$OUT/licence-mihon.txt"

# Libraries packed inside the extension-server jar: the list, then every licence/notice file the jar itself carries.
{
  cat <<'EOF'
The extension server contains these libraries (licence in brackets):

Kotlin standard library, kotlin-reflect, kotlinx.coroutines, kotlinx.serialization [Apache-2.0]
OkHttp, Okio [Apache-2.0]
Tachiyomi / Mihon source API [Apache-2.0]
Android Open Source Project: framework stubs, dx, apksig, libcore [Apache-2.0]
dex2jar [Apache-2.0]
RxJava, RxKotlin [Apache-2.0]
Jackson [Apache-2.0]
Typesafe Config, config4k [Apache-2.0]
kotlin-logging [Apache-2.0]
Multiplatform Settings [Apache-2.0]
Chicory, quickjs4j [Apache-2.0] — includes QuickJS [MIT]
webp-imageio [Apache-2.0]
JetBrains annotations [Apache-2.0]
JavaParser [Apache-2.0, at our option; also offered under LGPL-3.0]
ICU4J [Unicode License v3]
Protocol Buffers (javalite) [BSD-3-Clause]
ASM [BSD-3-Clause]
ANTLR [BSD-3-Clause]
TwelveMonkeys ImageIO [BSD-3-Clause]
NanoHTTPD [BSD-3-Clause]
apk-parser [BSD-2-Clause]
jsoup [MIT]
Kodein DI [MIT]
Injekt [MIT]
SLF4J [MIT]
EOF
  unzip -Z1 "$JAR" | grep -E '(^|/)(LICENSE|NOTICE)[^/]*$|^META-INF/[^/]*-(LICENSE|NOTICE)$|^NOTICES/.+' | sort -u | while read -r f; do
    rule "From the server archive: $f"; unzip -p "$JAR" "$f"
  done
  # Libraries whose jars carry no licence file: texts fetched once from each project's repository (S151).
  for f in "$TP"/*.txt; do
    [ "$(basename "$f")" = libffi.txt ] && continue
    rule "$(basename "$f" .txt)"; cat "$f"
  done
} > "$OUT/licence-server-libraries.txt"

# Plain text only: the screen shows these in a Text view.
for f in "$OUT"/*.txt; do LC_ALL=C tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
ls -l "$OUT"
