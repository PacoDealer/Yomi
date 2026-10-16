#!/usr/bin/env python3
"""Writes each plugin's SHA-256 into Firebase/public/index.json (`sha256`, KNOWN_ISSUES #151).

Runs as the `plugins` hosting target's predeploy hook (Firebase/firebase.json), so the hashes always describe the
files being deployed. Yomi refuses an install whose bytes differ from the catalog's hash. Entries whose file is not in
public/ are left without a hash (the app then skips the check)."""
import hashlib, json, sys
from pathlib import Path
from urllib.parse import urlparse

public = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "Firebase" / "public")
index = public / "index.json"
entries = json.loads(index.read_text())
changed = 0
for entry in entries:
    name = Path(urlparse(entry.get("fileURL", "")).path).name
    file = public / name
    if not name or not file.is_file():
        entry.pop("sha256", None)
        print(f"no local file for {entry.get('name')} ({name or 'no fileURL'}) — no hash", file=sys.stderr)
        continue
    digest = hashlib.sha256(file.read_bytes()).hexdigest()
    if entry.get("sha256") != digest:
        entry["sha256"] = digest
        changed += 1
index.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n")
print(f"index.json: {len(entries)} entries, {changed} hashes updated")
