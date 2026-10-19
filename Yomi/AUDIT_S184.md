# Yomi — overnight audit (S184, 2026-10-18 → 19)

Martin asked (going to sleep): audit everything done so far, check the roadmap for what's missing, take nothing for
granted, research what we didn't consider — plus GitHub organisation (how similar projects do it, README, branch
protection), donations, and whether the Yomi catalog can be open on GitHub under Apple's rules. No questions asked
overnight; everything below that needs a decision is in §2, in the order I'd take them.

Verified = I ran it or read it tonight. Phone: nothing installed or checked (it was locked/away).

---

## 1. Fixed tonight (all verified, all pushed)

| # | What was wrong | Why it mattered | Fix | Verified |
|---|---|---|---|---|
| 1 | **Privacy manifest used the wrong UserDefaults reason.** Yomi shares settings with the widget through the App Group, but declared only `CA92.1`, which Apple's text says "does not permit … writing information that can be accessed by other apps" | Apple emails ITMS-91053 / can reject for wrong reasons | Added `1C8F.1` (App Group). Read live from Apple's docs JSON | Build, file in bundle |
| 2 | **Widget had no privacy manifest** (its own executable, reads App Group defaults) | Apple: "each executable … needs to include a privacy manifest" | `YomiWidget/PrivacyInfo.xcprivacy` | Inside `YomiWidget.appex` |
| 3 | **`OpenJDKRuntime.framework` had no privacy manifest.** `nm -u` shows `stat`/`fstat`/`lstat` (file timestamp), `statfs`/`statvfs` (disk space), `mach_absolute_time` (boot time) | Same rule; this framework ships in every TestFlight build | `embed-runtime.sh` copies `scripts/keiyoushi/OpenJDKRuntime-PrivacyInfo.xcprivacy` in before signing | Release **device** build: file inside the framework, `codesign --verify --deep --strict` OK |
| 4 | **Disk-space reason was wrong** (`85F4.1` = *display* free space). Yomi checks free space before downloading (S162 low-storage pause) and never shows it | Wrong reason = mismatch | `E174.1` | — |
| 5 | **The internal docs shipped inside the app.** `Yomi/` is a synchronized folder, so ROADMAP, RESEARCH, KNOWN_ISSUES, **APP_STORE_LISTING** (App Review strategy, the 18+ switch discussion), HISTORY, METODOLOGIA… were copied into every build — **build 515 on TestFlight has them**. Also `AppSecrets.swift.template` | Anyone can unzip an .ipa; App Review can look inside it | Target membership exceptions | Clean build: bundle holds only licences, reader fonts, `yomi-js-libs.js`, manifests |
| 6 | **Unused Space Grotesk / Space Mono fonts** (pre-"calm" design) were bundled + registered, with no licence row (OFL needs one) | 332 KB + licence gap | Excluded, `UIAppFonts` removed | Clean build, 0 warnings |
| 7 | **13 English strings in Spanish mode:** Safe Mode passcode prompts (3), Face ID reason "Turn on App Lock", low-storage pause, "Could not load any catalog…", "Reading · 40 %", "Novel · …", "Queued · …", Tachiyomi-import error, read-aloud "Couldn't load …", Keiyoushi HTTP error, "Unknown error" | They are `String` values shown later, so Xcode never extracted them; the S181 finder skipped `case .x: "…"` lines and text with digits or "·" | `String(localized:)` + `scripts/localization/es-8.json`; finder fixed | Catalog 1028/1028 in Spanish; compiled `es.lproj` checked. **Not seen on screen** |
| 8 | **A failed DB migration loses the library.** `YomiApp` calls `fatalError` if migration fails — Yomi then crashes at every launch | One bad migration on your phone = no way back except reinstall | Before pending migrations, the DB is copied to `Application Support/yomi-before-migration.db` (never blocks launch) | Sim: rolled DB back to v29 → launch → copy at v29 (169 titles), live DB at v30, 169 titles; normal launch makes no copy |
| 9 | **No single test command, no CI.** 7 test suites, each run by hand | Regressions only found if someone remembers | `scripts/test-all.sh` + GitHub Actions **Tests** (macos-26, every push/PR) + `scripts/check-bundle-docs.py` (fails if a new `.md` would ship) | All 7 suites + guard pass locally; **CI run green** on GitHub |
| 10 | **No issue templates** | Bug reports arrive without version/iOS/source type | `.github/ISSUE_TEMPLATE` (bug form, feature form, no blank issues, link to support page) — modelled on Aidoku/Paperback/Mihon | YAML parses |
| 11 | **Firebase folder (live plugins + website) had no version control** — only hand-made backup copies | One bad edit to a live plugin can't be undone | Local git repo, first commit = today's live state. **No remote** (nothing published) | `git log` |
| 12 | **Doc drift** | Docs are what the next session trusts | CLAUDE.md 268 → 150 lines (its own limit is ~200; old block archived verbatim in HISTORY.md); `rules/grdb.md` said next migration `v29_` (it's `v31_`); App Store checklist said "Support URL ❌" (live since S154) and "privacy manifest: UserDefaults only"; "phone on iOS 18.6.2" note; strategic table (Keiyoushi "S41 Suwayomi", "15 plugins", OPDS "not yet"); README import steps (old button name, no Tachimanga, no CBR/CB7); `embed-runtime.sh` comment said Personal only | Fixed | Read back |

| 13 | **Novel reader ran JavaScript from chapter HTML.** Chapters are set with `innerHTML` (stops `<script>`), but inline handlers like `<img onerror=…>` still ran and could post the reader's own messages (mark a chapter complete, load the next) | A hostile or hacked site could mark chapters read or loop loads | Content-Security-Policy with a per-page nonce: only the reader's script runs; Swift's `evaluateJavaScript` is unaffected | macOS WKWebView experiment: with CSP the handler is blocked and the reader script + evaluateJavaScript work; **control without CSP: handler ran**. ReaderUITests (see ROADMAP) |
| 14 | **"Remove from Library" race** (all 4 places: manga/novel × grid/list): the removal ran in a detached task while a separate task reloaded the library at once, so the reload could read before the write and the title stayed on screen; novels were saved whole-row (`upsert`, against the project's GRDB rule) | Title "comes back" until the next reload; stale whole-row write | Write first, then reload; novels use the column-only `NovelQueries.setInLibrary` | Build 0 warnings; scan found no other site with the pattern |
| 15 | Doc drift in TACHIMANGA_PARITY: OCR (S173), pinned sources / source filter / per-category sort (S170 G) still listed as missing | — | Struck + S184 re-check of Tachimanga v5.1/v5.2 preview (new there: "Delete Download" toolbar action — Yomi lacks it; Comick tracker) | Changelog read live |

Health checks that **passed** tonight: simulator + Release device builds 0 warnings; ReaderUITests 13/13 +
PerfUITests 3/3, and ReaderUITests 13/13 again on the final (CSP) build; all 7 suites; CI; git history has no secrets (`AppSecrets.swift` never committed,
no hard-coded client ids, no Google keys); live privacy + support pages accurate; Pulse logs only in Debug; Info.plist
matches the features (BG refresh id, `yomi://`, CBZ/CBR/CB7/EPUB types, usage strings).

---

## 2. Decisions for you (in the order I'd take them)

### A. The public repo and the Yomi catalog — **the biggest risk I found**
Evidence (read tonight):
- **March 2026: FAKKU's DMCA notice hit `keiyoushi/extensions-source`, `keiyoushi/extensions` and an archive repo on
  GitHub**; six sources were removed for good and the archive repo was erased
  ([GitHub DMCA record](https://github.com/github/dmca/blob/master/2026/03/2026-03-23-fakku.md),
  [keiyoushi #14260](https://github.com/keiyoushi/extensions-source/issues/14260)). Rights holders do go after
  scraper code on GitHub, not only the sites.
- `PacoDealer/Yomi` is **public** and contains: `scripts/plugins-src/*.ts` (6 scrapers), `scripts/catalog-output/index.json`
  (lists MangaDex, Asura… with your Firebase URLs), and the README's table of repository links (LNReader, Keiyoushi,
  Yomi Catalog) — the open #170 legal question. The repo, the Firebase catalog and the App Store developer account are
  all the same identity.
- Apple doesn't review GitHub, but **5.2.2** ("If your app uses, accesses … content from a third-party service, ensure
  you are specifically permitted") is weakest exactly where *you* wrote the scrapers (the Yomi Catalog), and App
  Review can follow your support/marketing pages. **4.7**: you are "responsible for all such software offered in your
  app" — Yomi offers none in-app (user pastes a link), which is the right shape; keep it.

How similar projects do it:
| Project | App code | Sources live | Repo shows |
|---|---|---|---|
| **Paperback** (App Store, closed source) | private | third-party repos | public repo = **README + issues + releases only** |
| Aidoku (GPL, not on App Store) | public | separate community repos | screenshots, features, install, Discord, CLA |
| Mihon (Apache) | public | none official — Keiyoushi is a separate project | features, Patreon, templates, CI |
| Suwatte (GPL) | public | separate runners | Ko-fi/Patreon |
| Keiyoushi | — | one repo, `repo` branch hosts `index.pb` | minimal |

Nobody who ships on the App Store keeps their scrapers in the app's repo.

Options:
1. **Now (cheap):** remove `scripts/plugins-src/` and `scripts/catalog-output/` from the repo (keep them in the
   Firebase git), and drop the URL table from the README (keep "paste a repository link"). Old commits still hold them
   — removing them from history needs a force-push (your call; it breaks nothing for a solo repo but is irreversible
   for anyone who cloned).
2. **Before App Store submission:** Paperback's shape — make the app repo private, keep a public `Yomi` repo with
   README, issues, releases. Constraint: `PageBorders.swift` (MPL-2.0) and the M-Extension-Server patch must stay
   public — the licences screen links to them in this repo — so move those two files to a small public repo first and
   update the two links in `Yomi/Resources/Licenses/`.
3. **Longer term:** move the Yomi Catalog away from your developer identity, or retire your own manga scrapers and rely
   on LNReader/Keiyoushi repos you don't author (WeTried is the one you use daily — it could be offered upstream to
   LNReader).

My pick: 1 now, 2 before submission. I did none of it — it publishes/deletes public content.

### B. Ship a new TestFlight build soon
515 contains the internal docs (#5) and lacks the widget + JVM manifests (#2–3). Next build = these fixes + S182/S183
work. Needs your "upload build N now".

### C. GitHub repo settings — ready-to-run (each changes your account, so I didn't)
```bash
gh repo edit PacoDealer/Yomi --description "Manga, manhwa and light-novel reader for iPhone — your own files plus sources you add. No ads, no account." --homepage "https://yomi-reader.web.app" --add-topic ios --add-topic swift --add-topic swiftui --add-topic manga-reader --add-topic light-novel --add-topic epub --add-topic comic-reader
```
```bash
gh api -X POST repos/PacoDealer/Yomi/rulesets --input - <<'EOF'
{"name":"Protect main","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}
EOF
```
(blocks deleting `main` and force-pushes; normal pushes — including mine — keep working. Requiring PRs or green CI
would block the direct pushes our sessions do; not recommended for a solo repo.)
```bash
gh api -X PATCH repos/PacoDealer/Yomi -f 'security_and_analysis[secret_scanning][status]=enabled' -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
```
```bash
gh api -X PUT repos/PacoDealer/Yomi/vulnerability-alerts
```
```bash
git push origin --delete worktree-agency-agents-docs
```
(stale remote branch). Also worth adding by hand: 3–4 screenshots at the top of the README (Aidoku does this) and a
social-preview image (Settings → General).

### D. Donations
- **Outside the app (allowed anywhere):** **GitHub Sponsors supports Argentina and takes 0 % from personal sponsors**
  ([GitHub docs](https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors)) →
  then a `.github/FUNDING.yml` adds the "Sponsor" button (Mihon, Aidoku, Suwatte, Paperback all have one; Ko-fi works too).
- **Inside the app:** only a **consumable In-App Purchase tip jar** (3.1.1, read live S183). No Ko-fi/Sponsors link or
  button in the app outside the US storefront (3.1.1(a)). Before selling anything: Paid Apps Agreement + bank/tax in
  App Store Connect, and enrol in the **App Store Small Business Program (15 % instead of 30 %)** — it is not automatic
  ([overview](https://adapty.io/blog/app-store-small-business-program/); confirm on Apple's page when enrolling).
- Small catch: if FUNDING.yml exists, the repo pages the app's licence notes point to show a Sponsor button. The links
  are plain text in the licence files, so the risk is tiny; I'd still point them at a non-repo page if you go with A2.

### E. 18+ switch → Apple's Declared Age Range API (guideline 4.7.5)
4.7.5 (live text): plug-in apps must "use an age restriction mechanism based on verified or declared age". S154
flagged this as a known risk. New since then: **`DeclaredAgeRange`** (iOS 26, `AgeRangeService`, entitlement
`com.apple.developer.declared-age-range`) is exactly that mechanism. Proposal: turning on "Show 18+" asks for the age
range (gate 18); declined/under 18 → stays off. New entitlement + small UI change — your call (feature rule S144).

### F. Smaller ones
1. **DB failure screen:** the snapshot (#8) keeps the data, but Yomi still crashes at launch if a migration fails. A
   tiny "Yomi couldn't open your library — Share database / Try again" screen instead of `fatalError`.
2. **Dependencies:** Kingfisher 8.9.0 → **8.14.0** (5 releases), GRDB 7.11.0 → 7.11.1. Reader pages depend on
   Kingfisher's cache keys (S183) → update + ReaderUITests + a phone check, not overnight.
3. **SwiftLint** reports ~2,000 style warnings because its rules fight the house style (aligned colons etc.) — tune
   `.swiftlint.yml` to the real style or drop it; as is it's noise.
4. **Big files:** MangaDetailView 2,097 lines, JSBridge 1,819, TextReaderView 1,505, NovelDetailView 1,499 — candidates
   for #106-style pure-move splits.
5. **App Store checklist still open:** age rating, description, screenshots, ATS review note, France encryption
   (all ROADMAP checklist).

---

### G. Catalog plugins, live tonight (plugin code run in Node with the app's cheerio shim; MangaDex skipped per rule)
- **Work end to end** (list → details → chapter): **Asura Scans** (20 → 32 pages), **WeTried** (889 ch), **NovelFire**
  (3,219 ch), **NovelBin** (1,039 ch).
- **Behind bot protection** (403 Cloudflare, or BoxNovel's JS "Redirecting…" page): AquaManga's list, BabelNovel,
  BoxNovel, FreeWebNovel, NovelFull, NovelHall, ReadWN, Royal Road, Scribble Hub — plain HTTP can't judge them; the
  app's Cloudflare WebView may get through. Worth one in-app pass (Browse → each source) before listing them anywhere.
- **Unreachable from this network:** LightNovelPub (`lightnovelpub.vip`) and MTLNovel — DNS resolves, connection fails
  (could be this network; memory notes campus/airport blocks). If dead, retire them from `index.json`.

### H. TestFlight crash + hang reports
Xcode's MCP can read App Store Connect crash/hang data for builds 493–515 (`GetTopCrashIssues`), but it asks you to
approve the agent in Xcode first (it refused overnight). Worth a look when you're at the Mac: open the project in
Xcode and say "check TestFlight crashes".

## 3. Competitors, checked tonight
- **Madomi** (App Store, Mihon sources, translation) remains the closest App Store rival (S122/S159 research).
- **Aidoku**: still not on the App Store (TestFlight/AltStore), v0.8.x.
- **Paperback**: 0.9 supporter-only TestFlight per third-party reports (unconfirmed officially).
- **"LNReader for iOS"** (`lqSky7/lnreader-ios`, Swift port): 1 star, no releases — not a real competitor yet.
- Yomi's edge stands: manga **and** light novels with plugins, on-device Keiyoushi, Tachimanga/Mihon import, read
  aloud, Spanish. Where the others are ahead on GitHub: screenshots in the README, a website with install/FAQ (you have
  one), Discord/community, translations platform (Aidoku: Weblate), FUNDING button.

## 4. Proposed README (draft — not applied, depends on A)
```
# Yomi
A calm, fast reader for manga, manhwa, manhua and light novels on iPhone. No ads, no account, no tracking.

[3–4 screenshots: Library · manga reader · novel reader · read aloud]

## What it does
- Reads your own files: CBZ, CBR, CB7, ZIP, EPUB
- Extensions you add by link (Yomi includes none)
- Manga reader: paged, webtoon, continuous; crop borders, two-page spreads
- Novel reader: themes, fonts, read aloud with sentence highlight, term replacement
- Library sync with iCloud, backups, Mihon / Tachiyomi / Tachimanga import
- English and Spanish

## Get it
TestFlight: <public link> · App Store: soon

## Help
https://yomi-reader.web.app/support · Bugs: open an issue (use the form)

## License
All rights reserved (see LICENSE) — except the files listed there.
```

## 5. What I could not check
- Anything on the phone (nothing installed tonight).
- Whether Apple already emailed ITMS-91053 warnings for builds 493–515 (the connected Gmail isn't the App Store
  Connect address).
- Spanish fixes on screen (bundle-verified only).
- GitHub settings, README, Firebase deploys: not changed — they publish or change your accounts.
