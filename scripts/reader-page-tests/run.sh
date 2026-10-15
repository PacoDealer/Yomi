#!/bin/sh
# F17 (S169): crop borders, two-page pairing and automatic background — Yomi has no unit-test target, so the files
# compile on macOS.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-reader-page-tests"
swiftc -O -o "$out" ../../Yomi/Features/Reader/PageBorders.swift ../../Yomi/Features/Reader/PageAnalysis.swift main.swift
"$out"
