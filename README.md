# marginalia

A no-stop English reader for Android. Three articles are always waiting; you read
one, hear one, or both, and the next is written while you are away from the phone.

The name is the thing itself: marginalia are the notes a reader leaves in the
margin. This app is a margin that answers back.

**Offline first, keys optional.** A fresh install with no API key reads bundled
sample articles, looks words up in a bundled 392,695-entry dictionary, and speaks
with the phone's own TTS engine — in airplane mode, for $0.00. Keys buy a better
voice and a cheaper writer; they are never required.

Licensed under [GPLv3](LICENSE).

## What is in here

```
Marginalia/               the Flutter app — start here
  README.md                 what it does, the keys, the layout, the licences
  docs/                     architecture, build manual, user guide, status
  lib/                      the source
  tool/                     the invariants and the agent checks, run as programs
  test/                     widget tests (word hit-testing among them)
Marginalia-Prototype/     the design document and the content pipeline
  docs/DESIGN.md            the source of truth for every decision in the app
  prototype/                the HTML prototype the design came from
  pipeline/                 article and dictionary generation, for offline use
LICENSE                   GPLv3
```

`Marginalia-Prototype/docs/DESIGN.md` is the design bible. Where the app and that
document disagree, the document is right and the code is a bug.

## Running it

Flutter 3.44 or newer on the stable channel, JDK 17, Android SDK platform 35.
`Marginalia/docs/BUILD.md` is the full manual; the short version is

```bash
cd Marginalia
flutter pub get
flutter analyze --no-pub && flutter test
dart tool/check_invariants.dart && dart tool/check_agent.dart
flutter run
```

`Marginalia/docs/BUILD.md` is the full manual — the SDK layout, the JDK, driving
the emulator with `adb`, and the release checklist.

## The shape of it

Three decisions carry the whole design, and they are worth knowing before you
read any code:

1. **Tapping a word is the interaction.** Not long-press, not a selection menu,
   not a mode you have to discover. You tap the word and the gloss appears.
2. **There is no bar on the progress.** No percentage, no "3 of 5", no estimate
   time remaining. The article ends when it ends.
3. **No per-line buttons.** One mechanism per gesture instead of a pair under
   every sentence: tap a word for its meaning, long-press a line to hear it, two
   toolbar buttons for all translations at once and for the reading size.

`Marginalia/docs/ARCHITECTURE.md` explains the rest — why the data model has no
"done" state, why the library is derived rather than stored, why the queue is
exactly three.

## Contributing

Issues and pull requests are welcome. Two things worth knowing first:

- **The invariants are the spec.** `dart tool/check_invariants.dart` runs the
  data-model rules as a program. A change that breaks one is a change to the
  design, not a bug fix, and should say so.
- **`Marginalia/docs/STATUS.md` is the truth about what works.** Read it before
  building something — the answer may be that it half exists already.

## Licence

GNU General Public License v3.0 — see [LICENSE](LICENSE). The bundled fonts are
SIL OFL 1.1 and the bundled dictionary derives from ECDICT (MIT); both are
compatible with GPLv3. `Marginalia/README.md` names every asset and its upstream.
