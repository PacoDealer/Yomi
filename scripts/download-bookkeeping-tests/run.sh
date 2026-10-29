#!/bin/sh
# S195 (S189 audit "Tests" gap): download bookkeeping — which page files count as downloaded, what a resumed download
# fetches again, and the chapter row's downloaded flag (`DownloadQueries`, refresh inserts). Same GRDB as the app.
set -e
cd "$(dirname "$0")"
pkg="${TMPDIR:-/tmp}/yomi-download-bookkeeping-tests"
src="$pkg/Sources/DownloadBookkeepingTests"
rm -rf "$src"; mkdir -p "$src"
ln -sf "$PWD/main.swift" "$src/main.swift"
for f in Features/More/TallPageSplitter.swift Database/Queries/DownloadQueries.swift \
         Database/DatabaseManager.swift Core/ChapterRecognition.swift Models/Manga.swift Models/Chapter.swift \
         Models/Novel.swift Models/Category.swift Models/Extension.swift; do
  ln -sf "$PWD/../../Yomi/$f" "$src/$(basename "$f")"
done
cat > "$pkg/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "DownloadBookkeepingTests",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.0")],  // = the app's pin
    targets: [.executableTarget(name: "DownloadBookkeepingTests", dependencies: [.product(name: "GRDB", package: "GRDB.swift")])]
)
SWIFT
swift build -c debug --package-path "$pkg" 2>&1 | grep -E "error:" || true
"$pkg/.build/debug/DownloadBookkeepingTests"
