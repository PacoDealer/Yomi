#!/usr/bin/env python3
"""Rebuilds the website's What's new page from Yomi's GitHub Releases (tags build-N).

The releases are the one source of truth: build-testflight.sh creates one per upload (publish-release.sh), and this
script turns them into Firebase/site/whats-new.html, newest first. Only the part between the changelog markers is
rewritten, so the page's look stays hand-made. release-notes/next.md, when it exists, shows on top as "Next beta".

  whats-new.py                 rebuild the page (no deploy)
  whats-new.py --deploy        rebuild, `firebase deploy --only hosting:site`, commit the page in the Firebase git
  whats-new.py --out FILE      write the page somewhere else (testing)
  whats-new.py --clean NOTES   print a notes file the way it is published; exit 1 if it has no "- " lines

Notes format (Markdown, also the GitHub release body): "### Heading" lines, each followed by "- " lines.
<!-- comments --> are dropped. Reading the releases uses the local `gh` login; nothing secret goes to GitHub.
"""
import argparse
import datetime
import html
import json
import os
import re
import subprocess
import sys

REPO = "PacoDealer/Yomi"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # iOS/
FIREBASE = os.environ.get("YOMI_FIREBASE_DIR", os.path.normpath(os.path.join(ROOT, "..", "Firebase")))
PAGE = os.path.join(FIREBASE, "site", "whats-new.html")
NEXT = os.path.join(ROOT, "release-notes", "next.md")
START = "<!-- changelog:start (generated from the GitHub releases by iOS/scripts/changelog/whats-new.py) -->"
END = "<!-- changelog:end -->"
UPLOADED = re.compile(r"<!--\s*uploaded:\s*(\d{4}-\d{2}-\d{2})\s*-->")


class NotesError(Exception):
    pass


def parse_notes(text):
    """Notes Markdown -> [(heading, [items])]. Raises NotesError when nothing would be published."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    sections = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        m = re.match(r"^#{1,6}\s+(.+)$", line)
        if m:
            sections.append((m.group(1).strip(), []))
            continue
        m = re.match(r"^\s*[-*]\s+(.+)$", line)
        if m:
            if not sections:
                raise NotesError(f"a '- ' line comes before any '### Heading': {line.strip()}")
            sections[-1][1].append(m.group(1).strip())
            continue
        if raw[:1].isspace() and sections and sections[-1][1]:  # wrapped continuation of the previous item
            sections[-1][1][-1] += " " + line.strip()
            continue
        raise NotesError(f"line is neither a '### Heading' nor a '- ' item: {line.strip()}")
    sections = [(h, items) for h, items in sections if items]
    if not sections:
        raise NotesError("no '- ' lines")
    return sections


def notes_markdown(sections):
    return "\n\n".join(f"### {h}\n" + "\n".join(f"- {i}" for i in items) for h, items in sections) + "\n"


def long_date(iso):
    d = datetime.date.fromisoformat(iso)
    return f"{d.day} {d.strftime('%B')} {d.year}"


def fetch_releases():
    out = subprocess.run(["gh", "api", f"repos/{REPO}/releases", "--paginate", "--jq", ".[]"],
                         check=True, capture_output=True, text=True).stdout
    releases = []
    for line in out.splitlines():
        r = json.loads(line)
        m = re.fullmatch(r"build-(\d+)", r["tag_name"])
        if not m or r["draft"]:
            continue
        body = r.get("body") or ""
        up = UPLOADED.search(body)
        releases.append({
            "build": int(m.group(1)),
            "prerelease": r["prerelease"],
            "name": r.get("name") or f"Build {m.group(1)}",
            "date": up.group(1) if up else r["published_at"][:10],
            "sections": parse_notes(body),
        })
    return sorted(releases, key=lambda r: r["build"], reverse=True)


def block(title, date_line, sections):
    esc = lambda s: html.escape(s, quote=False)
    lines = [f"    <h2>{esc(title)}</h2>", f'    <p class="date">{esc(date_line)}</p>']
    for heading, items in sections:
        lines.append(f"    <h3>{esc(heading)}</h3>")
        lines.append("    <ul>")
        lines += [f"      <li>{esc(i)}</li>" for i in items]
        lines.append("    </ul>")
    return "\n".join(lines)


def render(releases, next_sections):
    blocks = []
    if next_sections:
        blocks.append(block("Next beta", "Not released yet", next_sections))
    for r in releases:
        if r["prerelease"]:
            blocks.append(block(f"Build {r['build']}", long_date(r["date"]), r["sections"]))
        else:  # App Store version
            blocks.append(block(r["name"], f"{long_date(r['date'])} · App Store", r["sections"]))
    if not blocks:
        blocks.append("    <p>No builds yet.</p>")
    return "\n\n".join(blocks)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--deploy", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--clean", metavar="NOTES")
    a = ap.parse_args()

    if a.clean:
        try:
            with open(a.clean, encoding="utf-8") as f:
                sys.stdout.write(notes_markdown(parse_notes(f.read())))
        except (OSError, NotesError) as e:
            sys.exit(f"{a.clean}: {e}")
        return

    next_sections = None
    if os.path.exists(NEXT):
        with open(NEXT, encoding="utf-8") as f:
            next_sections = parse_notes(f.read())
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    i, j = page.find(START), page.find(END)
    if i < 0 or j < i:
        sys.exit(f"{PAGE}: changelog markers not found")
    page = page[:i + len(START)] + "\n" + render(fetch_releases(), next_sections) + "\n    " + page[j:]
    out = a.out or PAGE
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"Wrote {out}")

    if a.deploy:
        if subprocess.run(["firebase", "deploy", "--only", "hosting:site"], cwd=FIREBASE).returncode:
            sys.exit("firebase deploy failed. If it says the credentials are no longer valid, run "
                     "`firebase login --reauth`, then `python3 scripts/changelog/whats-new.py --deploy`.")
        if subprocess.run(["git", "diff", "--quiet", "--", "site/whats-new.html"], cwd=FIREBASE).returncode:
            subprocess.run(["git", "commit", "-q", "-m", "What's new: rebuilt from the GitHub releases",
                            "--", "site/whats-new.html"], cwd=FIREBASE, check=True)


if __name__ == "__main__":
    main()
