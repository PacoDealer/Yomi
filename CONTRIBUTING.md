# Contributing to Yomi

Thanks for helping. Yomi is a small project run by one developer, so short and specific reports help the most.

## Reporting a bug

[Open an issue](https://github.com/PacoDealer/Yomi/issues/new/choose) with the bug form. Please include:

- the Yomi build number (**More → About**) and your iOS version
- what you did, what you expected, and what happened instead
- a screenshot or screen recording if it's visual

If the problem is with one source (a site won't load, chapters are missing), check that website in Safari first —
sources are run by their own projects, not by Yomi.

Security problems: please don't open a public issue — see [SECURITY.md](SECURITY.md).

## Suggesting a feature

Use the feature request form. Say what you're trying to do, not only the button you'd like — there may be a simpler
way. Fixing bugs in everyday reading comes before new features.

## Pull requests

- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Keep each pull request to one change, and describe how you tested it (simulator or device, iOS version).
- Run the test suites before sending: `scripts/test-all.sh`.
- Code is Swift + SwiftUI, iOS 26 or later only. Follow the style of the file you're editing.
- Pull requests that add scrapers or site plugins to this repository won't be merged: Yomi ships no sources.
  Publish extensions in your own repository instead — see [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

### Building

1. Open `Yomi.xcodeproj` in Xcode 26.
2. Copy `Yomi/Config/AppSecrets.swift.template` to `Yomi/Config/AppSecrets.swift` (git-ignored). The MyAnimeList id
   is needed to compile; the others can stay empty.
3. Build the `Yomi` scheme for an iPhone simulator.

## Licence

By contributing, you agree that your contribution is licensed under the [GNU GPL v3](LICENSE) with the two
additional permissions in [NOTICE](NOTICE) (UnRAR, and app stores), like the rest of Yomi — so it can ship in the
App Store build.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
