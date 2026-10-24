#!/bin/bash
# S192: per-plugin cookie jars, the redirect check and the plugin call time limit (PluginSandbox.swift).
# Runs the binary twice against a local site: "write" saves jars, "read" (a new process) checks what came back from disk.
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/yomi-plugin-sandbox-tests"
jars=$(mktemp -d)
swiftc -O -o "$out" ../../Yomi/Features/Extensions/PluginSandbox.swift ../../Yomi/Features/Extensions/PluginNetworkPolicy.swift main.swift
fifo=$(mktemp -u); mkfifo "$fifo"
python3 -u server.py > "$fifo" &
server=$!; disown $server
trap 'kill $server 2>/dev/null; rm -rf "$jars" "$fifo"' EXIT
read -r port < "$fifo"
"$out" write "$port" "$jars"
"$out" read "$port" "$jars"
