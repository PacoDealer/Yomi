#!/bin/sh
# Mihon's FetchIntervalTest.kt ported (S166) — Yomi has no unit-test target, so the file compiles on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-fetch-interval-tests"
swiftc -O -o "$out" ../../Yomi/Core/FetchInterval.swift main.swift
"$out"
