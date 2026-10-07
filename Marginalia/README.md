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

## The two keys

Both are optional and both live in the Android Keystore, never on a server —
there is no server.

| Key | What it buys | Where it is configured |
|---|---|---|
| Writer | Articles written for you, at your plan's topic | Settings → Who writes the articles |
| Voice | MiMo reads articles aloud in a recorded voice | Settings → Voice |

Nothing is ever written without you tapping **Write it** on a planned card, and
that card states the cost before you tap.

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
