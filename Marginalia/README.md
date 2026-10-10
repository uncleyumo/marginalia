# marginalia

A no-stop English reader. Three articles are always waiting; you read one, hear
one, or both, and the next is written while you are away from the phone.

The name is the thing itself: marginalia are the notes a reader leaves in the
margin. This app is a margin that answers back.

## What it does

- **Read.** An article is a block of prose with every word tappable. Tap a word
  and its meaning appears in English, with the Chinese one tap further. Long-press
  a line to hear it.
- **Listen.** The second tab shows one sentence at a time, very large, and reads
  the whole article aloud with the transport on the lock screen.
- **The queue is three, always.** Finish one and the next is written. Reading
  counts and never removes anything — there is no "done" state anywhere in the
  data model.
- **The words come back.** Words you meet and words you star gain weight; weight
  decays with a seven-day half-life and steers what the next article is about.

## Running it

The environment is not on your PATH by default. `run-emulator.bat` starts the
AVD, `run-app.bat` builds and installs on whatever device is attached, and both
set `JAVA_HOME`, `ANDROID_HOME` and `PATH` themselves.

```
..\run-emulator.bat          # boot the emulator (once)
..\run-app.bat               # build + install + run
```

`..\SETUP.md` covers the toolchain from scratch, `..\HOW_TO_RUN.md` the shorter
version.

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
export ANDROID_HOME="E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
flutter analyze --no-pub && dart tool/check_invariants.dart && dart tool/check_agent.dart
flutter build apk --release
```

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
