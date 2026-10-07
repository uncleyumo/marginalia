# Architecture

## The one idea

Everything in this app is either **a fact that was recorded** or **something
derived from those facts**. There is no third category, and in particular there
is no cached summary that can disagree with what it summarises.

That is why there is no `library` table: the shelf is `LEDGER ∪ live QUEUE`,
merged on title at read time. It is why the calendar's numbers are `GROUP BY`
queries over one `day_article` row per (day, article) rather than a second
`days` table. And it is why freeing space edits a `kb` column and touches
nothing else.

If you are about to add a field that restates something already recorded, that
is the bug this design exists to prevent.

## Layers

```
domain/     pure Dart. No Flutter, no database, no network.
data/       the outside world: sqlite, keystore, zip, http, audio.
core/       design tokens and the widgets built from them.
features/   one directory per screen. Renders what it is handed.
main.dart   the shell: owns all state, wires every screen.
```

`domain/` importing Flutter is a mistake. `features/` holding state is a
mistake — screens are handed data and callbacks and hold only what is genuinely
local to them (which pane is open, whether a sheet's star is on).

## domain/

| File | What it holds |
|---|---|
| `models.dart` | `Article`, `Sentence`, `Mark`, `MarkTier`, `WordEntry` |
| `queue.dart` | `Queue`, `QueueSlot`, `SlotState` — the three-slot model |
| `plan.dart` | `ReadingPlan` (seven fields), `PlanField`, `PlanRewrite` |
| `word_pool.dart` | `WordPool`, the decay curve, `selectionChance` |
| `library.dart` | `shelf()`, `ShelfRow`, `Library.search`, `mostRevisited` |

The five invariants live in these types, not in comments:

1. The queue is exactly three slots.
2. A slot is `planned` or `ready`. There is no third state and no `finished`.
3. Any slot being `planned` stops all automatic writing.
4. Reading counts and never removes. `listens` never touches `reads`.
5. Freeing space changes `kb` and nothing else — counts survive deletion.

`tool/check_invariants.dart` runs these as a program. It is a program and not a
`test/` file on purpose: `dart test` cannot start on this machine (native-asset
subprocess fails with `CreateFile` error 231), so a test suite that cannot run
would be worse than none. Run it with `dart tool/check_invariants.dart`.

## data/

| File | Responsibility |
|---|---|
| `database.dart` | drift schema; `day_article` is the single source of truth for history |
| `repository.dart` | every read and write the app performs, in one place |
| `keystore.dart` | the two API keys, in the Android Keystore and nowhere else |
| `dictionary.dart` | loads the inflated ECDICT json, in a background isolate |
| `zip.dart` | a minimal single-member zip reader, so `archive` is not a dependency |
| `audio.dart` | `SentencePlayer`: device TTS, MiMo recordings, and the cache |
| `handler.dart` | the `audio_service` handler that puts transport on the lock screen |
| `remote/api.dart` | the two HTTP shapes: writing, and speech |
| `writer.dart` | builds the prompt and parses the writer's reply |
| `samples.dart` | the bundled first-run articles |

### The dictionary

`assets/dict/dictionary.zip` is 10.4 MB and inflates to 39 MB of json. It is
inflated once into the app's private directory and parsed **in a background
isolate** — parsing on the UI isolate froze the first frame for about five
seconds. Until it finishes, a word tap says so plainly instead of showing an
empty card.

### The audio

Two engines and no silent switching:

- **Device TTS** (`flutter_tts`) is the floor. Free, offline, always available,
  and what a fresh install with no key uses.
- **MiMo** is the only online engine. A synthesised sentence is cached to disk
  keyed by voice + text, so hearing it again costs nothing and works offline.

A failure in the recorded path falls through to the device voice rather than
leaving a gap, and the Listen screen labels which engine is speaking.

## main.dart

It is large, and deliberately so. Every screen is a stateless-ish widget handed
data and callbacks; `_ShellState` owns the queue, the plan, the pool, the
dictionary, the audio, and the navigation stack. Splitting that across
`Provider`s was considered and rejected — the app has one state owner, and
hiding it behind a container would make the invariants harder to see, not easier.

`build()` returns `_stack.last`, so pushed screens must be built fresh. Pushing
a pre-constructed `Widget` instance means Flutter's `canUpdate` sees the same
widget and skips the rebuild, which is exactly how a settings pane silently
stops refreshing.

## Design tokens

`core/design/tokens.dart` declares colour, type, spacing, radii and motion once.
Nothing below it re-declares a value. `context.colors` and `context.texts` are
the only ways to reach them.

Two rules that are easy to break by accident:

- Colours are never `#000` or `#fff`; the neutrals are warm.
- Vermilion means "this costs money or is a primary action". Jade means "already
  done". A cost line that says `free` is jade — never vermilion.
