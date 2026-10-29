#!/bin/sh
# S196: opening a title from a website link — the pure matching rules in Core/SharedLink.swift.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-shared-link-tests"
swiftc -O -o "$out" ../../Yomi/Core/SharedLink.swift main.swift
"$out"
