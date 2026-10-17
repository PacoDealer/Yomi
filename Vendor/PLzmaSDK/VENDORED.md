# PLzmaSDK — vendored copy

- Upstream: https://github.com/OlehKulykov/PLzmaSDK, tag 1.6.1, commit `f449bc3e13204b68a7e05fca80ce8c31642085ec`
  (MIT; contains Igor Pavlov's LZMA SDK 26.01, public domain). Used for CB7/7z local files (`Core/ComicArchive.swift`).
- Copied: `src/`, `swift/`, `libplzma.h`, `libplzma.hpp`, `resources/PrivacyInfo.xcprivacy`, `LICENSE`, `README.md`. Left out:
  tests, test files and the other platforms (Node, Android, ObjC, CMake).
- **One change: `src/Asm/` removed** (S175). `src/Asm/arm64/LzmaDecOpt.S` is never used — nothing defines
  `Z7_LZMA_DEC_OPT`, so `src/C/LzmaDec.c` always builds its own `static` C decoder — but its debug info made `ld`
  print 59 "could not associate debug note to atom …" warnings on every clean build of Yomi.
- `Package.swift`: upstream's, minus the test targets, plus `-Wno-deprecated-declarations` on `libplzma`: as a local
  package Xcode shows its warnings, and `src/plzma_path.cpp` / `plzma_path_utils.cpp` call the deprecated `readdir_r`
  (directory listing for the encoder side — Yomi only decodes single archives). Code itself unchanged.
- To update: copy the same folders from a newer tag, delete `src/Asm/` again, re-run `scripts/build-licenses.sh`,
  re-test CB7 the S175 way (ROADMAP S175: py7zr-made LZMA, LZMA2, PPMd, Copy, AES archives byte-identical).
