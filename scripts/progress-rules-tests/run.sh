#!/bin/sh
# S190: tracker count never goes down + backup restore merge (S189 audit #1, #2). Compiled on macOS (no unit-test target).
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-progress-rules-tests"
swiftc -O -o "$out" ../../Yomi/Models/Chapter.swift ../../Yomi/Models/Manga.swift ../../Yomi/Models/Novel.swift ../../Yomi/Core/ProgressRules.swift main.swift
"$out"
