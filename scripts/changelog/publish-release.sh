#!/bin/bash
# Creates (or updates) the GitHub release for an uploaded build, then rebuilds and deploys the website's What's new.
# build-testflight.sh calls this after a successful upload; run it by hand to retry or to seed an older build.
#
#   publish-release.sh N                       release build-N at HEAD (HEAD must be build N), marked pre-release
#   publish-release.sh N --commit SHA          same, for an older build's commit (seeding)
#   publish-release.sh N --app-store 1.0       build N went to the App Store: mark its release "Version 1.0", latest
#   --no-deploy                                skip the website step
# Notes come from release-notes/build-N.md (draft-notes.py). YOMI_RELEASE_DATE=YYYY-MM-DD overrides the upload date.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
BUILD="${1:?usage: publish-release.sh BUILD [--commit SHA] [--app-store VERSION] [--no-deploy]}"; shift
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Build must be a number." >&2; exit 1; }
COMMIT=HEAD; STORE=""; DEPLOY=1
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) COMMIT="$2"; shift 2 ;;
    --app-store) STORE="$2"; shift 2 ;;
    --no-deploy) DEPLOY=0; shift ;;
    *) echo "Unknown option $1" >&2; exit 1 ;;
  esac
done
REPO=PacoDealer/Yomi
TAG="build-$BUILD"

if [ -n "$STORE" ]; then
  gh release edit "$TAG" -R "$REPO" --title "Version $STORE" --prerelease=false --latest
  echo "Release $TAG is now Version $STORE (latest)."
else
  NOTES="release-notes/$TAG.md"
  [ -f "$NOTES" ] || { echo "No $NOTES — run scripts/changelog/draft-notes.py first." >&2; exit 1; }
  SHA=$(git rev-parse --verify "$COMMIT^{commit}")
  [ "$(git rev-list --count "$SHA")" = "$BUILD" ] || { echo "$COMMIT is build $(git rev-list --count "$SHA"), not $BUILD." >&2; exit 1; }
  git fetch -q origin main
  git merge-base --is-ancestor "$SHA" origin/main || { echo "$SHA is not on GitHub's main yet — push first." >&2; exit 1; }
  BODY=$(mktemp)
  python3 scripts/changelog/whats-new.py --clean "$NOTES" > "$BODY"
  printf '\n<!-- uploaded: %s -->\n' "${YOMI_RELEASE_DATE:-$(date +%F)}" >> "$BODY"
  if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    gh release edit "$TAG" -R "$REPO" --notes-file "$BODY"
    echo "Updated the notes of release $TAG."
  else
    gh release create "$TAG" -R "$REPO" --target "$SHA" --title "Build $BUILD" --prerelease --notes-file "$BODY"
  fi
  git fetch -q --tags origin
  # The Next beta list is now this build's notes (draft-notes.py started from it).
  [ "$SHA" = "$(git rev-parse HEAD)" ] && rm -f release-notes/next.md
fi

if [ "$DEPLOY" = 1 ]; then
  python3 scripts/changelog/whats-new.py --deploy
else
  echo "Skipped the website (--no-deploy)."
fi
