#!/bin/sh
# L3d (S173): Text on Page grouping + reading order. Yomi has no unit-test target, so PageTextLayout.swift compiles on
# macOS. Fixed cases (box numbers taken from real pages) always run; pass image paths to also print what Vision +
# the layout make of them, e.g. run.sh ~/page.jpg ja-JP   (pages aren't kept in the repo — they're copyrighted).
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-page-text-tests"
swiftc -O -o "$out" ../../Yomi/Features/Reader/PageTextLayout.swift main.swift
"$out" "$@"
