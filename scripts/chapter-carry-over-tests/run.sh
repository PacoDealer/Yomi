#!/bin/sh
# Known Issue #208 (S188): ChapterCarryOver's matching rules — Yomi has no unit-test target, so the file compiles on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-chapter-carry-over-tests"
swiftc -O -o "$out" ../../Yomi/Core/ChapterCarryOver.swift main.swift
"$out"
