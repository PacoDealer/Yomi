#!/usr/bin/env python3
"""Drafts release-notes/build-N.md from the commits since the previous build-* tag.

  draft-notes.py           draft for the build the next upload gets (= commit count of HEAD)
  draft-notes.py N         draft for build N (HEAD must be that build's commit)
  draft-notes.py --force   overwrite an existing draft

The draft is a starting point, not the notes: rewrite it in plain user language (short lines, "### New" and
"### Fixed", no issue numbers, no session numbers, no names) and show it to PacoDealer with the upload question.
If release-notes/next.md exists (the "Next beta" list on the website) it is used as the draft body. The raw commit
list stays below, inside <!-- -->, which is never published. release-notes/ is git-ignored on purpose: committing
the notes would change the build number.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # iOS/
NOTES_DIR = os.path.join(ROOT, "release-notes")
APP_DIRS = ("Yomi/", "YomiWidget/", "Yomi.xcodeproj/", "Config/", "Vendor/")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def changes_app(sha):
    files = git("show", "--name-only", "--format=", sha).splitlines()
    return any(f.startswith(APP_DIRS) and not f.endswith(".md") for f in files)


def tidy(subject):
    s = re.sub(r"^S\d+[a-z]?(\s+part\s+\d+)?:\s*", "", subject)  # session prefix
    s = re.sub(r"\s*\((?:#\d+[^)]*|[^)]*'s pick)\)", "", s)     # (#254), (#253, part), (PacoDealer's pick)
    s = re.sub(r"\s*#\d+\b", "", s)
    s = s.strip().rstrip(".")
    return (s[:1].upper() + s[1:] + ".") if s else ""


def main():
    args = [a for a in sys.argv[1:] if a != "--force"]
    force = "--force" in sys.argv
    head_count = int(git("rev-list", "--count", "HEAD"))
    build = int(args[0]) if args else head_count
    if build != head_count:
        sys.exit(f"HEAD is build {head_count}, not {build}. Check out that build's commit first.")
    out = os.path.join(NOTES_DIR, f"build-{build}.md")
    if os.path.exists(out) and not force:
        sys.exit(f"{out} exists (pass --force to redraft).")

    subprocess.run(["git", "fetch", "-q", "--tags", "origin"], cwd=ROOT)
    prev = [int(t[6:]) for t in git("tag", "-l", "build-*").splitlines() if t[6:].isdigit() and int(t[6:]) < build]
    if not prev:
        sys.exit("No earlier build-* tag to draft from.")
    since = f"build-{max(prev)}"
    shas = git("rev-list", "--no-merges", f"{since}..HEAD").splitlines()

    new, fixed, app_lines, skipped = [], [], [], []
    for sha in shas:
        subject = git("log", "-1", "--format=%s", sha)
        line = f"{sha[:7]} {subject}".replace("--", "–")
        if not changes_app(sha):
            skipped.append(line)
            continue
        app_lines.append(line)
        text = tidy(subject)
        (fixed if re.match(r"(?i)fix", text) else new).append(text)

    next_md = os.path.join(NOTES_DIR, "next.md")
    if os.path.exists(next_md):
        with open(next_md, encoding="utf-8") as f:
            body = re.sub(r"<!--.*?-->", "", f.read(), flags=re.S).strip() + "\n"
        source = "release-notes/next.md (the website's Next beta list) — add anything newer from the commits below"
    else:
        body = ""
        if new:
            body += "### New\n" + "".join(f"- {t}\n" for t in reversed(new)) + "\n"
        if fixed:
            body += "### Fixed\n" + "".join(f"- {t}\n" for t in reversed(fixed))
        source = "commit subjects (oldest first) — rewrite every line"

    os.makedirs(NOTES_DIR, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(f"<!-- DRAFT for build {build}, from {source}.\n"
                f"     Plain user language: short lines, no issue/session numbers, no names. Comments are not published. -->\n\n")
        f.write(body)
        f.write(f"\n<!-- Commits since {since} that change the app:\n" + "\n".join(app_lines or ["(none)"]) +
                "\n\nDocs/tests/tools only (usually not worth a line):\n" + "\n".join(skipped or ["(none)"]) + "\n-->\n")
    print(out)


if __name__ == "__main__":
    main()
