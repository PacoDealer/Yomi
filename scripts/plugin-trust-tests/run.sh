#!/bin/sh
# H (S170): the checks a downloaded plugin passes before it replaces an installed one (PluginScript.swift).
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-plugin-trust-tests"
swiftc -O -o "$out" ../../Yomi/Features/Extensions/PluginScript.swift main.swift
"$out" "$@"
