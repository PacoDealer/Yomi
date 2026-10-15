#!/bin/sh
# Mihon's ChapterRecognitionTest.kt ported (S165) — Yomi has no unit-test target, so the file compiles on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-chapter-recognition-tests"
swiftc -O -o "$out" ../../Yomi/Core/ChapterRecognition.swift main.swift
"$out"
