#!/bin/sh
# L4 (S173): reading streak + repair rules — Yomi has no unit-test target, so the file compiles on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-streak-tests"
swiftc -O -o "$out" ../../Yomi/Core/ReadingStreak.swift main.swift
"$out"
