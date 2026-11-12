#!/bin/sh
# ChapterGaps (S212): missing-chapter counts shown in a title's chapter list.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-chapter-gap-tests"
swiftc -O -o "$out" ../../Yomi/Core/ChapterGaps.swift main.swift
"$out"
