#!/bin/sh
# S193 (#227): ApkSignature — Android v2/v3 signature check for Keiyoushi APKs. Real APKs are read from
# ~/Desktop/Projects/Yomi/Tools/keiyoushi-poc/apks (never committed: extensions stay out of this repo); without them only
# the file-free checks run.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-apk-signature-tests"
swiftc -O -o "$out" ../../Yomi/Features/Keiyoushi/ApkSignature.swift main.swift
"$out" "${YOMI_TEST_APKS:-$PWD/../../../Tools/keiyoushi-poc/apks}"
