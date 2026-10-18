#!/usr/bin/env python3
"""Builds Yomi/Localizable.xcstrings from what the compiler extracted plus the translation maps here (S180).

The catalog is GENERATED — edit es-*.json / plurals.json and re-run, don't edit the catalog in Xcode.

  1. Build the app once (xcodebuild … build) so DerivedData has the .stringsdata files.
  2. python3 scripts/localization/build-catalog.py            # writes the catalog, lists keys with no Spanish

dynamic.json lists keys the code looks up at run time (not extractable).

Checks: every translation keeps its key's format specifiers (same kinds, same order), so a String(format:) can't
read the wrong argument. Plural keys (plurals.json) get one/other variations for English and Spanish.
"""
import glob, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CATALOG = ROOT / "Yomi" / "Localizable.xcstrings"
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")


def derived_data():
    dirs = sorted(glob.glob(str(Path.home() / "Library/Developer/Xcode/DerivedData/Yomi-*")),
                  key=lambda p: Path(p).stat().st_mtime, reverse=True)
    if not dirs:
        sys.exit("no DerivedData/Yomi-* — build the app first")
    return dirs[0]


def extracted_keys():
    files = glob.glob(derived_data() + "/Build/Intermediates.noindex/Yomi.build/Debug-iphonesimulator/Yomi.build/"
                      "Objects-normal/arm64/*.stringsdata")
    keys = {}
    for f in sorted(files):
        data = json.loads(Path(f).read_text())
        for item in data["tables"].get("Localizable", []):
            keys.setdefault(item["key"], item.get("comment", ""))
    return keys


def specs(s):
    return [m for m in SPEC.findall(s) if m != "%%"]


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def main():
    keys = extracted_keys()
    # English strings the code looks up at run time (LocalizedStringKey(label), String.LocalizationValue(name)) —
    # the compiler can't extract them, so they are listed by hand.
    for key in json.loads((HERE / "dynamic.json").read_text()):
        keys.setdefault(key, "Looked up at run time")
    es = {}
    for f in sorted(HERE.glob("es-*.json")):
        es.update(json.loads(f.read_text()))
    plurals = json.loads((HERE / "plurals.json").read_text())

    problems, missing, strings = [], [], {}
    for key in sorted(keys):
        entry = {}
        if keys[key]:
            entry["comment"] = keys[key]
        if key in plurals:
            p = plurals[key]
            for lang in ("en", "es"):
                for form in ("one", "other"):
                    if specs(p[lang][form]) != specs(key):
                        problems.append(f"plural {lang}.{form} specifiers differ: {key!r}")
            entry["localizations"] = {lang: {"variations": {"plural": {
                form: unit(p[lang][form]) for form in ("one", "other")}}} for lang in ("en", "es")}
        elif key in es:
            if specs(es[key]) != specs(key):
                problems.append(f"specifiers differ: {key!r} → {es[key]!r}")
            entry["localizations"] = {"es": unit(es[key])}
        else:
            missing.append(key)
        strings[key] = entry

    unused = sorted(set(es) - set(keys)) + sorted(set(plurals) - set(keys))
    if problems:
        sys.exit("\n".join(problems))
    CATALOG.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                                  indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"{CATALOG.relative_to(ROOT)}: {len(strings)} keys, {len(strings) - len(missing)} in Spanish, "
          f"{len(missing)} missing, {len(unused)} unused translations")
    for k in missing:
        print("  missing:", json.dumps(k, ensure_ascii=False))
    for k in unused:
        print("  unused: ", json.dumps(k, ensure_ascii=False))


main()
