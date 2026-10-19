#!/usr/bin/env python3
"""Fails when a doc or note under Yomi/ would be copied into the app (S184).

Yomi/ is a synchronized folder: Xcode puts EVERY file in it into the app unless project.pbxproj lists it under the
Yomi target's membershipExceptions. Until S184 the internal docs (ROADMAP, RESEARCH, KNOWN_ISSUES, …) shipped inside
every build, TestFlight included. Run by scripts/test-all.sh (and CI).
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
pbx = (ROOT / "Yomi.xcodeproj/project.pbxproj").read_text()
block = re.search(r'Exceptions for "Yomi" folder in "Yomi" target \*/ = \{.*?membershipExceptions = \((.*?)\);', pbx, re.S)
if not block:
    sys.exit("membershipExceptions for the Yomi target not found in project.pbxproj")
excluded = {e.strip().strip('"') for e in block.group(1).split(",") if e.strip()}

# Files that must never ship: notes and docs, templates, secrets examples.
patterns = ("*.md", "*.template", "*.txt.orig", "*.jsx")
missing = []
for pattern in patterns:
    for path in (ROOT / "Yomi").rglob(pattern):
        rel = path.relative_to(ROOT / "Yomi").as_posix()
        if rel not in excluded:
            missing.append(rel)

if missing:
    print("These files would be copied into the app — add them to the Yomi target's membershipExceptions:")
    for rel in sorted(missing):
        print("  ", rel)
    sys.exit(1)
print(f"OK no docs in the app ({len(excluded)} exceptions)")
