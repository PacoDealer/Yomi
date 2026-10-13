# App Store listing — draft for Martin's approval (S154, 2026-10-12)

Status: **DRAFT. Nothing here has been typed into App Store Connect.** Every listing field there is still empty
(read 2026-10-12: Name is set, Subtitle / Description / Keywords / Support URL / Category / Content Rights / Age
Ratings are blank).

Lines marked **[CHECK]** make a claim that has not been confirmed on a real device or needs Martin's decision.

---

## 1. Text fields (copy-paste ready)

### Name (30 max) — already set
```
Yomi Manga and Novels Reader
```

### Subtitle (30 max)
```
Webtoon, comics, EPUB, offline
```
The name already carries "manga", "novels", "reader"; Apple indexes name + subtitle + keywords together, so the
subtitle adds new words instead of repeating them. (How Apple weighs these fields is common ASO advice, not something
Apple documents — not verified.)

### Promotional text (170 max — can be changed any time without a new version)
```
A calm reader for manga, webtoons, light novels and books. Your own files, your own library, no ads and no account.
```

### Description (4,000 max, plain text)
```
Yomi is a calm, fast reader for manga, manhwa, webtoons and light novels on iPhone. No ads, no account, no tracking.

READ YOUR OWN FILES
• Open CBZ, ZIP and EPUB files, or link a folder from the Files app
• Connect an OPDS catalog on a server you run or are allowed to use
• Download chapters and read offline, on Wi-Fi only if you prefer

A READER FOR COMICS
• Right-to-left, left-to-right, vertical and long-strip (webtoon) modes
• Pages slide under your finger; pinch to zoom exactly where you pinch
• Picks up on the page where you stopped

A READER FOR NOVELS
• Scroll, or turn pages like a book
• Light, Sepia, Warm, Dark and true black themes
• Fonts chosen for long reading, including one designed for dyslexia
• Size, spacing, margins and hyphenation, all adjustable
• Read aloud with the sentence highlighted as it is spoken, speed control and a sleep timer

YOUR LIBRARY
• Categories, history and a list of new chapters
• A Continue shelf that takes you straight back into the chapter
• Reading time and chapter statistics
• App Lock with Face ID, and an Incognito mode that saves no history

YOURS TO KEEP
• Optional iCloud sync, stored in your own private iCloud
• Export a backup file and restore it whenever you want
• Import a library backup in the .tachibk format

OPTIONAL EXTENSIONS
Yomi can be extended with extensions from repositories you add by pasting their link. None are included and none are suggested.

Yomi does not include a content catalog and does not provide access to content. You are responsible for the files, servers and extensions you choose to use, and for having the right to read what you open.

Questions or problems: yomiappreader@gmail.com
```

Claims to confirm before this goes live:
- iCloud sync stays in (Martin, S154: "iCloud sync will work"). The two-device test is still worth doing before release.
- **[CHECK] Read aloud** — rebuilt in S143, only checked in the simulator.
- iPad removed (Martin, S154): the project is iPhone-only now (`TARGETED_DEVICE_FAMILY = 1`), so no iPad screenshots.
  iPad — and maybe iPhone Duo — come as a later update. An iPhone-only app can still be opened on an iPad in a
  phone-sized window, and App Review may try it there.
- Not in the draft until tested (Martin agreed, S154): trackers (MyAnimeList, AniList, …) and the Home Screen widget —
  both need a check on a TestFlight build; add a line for each once it works.

### Keywords (100 bytes max, comma-separated, no spaces)
```
manhwa,manhua,cbz,zip,light,web,ebook,book,opds,library,read aloud,tts,themes,sync,backup
```
Rules read from Apple's help page (2026-10-12): no app name or company name repeated, **"Names of other apps or
companies aren't allowed"**. So no Tachiyomi, Mihon, Kindle, Komga, MangaDex.

### Category
Primary **Books**, secondary **Entertainment** — same as Suwatte, Eclipse, Panels, ArcReader.

### Copyright
```
2026 Martín Gamberg
```
(Apple adds the © itself.) **[CHECK]** exact legal name as on the developer account.

