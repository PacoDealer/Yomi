#!/usr/bin/env python3
"""Summarize an xctrace recording of Yomi: hitches, potential hangs and Perf signpost intervals (S129 baseline).

Usage: scripts/perf/summarize.py <file.trace> [more.trace ...]
Record with scripts/perf/record.sh, which uses Time Profiler + Points of Interest + Hitches.
"""
import subprocess, sys, xml.etree.ElementTree as ET
from collections import defaultdict

def table(trace, schema):
    xp = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    out = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xp],
                         capture_output=True, text=True).stdout
    root = ET.fromstring(out)
    rows, cols, ids = [], [], {}
    for node in root.findall("node"):  # an instrument can add its own table with the same schema
        schema = node.find("schema")
        if schema is not None:
            cols = [c.findtext("mnemonic") for c in schema.findall("col")]
        def val(el):
            return ids[el.attrib["ref"]] if "ref" in el.attrib else el
        for row in node.findall("row"):
            for el in row.iter():
                if "id" in el.attrib:
                    ids[el.attrib["id"]] = el
            rows.append({c: (None if e.tag == "sentinel" else val(e)) for c, e in zip(cols, list(row))})
    return rows

def num(el):
    return int(el.text) if el is not None and el.text else 0

def summarize(trace):
    print(f"== {trace}")
    hitches = [r for r in table(trace, "hitches") if r.get("process") is not None
               and "Yomi" in r["process"].get("fmt", "") and not (r.get("is-system") is not None and r["is-system"].text == "1")]
    durs = sorted(num(r["duration"]) / 1e6 for r in hitches)
    total = sum(durs)
    print(f"hitches: {len(durs)}  total {total:.0f} ms  worst {durs[-1] if durs else 0:.0f} ms"
          f"  >100ms: {sum(d > 100 for d in durs)}")
    hangs = [r for r in table(trace, "potential-hangs") if r.get("process") is not None
             and "Yomi" in r["process"].get("fmt", "")]
    hd = sorted((num(r["duration"]) / 1e6 for r in hangs), reverse=True)
    print(f"potential hangs: {len(hd)}  " + ", ".join(f"{d:.0f} ms" for d in hd[:8]))
    open_ = {}
    intervals = defaultdict(list)
    for r in table(trace, "os-signpost"):
        sub = r.get("subsystem")
        if sub is None or sub.text != "pacodealer.Yomi":
            continue
        key = (r["identifier"].text, r["name"].text)
        kind, t = r["event-type"].text, num(r["time"])
        if kind == "Begin":
            open_[key] = t
        elif kind == "End" and key in open_:
            intervals[r["name"].text].append((t - open_.pop(key)) / 1e6)
    for name, ds in sorted(intervals.items()):
        print(f"  {name:14} n={len(ds):2}  " + "  ".join(f"{d:.0f}" for d in ds) + " ms")
    for (_, name) in open_:
        print(f"  {name:14} (still open at end of trace)")

for t in sys.argv[1:]:
    summarize(t)
