# marginalia

A no-stop English reader. Three articles are always waiting; you read one, hear
one, or both, and what you have read stays where it is. Nothing is spent until
you tap Write it.

The name is the thing itself: marginalia are the notes a reader leaves in the
margin. This app is a margin that answers back.

> **Generation is remote, not local.** There is no local model in this app — no
> bundled `gguf`, no ONNX, nothing that writes text on the device. Every article
> is produced by a remote API over HTTPS (DeepSeek, MiMo or OpenAI), which is why
> a new article needs a key and a connection and is the only thing here that costs
> money. What is local: the bundled samples, the bundled dictionary, the SQLite
> database, and the word-marking. With no key you can read, hear and look words
> up in airplane mode for $0.00 — you just cannot have a new article written.

## What it does

- **Read.** An article is a block of prose with every word tappable. Tap a word
  and its meaning appears in English, with the Chinese one tap further. Long-press
  a line to hear it.
- **Listen.** The second tab shows one sentence at a time, very large, and reads
  the whole article aloud with the transport on the lock screen.
- **The queue is three, always.** Reading counts and never removes anything —
  there is no "done" state anywhere in the data model, and an article you have
  read stays where it is so you can go back to it. A card leaves only when you
  say so, and what takes its place is a free *plan*, not a paid article.
- **The words come back.** Words you meet and words you star gain weight; weight
  decays with a seven-day half-life and steers what the next article is about.

## Running it

Point `ANDROID_HOME` at your SDK and let Gradle find the JDK — both are pinned
in `android/gradle.properties`, so there is nothing to export by hand:

```bash
cd Marginalia
flutter pub get
flutter run
```

`docs/BUILD.md` covers the whole toolchain: the SDK layout, why `avdmanager`
needs a JDK 8 while the build needs 21, driving the emulator with `adb`, and the
release checklist.

### It works with no keys at all

This is a hard requirement, not a nicety. A fresh install with no API key reads
bundled sample articles, looks words up in a bundled 392,695-entry dictionary,
and speaks with the phone's own TTS engine — offline, in airplane mode, for
$0.00. Keys add a better voice and a cheaper writer; they are never required.

## The keys

All of them are optional and all of them live in the Android Keystore, never on
a server — there is no server.

| Key | What it buys | Where it is configured |
|---|---|---|
| Writer | Articles written for you, on a subject you name or one the writer picks | Settings → Who writes |
| Voice | MiMo reads articles aloud in a recorded voice | Settings → Voice |
| News | The writer may read a Zhihu Daily story before writing | Settings → Who writes → Sources |
| Search | The writer may look a fact up on the web | Settings → Who writes → Sources |

The first two are what "set up" means. The last two are enhancements: with
neither, the writer still writes, in one call. With one, it can research first —
which costs a few more calls, and the card says so before you tap it.

**There is no topic setting.** What to write about is either a sentence you
type (saved as an *instruction*, reusable from any card) or nothing at all, in
which case the writer chooses. Every article then carries the keywords the
writer produced, so a card tells you what it is about without you having to
maintain a list of subjects forever.

Nothing is ever written without you tapping **Write it** on a planned card, and
that card states the cost before you tap.

## Using it

`docs/USER_GUIDE.md` is the walkthrough for somebody who has never used the app
and does not want to read about architecture — where the keys go, what each
button does, what costs money and what does not. Written in Chinese, because
the reader this app is for is a Chinese speaker learning English.

## Building it

`docs/BUILD.md` is the full manual — SDK paths, the JDK, the proxy, how to drive
the emulator with adb, and the release checklist. The short version:

```bash
export ANDROID_HOME="/path/to/Android/sdk"
flutter analyze --no-pub && dart tool/check_invariants.dart && dart tool/check_agent.dart
flutter build apk --release
```

`docs/BUILD.md` has the machine-specific parts — the exact SDK layout this was
developed against, the JDK, the proxy — as reference rather than as something to
copy verbatim.

## Layout

```
lib/
  main.dart              the shell: state, boot, and every screen's wiring
  app/bottom_bar.dart    the five destinations
  core/design/tokens.dart   colour, type, spacing, motion — declared once
  core/widgets/          Hairline, sheets, buttons, paper texture
  data/                  drift database, keystore, dictionary, audio, HTTP
  domain/                the pure models and the five invariants
  features/              one directory per screen
tool/check_invariants.dart   runs the invariants as a program, not a test
```

`docs/ARCHITECTURE.md` explains the shape and why it is that shape.
`docs/STATUS.md` states what is finished and what is not — read it before
assuming a feature exists.

The design bible is `../Marginalia-Prototype/docs/DESIGN.md`. It is the source of
truth for every visual and behavioural decision here; when this code and that
document disagree, the document is right and this code is a bug.

## Requirements

| | |
|---|---|
| Flutter | 3.44 or newer, stable channel |
| Dart | the one that ships with it |
| JDK | 17 for the Gradle build (21 is pinned in `gradle.properties`) |
| Android SDK | platform 35, build-tools 35 |
| Target | Android 8.0 (API 26) and up |

Nothing else. No server, no database to install, no account to create.

```bash
cd Marginalia
flutter pub get
flutter analyze --no-pub
flutter test
dart tool/check_invariants.dart
dart tool/check_agent.dart
```

## License

GNU General Public License v3.0. The full text is in [`../LICENSE`](../LICENSE);
the short version is that you may use, read, modify and redistribute this code,
including in something you charge money for, but anything you build on it has to
carry the same license and has to ship its source. The bundled fonts are covered
by their own licences (see below) and are not part of that grant.

### Third-party assets

The app bundles three things it does not own. All of them are redistributable,
and all of them are compatible with GPLv3, so the combination may be shipped
under the licence above.

| Asset | Licence | Upstream |
|---|---|---|
| `assets/fonts/IBMPlexMono-*.ttf` | SIL OFL 1.1 | [IBM/plex](https://github.com/IBM/plex) |
| `assets/fonts/Newsreader*.ttf` | SIL OFL 1.1 | [productiontype/Newsreader](https://github.com/productiontype/Newsreader) |
| `assets/fonts/SchibstedGrotesk.ttf` | SIL OFL 1.1 | [schibsted/schibsted-grotesk](https://github.com/schibsted/schibsted-grotesk) |
| `assets/dict/dictionary.zip` (ECDICT, filtered) | MIT | [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT) |
| `assets/sample/pointers.json` | — | sample data generated by this project |

The ECDICT archive is not a copy: `tools/build_dictionary.py` filters,
re-phonemes and re-orders it into the bundled file. That script is part of this
repository and is covered by the licence above, so the derivation is auditable
end to end. Keep the notices with the assets if you fork this.

## Contributing

Issues and pull requests are welcome. Two things worth knowing before you send
one:

- **The invariants are the spec.** `dart tool/check_invariants.dart` runs the
  data-model rules as a program, and `docs/ARCHITECTURE.md` explains why each one
  exists. A change that breaks one is a change to the design, not a bug fix, and
  needs to say so.
- **`docs/STATUS.md` is the truth about what works.** If you are about to build
  something, read it first — the answer may be that it half exists already.
