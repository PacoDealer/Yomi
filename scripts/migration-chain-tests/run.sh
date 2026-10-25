#!/bin/sh
# S193 (S189 audit #15): runs the app's real migration chain (`DatabaseManager.makeMigrator()`) on macOS — a fresh
# install, and a v1-era library with data upgraded step by step. Same GRDB as the app (Package.resolved pin).
set -e
cd "$(dirname "$0")"
pkg="${TMPDIR:-/tmp}/yomi-migration-chain-tests"
src="$pkg/Sources/MigrationChainTests"
rm -rf "$src"; mkdir -p "$src"
ln -sf "$PWD/main.swift" "$src/main.swift"
for f in Database/DatabaseManager.swift Core/ChapterRecognition.swift Models/Manga.swift Models/Chapter.swift \
         Models/Novel.swift Models/Category.swift Models/Extension.swift; do
  ln -sf "$PWD/../../Yomi/$f" "$src/$(basename "$f")"
done
cat > "$pkg/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MigrationChainTests",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.0")],  // = the app's pin
    targets: [.executableTarget(name: "MigrationChainTests", dependencies: [.product(name: "GRDB", package: "GRDB.swift")])]
)
SWIFT
swift build -c debug --package-path "$pkg" 2>&1 | grep -E "error:" || true
"$pkg/.build/debug/MigrationChainTests"
