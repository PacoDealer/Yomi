#!/bin/bash
# Builds the novel reader's bundled fonts (S136, RESEARCH §25.10 #1) into Yomi/Resources/ReaderFonts as WOFF2.
# All four families are SIL OFL 1.1; their licenses are copied next to the fonts.
# Full variable files would be ~3.5 MB, so each is cut down for body text:
#   - optical size pinned to a reading size, weight limited to 400–700 (regular…bold),
#   - glyphs subset to Latin (incl. Vietnamese), Greek, Cyrillic and common punctuation/symbols,
#   - TrueType hinting dropped (Apple platforms don't use it), then WOFF2.
# Characters outside the subset fall back to the system font per glyph, as with any web font.
# Needs fontTools + brotli:  PYTHON=/path/to/python scripts/build-reader-fonts.sh   (pip install fonttools brotli)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Yomi/Resources/ReaderFonts"
PY="${PYTHON:-python3}"
"$PY" -c "import fontTools, brotli" || { echo "need fontTools + brotli for $PY"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

GF=https://raw.githubusercontent.com/google/fonts/main/ofl
OD=https://raw.githubusercontent.com/antijingoist/opendyslexic/master
fetch() { curl -sfL "$1" -o "$TMP/$2" || { echo "download failed: $1"; exit 1; }; }

fetch "$GF/literata/Literata%5Bopsz,wght%5D.ttf"                          Literata.ttf
fetch "$GF/literata/Literata-Italic%5Bopsz,wght%5D.ttf"                   Literata-Italic.ttf
fetch "$GF/literata/OFL.txt"                                              Literata-OFL.txt
fetch "$GF/newsreader/Newsreader%5Bopsz,wght%5D.ttf"                      Newsreader.ttf
fetch "$GF/newsreader/Newsreader-Italic%5Bopsz,wght%5D.ttf"               Newsreader-Italic.ttf
fetch "$GF/newsreader/OFL.txt"                                            Newsreader-OFL.txt
fetch "$GF/atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext%5Bwght%5D.ttf"        AtkinsonHyperlegibleNext.ttf
fetch "$GF/atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext-Italic%5Bwght%5D.ttf" AtkinsonHyperlegibleNext-Italic.ttf
fetch "$GF/atkinsonhyperlegiblenext/OFL.txt"                              AtkinsonHyperlegibleNext-OFL.txt
for s in Regular Bold Italic Bold-Italic; do fetch "$OD/compiled/OpenDyslexic-$s.otf" "OpenDyslexic-$s.otf"; done
fetch "$OD/OFL.txt"                                                       OpenDyslexic-OFL.txt

UNICODES="U+0000-024F,U+0259,U+02B0-02FF,U+0300-036F,U+0370-03FF,U+0400-04FF,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-2199,U+2212,U+2215,U+FEFF,U+FFFD"

# instance <in> <out> <axis limits…>  (variable fonts only)
instance() { local in="$1" out="$2"; shift 2; "$PY" -m fontTools.varLib.instancer "$TMP/$in" "$@" -o "$TMP/$out" -q; }
subset() {
  "$PY" -m fontTools.subset "$TMP/$1" --unicodes="$UNICODES" --layout-features='*' --no-hinting \
    --flavor=woff2 --output-file="$OUT/$2"
}

instance Literata.ttf               lit.ttf   opsz=12 wght=400:700
instance Literata-Italic.ttf        liti.ttf  opsz=12 wght=400:700
instance Newsreader.ttf             nr.ttf    opsz=16 wght=400:700
instance Newsreader-Italic.ttf      nri.ttf   opsz=16 wght=400:700
instance AtkinsonHyperlegibleNext.ttf        ah.ttf  wght=400:700
instance AtkinsonHyperlegibleNext-Italic.ttf ahi.ttf wght=400:700

subset lit.ttf  Literata.woff2
subset liti.ttf Literata-Italic.woff2
subset nr.ttf   Newsreader.woff2
subset nri.ttf  Newsreader-Italic.woff2
subset ah.ttf   AtkinsonHyperlegibleNext.woff2
subset ahi.ttf  AtkinsonHyperlegibleNext-Italic.woff2
for s in Regular Bold Italic; do subset "OpenDyslexic-$s.otf" "OpenDyslexic-$s.woff2"; done
subset OpenDyslexic-Bold-Italic.otf OpenDyslexic-BoldItalic.woff2

cp "$TMP"/*-OFL.txt "$OUT/"
ls -l "$OUT"
du -sh "$OUT"
