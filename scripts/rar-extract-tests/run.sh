#!/bin/sh
# S179: checks Core/RarExtract.swift (one pass through a RAR) against Unrar.swift's own per-entry extract — same bytes
# for every entry — and times both. Pass .cbr/.rar files; RAR archives aren't kept in the repo (make test ones with
# RARLAB's `rar`: `rar a -s` = solid, RAR 6.x `-ma4` = RAR4; ROADMAP S179).
#   run.sh solid5.cbr plain5.cbr solid4.cbr [--fast]   (--fast: skip the slow per-entry timing, compare 10 entries)
set -e
cd "$(dirname "$0")"
pkg="${TMPDIR:-/tmp}/yomi-rar-extract-tests"
mkdir -p "$pkg/Sources/RarExtractTests"
ln -sf "$PWD/main.swift" "$pkg/Sources/RarExtractTests/main.swift"
ln -sf "$PWD/../../Yomi/Core/RarExtract.swift" "$pkg/Sources/RarExtractTests/RarExtract.swift"
cat > "$pkg/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "RarExtractTests",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/mtgto/Unrar.swift", exact: "0.5.4")],  // = the app's pin
    targets: [.executableTarget(name: "RarExtractTests", dependencies: [.product(name: "Unrar", package: "Unrar.swift")])]
)
SWIFT
swift build -c release --package-path "$pkg" 2>&1 | grep -E "error|warning: .*RarExtract" || true
"$pkg/.build/release/RarExtractTests" "$@"
