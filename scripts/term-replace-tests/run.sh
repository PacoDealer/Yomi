#!/bin/sh
# I (S177): term replacement in novel chapters — Yomi has no unit-test target, so the file compiles on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-term-replace-tests"
swiftc -O -o "$out" ../../Yomi/Core/TermReplacer.swift main.swift
"$out"