### Support URL / Marketing URL / Privacy Policy URL
```
Support:  https://yomi-reader.web.app/support
Privacy:  https://yomi-reader.web.app/privacy
Marketing: (leave empty)
```
**Decided S154:** a separate, neutral site `yomi-reader` in the same Firebase project — home, support and privacy
only, files in `Firebase/site/`. **Not created or deployed yet** (waiting for Martin's go). The old
`yomi-plugins.web.app/privacy` stays up: builds already on TestFlight link to it.

---

## 2. Age rating — proposed answers

The form (opened and read in App Store Connect 2026-10-12, then cancelled — nothing saved) has 7 steps. Result with
the answers below: **calculated 16+, then override to 18+.**

| Step | Question | Answer | Why |
|---|---|---|---|
| 1 In-App Controls | Parental Controls | No | Yomi has none |
| 1 | Age Assurance | No | Yomi does not check age |
| 1 Capabilities | **Unrestricted Web Access** | **Yes** | The Cloudflare sheet (`CFBypassView`) has an address bar — a user can open any web page. Apple's definition: "Users can navigate to any webpage within the app". This alone gives 16+. Tachimanga, Paperback, Lipex, Madomi, ArcReader all declare it |
| 1 | User-Generated Content | No | Nothing users make is distributed to other users |
| 1 | Social Media / Disabled under 13 | No | |
| 1 | Messaging and Chat | No | |
| 1 | Advertising | No | |
| 2 Mature Themes | Profanity or Crude Humor | Frequent | What a manga/novel reader can show |
| 2 | Horror/Fear Themes | Frequent | |
| 2 | Alcohol, Tobacco, Drug Use or References | Infrequent | |
| 3 Medical | Medical or Treatment Information | None | |
| 3 | Health or Wellness Topics | None | |
| 4 Sexuality | Mature or Suggestive Themes | Frequent | |
| 4 | Sexual Content or Nudity | Infrequent | |
| 4 | **Graphic Sexual Content and Nudity** | **None** | Any other answer makes the app **Unrated = cannot be on the App Store** |
| 5 Violence | Cartoon or Fantasy Violence | Frequent | |
| 5 | Realistic Violence | Infrequent | |
| 5 | **Prolonged Graphic or Sadistic Realistic Violence** | **None** | Same: any other answer = Unrated |
| 5 | Guns or Other Weapons | Infrequent | |
| 6 Chance | Gambling / Loot Boxes | No | |
| 6 | Simulated Gambling / Contests | None | |
| 7 Override | Age Categories and Override | **Override to Higher Age Rating → 18+** | Keeps the plan in ROADMAP (18+). Apple: the store shows the override, the content lines still show the answers above |
| 7 | Age Suitability URL | empty | Optional |

How the others answered (US store, 2026-10-12): Tachimanga, Paperback, Lipex, Madomi, ArcReader declare only
"Unrestricted Web Access" (17+ in the old scale). Eclipse declares the content lines too (frequent fantasy violence,
profanity, mature themes; mild sexual content) — 17+. Suwatte declares everything "mild" — 12+. The table above is
closest to Eclipse, and stricter.

Also on that page — **Content Rights** (two choices, read from the dialog):
- "Yes, it contains, shows, or accesses third-party content, and I have the necessary rights"
- "No, it does not contain, show, or access third-party content"

**Decided S154: answer Yes.** Apple's wording is "contain, show, or access" — Yomi accesses whatever the user points it
at, and the App Review notes say so. "No" would contradict those notes, and guideline 2.3.1(b) treats dishonesty as
grounds for removal from the program; a wrong "Yes" at worst brings a question. What "Yes" costs: Apple can ask for
proof (5.2.2, "Authorization must be provided upon request"). The answer then: the app ships no content; files,
servers and extensions are supplied by the user. Searched and not found: any Apple statement on this question for
reader or browser apps, or what comparable apps answered — the only guidance is a non-staff forum opinion ("the
question isn't conditional… answer yes").

---

## 3. What the other apps do — and where Yomi's listing can be better

Source: Apple's public search + review feeds, US store, 2026-10-12. Reviews are the 50 most recent per app — a small,
loud sample.

| App | Rating | Listing | Support URL |
|---|---|---|---|
| Tachimanga | 4.76 (5,441) | 247 characters. Files + Komga only, no word about extensions | Site with guides; no contact address at all |
| Paperback | 4.29 (640) | 129 characters, "scripting API to extend the app" | None |
| Eclipse | 4.45 (11) | 621 characters, opens with what is free. Files + Komga, no word about repos | One page: e-mail + "reply in 1–2 days" |
| Lipex | 5.0 (9) | 395 characters, "import EPUB" | A subreddit; policies are Google Docs |
| Suwatte | 5.0 (6) | 1,047 characters, 3 headed sections, names "optional source plugins from lists you trust" + a no-content sentence | Site with guides; no e-mail |
| ArcReader | 4.92 (50) | 3,899 characters, names source sites, genre keyword list | Site |
| Panels | 4.79 (12,512) | 3,042 characters, feature list, "your own files" | Site |

**Doing well**
- Suwatte: honest and short — says plugins exist, says the app has no content. Uses Pepper & Carrot (a free-licence
  comic) in its screenshots, with credit.
- Eclipse: first sentence is the reason to pick it (what is free). Support page is one e-mail and a promised reply
  time.
- Panels / Readest: headed sections a person can scan.

**Doing wrong**
- Tachimanga, Paperback, Lipex: the listing describes a different app from the one people use. Reviews show the
  cost — "initially I didn't understand how this app worked", "The app starts off empty", "setup instructions
  terrible", "requires Discord". Paperback's 1★ reviews are mostly setup and no support.
- Paperback / Tachimanga: no way to contact anyone. Apple's own rule for the Support URL: it "must lead to actual
  contact information".
- ArcReader: names the sites it reads from and lists genres as keywords — the opposite risk (5.2.2, 2.3.7).
- Tachimanga: top complaints are paywalls on basic features and slowness, neither of which the listing mentions.

**So Yomi's listing**
1. Says in one plain paragraph that extensions exist and nothing is included — users are not surprised by an empty
   app, and it matches the review notes.
2. Leads with what is true on first launch: your own files work with no setup.
3. Says "no ads, no account, no tracking" in the first line — the thing reviews praise most and Yomi can prove (the
   privacy page says the same).
4. Has a support page with a real e-mail, a reply time, and a short FAQ — better than every app in the table.
5. Names no other app and no source site anywhere.

---

## 4. Problems found while drafting (need a decision before submitting)

1. **The 18+ switch — DECIDED by Martin (S154), done in code.** It stays, hidden: removed from the Extensions menu and
   from Settings → Privacy; it now lives only in Repositories (Settings → Repositories, or Browse → ⋯ →
   Repositories), off by default. Remaining risk, stated plainly: guideline 1.2 says such content may be shown only
   when turned on "via your website", and 4.7.5 asks for a declared-age gate — an in-app switch, even a buried one, is
   what Apple objected to in 2016. If App Review raises it, the fallback is to remove the switch.
2. **Support address — DECIDED S154: separate site `yomi-reader.web.app`** (see §1). Why not the alternatives: staying on
   `yomi-plugins.web.app` keeps the support page one URL from a list of 16 source plugins on a host named "plugins";
   GitHub Pages would sit next to a README that lists repository links. A second site in the same Firebase project
   is free and takes two commands. After it is live: point the in-app Privacy Policy link at it in the next build.
3. **Home page — done in the same step:** `Firebase/site/index.html` (plain page: what Yomi is, support, privacy,
   contact). The placeholder on the old plugin host is left as it is.
4. **Screenshots** — not drafted this session. Proposal: use only free-licence content (Pepper & Carrot, CC BY, with
   credit; a Project Gutenberg or Standard Ebooks novel), six screens: library, comic reader, novel reader with the
   text panel, read aloud, downloads/offline, sync + backup. Guideline 2.3.8: screenshots must suit a 4+ audience
   whatever the app's rating. Required sizes not re-checked today.
5. **France** stays out of availability until the encryption declaration is done (ROADMAP checklist).
6. **Minimum iOS is 26.2** — only people on the newest system can install. Worth knowing; not a listing field.

---

## 5. Notes for App Review (4,000 bytes max) — draft, updated from the TestFlight notes

```
Yomi is a reader app for comics (CBZ/ZIP) and books (EPUB). It contains no content and needs no sign-in.

HOW TO TEST WITH REAL CONTENT
1. Download any public-domain EPUB (for example from Project Gutenberg) to the Files app.
2. In Yomi: Browse > On This iPhone > Local Files > Import, and choose the file.
3. Open it from Library. Reader settings are behind a tap in the middle of the screen.

OPTIONAL FEATURES
- OPDS: the user can enter the address of an OPDS catalog on a server they run or are allowed to use.
- Extensions: the user can paste the link of a repository and add extensions from it (JavaScript, and Mihon-format extensions run by an embedded OpenJDK runtime). No repository or extension is included in the app, and the app does not link to or suggest any. Extensions do not change the purpose of the app: they are additional places the reader can list and open titles from.
- A switch in Repositories (off by default) decides whether extensions that a repository marks as 18+ are listed.
- A web sheet with an address bar appears when a site asks the user to pass a browser check. Because of it we declared "Unrestricted Web Access".
- iCloud sync (off by default) stores the user's library in their private CloudKit database.

NETWORK
- NSAllowsArbitraryLoads is set because users connect to their own self-hosted servers (OPDS), which are often plain HTTP on a home network and whose addresses cannot be known in advance.
- Encryption: standard TLS only (from the OS and from the embedded OpenJDK runtime).

No account, no ads, no analytics, no in-app purchases.
Contact: yomiappreader@gmail.com
```
**[CHECK]** the three test steps were never run with a real Gutenberg file (also open from S152).

---

## 6. Sources (all read 2026-10-12)

- App Review Guidelines, live text: 1.1.4, 1.2, 1.5, 2.3–2.3.10, 4.7–4.7.5, 5.2.2 — developer.apple.com/app-store/review/guidelines/
- Age ratings values and definitions — developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/
- Set an app age rating — developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- Platform version information (field limits, Support URL rule) — developer.apple.com/help/app-store-connect/reference/platform-version-information/
- App Store Connect, Yomi record: version page, App Information, age rating dialog step 1, Content Rights dialog
- Competitor listings and reviews: itunes.apple.com search API + customer-review feeds (US)
- Competitor support pages: tachimanga.app, suwatte.mantton.com, madarame-bk.github.io/eclipse-legal
- Content Rights answer: developer.apple.com/forums/thread/654320 (a forum reply, not Apple policy)
- 2016 NSFW-switch removals: loopinsight.com/2016/04/12/official-reddit-app-ships-apple-pulls-3rd-party-reddit-apps-to-remove-nsfw-toggle

Not verified: what Apple weighs in search; required screenshot sizes; what comparable apps answered for Content
Rights; whether any reader app was rejected over an in-app 18+ switch after 2016.
