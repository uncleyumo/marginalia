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
| `queue.dart` | `Queue`, `QueueSlot`, `SlotState`, `CostKind` — the three-slot model |
| `plan.dart` | `ReadingPlan` (seven fields), `PlanField`, `LengthBand`, `PlanRewrite` |
| `instruction.dart` | `Instruction` — a sentence the reader saved for the writer |
| `agent_budget.dart` | every hard limit on a writing run, as bare constants |
| `difficulty.dart` | `Difficulty`, the two coverage lines, `markCapFor` |
| `word_pool.dart` | `WordPool`, the decay curve, `selectionChance` |
| `library.dart` | `shelf()`, `ShelfRow`, `Library.search`, `mostRevisited` |
| `picture.dart` | `Picture`, `PicturePack` — the 2 MB ceiling and the 5-picture cap |

The five invariants live in these types, not in comments:

1. The queue is exactly three slots.
2. A slot is `planned` or `ready`. There is no third state and no `finished`.
3. A slot being `planned` stops automatic writing, and nothing stops a tap.
   `mayAutoWrite` gates code that would spend without a tap; `writeSlot` is
   reachable only by one.
4. Reading counts and never removes. `listens` never touches `reads`.
5. Freeing space changes `kb` and nothing else — counts survive deletion.

Invariant 3 is the one that changed when the app learned to write by itself,
and it changed in a way worth stating precisely: it now reads "stops
**automatic** writing". A reader who taps `Write it` on a planned card gets an
article — an app that refused the only tap it has would be an app that can
never spend a cent, which is not what "a deliberate, affordable action" means.
The two halves are kept apart in the code so that neither can quietly become
the other.

`tool/check_invariants.dart` runs these as a program. It is a program and not a
`test/` file on purpose: `dart test` cannot start on this machine (native-asset
subprocess fails with `CreateFile` error 231), so a test suite that cannot run
would be worse than none. Run it with `dart tool/check_invariants.dart`.

### Difficulty is derived, not stored

`Article.difficulty` is a **getter**, computed from the marks the writer chose
and the running words in the body. There is no `difficulty` column and there
will not be one: the body already states everything the label needs, and a
stored copy could disagree with the text it describes. The same reasoning that
forbids a `library` table forbids this one.

The price is that a stub article read back from the database has no band — the
same price it already pays for having no word count.

### There is no `topic`, and there will not be one again

An article's subject is either **a sentence the reader typed** (`Instruction`,
saved and reusable) or **the writer's own choice**. There is no field holding a
list of permitted subjects, because such a list is configuration pretending to
be content: it has to be maintained forever, and every article written under it
drifts towards the same handful of words.

What the reader sees instead is `Article.keywords` — three to six words the
writer produced, shown on the card and in the article header. Keywords are
*output*, so they cost nobody any maintenance and they say more than one label
chosen in advance.

`Instruction` is a sentence, not a noun. "Explain how a limit order fills, for
someone who has never traded" is a request; `Finance` is not.

### The writer decides how many words to mark

`ReadingPlan` has no `marked` field. Asking a model for a fixed number of
marked words makes it pad the list with words that did not need marking, and a
mark that is wrong is worse than no mark. So the writer marks what it judges
hard, and the app measures the density afterwards.

`markCapFor` is the only ceiling, and it is not a setting: 1 mark per 4 words,
five times the density at which an article already reads as Hard. Nothing a
model plausibly returns comes near it, so the label is always honest.

## data/

| File | Responsibility |
|---|---|
| `database.dart` | drift schema (**v3**); `day_article` is the single source of truth for history |
| `repository.dart` | every read and write the app performs, in one place |
| `keystore.dart` | the four API keys, in the Android Keystore and nowhere else |
| `dictionary.dart` | loads the inflated ECDICT json, in a background isolate |
| `zip.dart` | a minimal single-member zip reader, so `archive` is not a dependency |
| `audio.dart` | `SentencePlayer`: device TTS, MiMo recordings, and the cache |
| `handler.dart` | the `audio_service` handler that puts transport on the lock screen |
| `remote/api.dart` | the two HTTP shapes: writing, and speech |
| `remote/agent.dart` | the writing loop: turns, tools, budget, retries, finalize |
| `remote/chat.dart` | one OpenAI-compatible turn, parsed totally |
| `remote/tools.dart` | `AgentTool`, `ReadStoryTool`, `WebSearchTool`, `ToolOutcome` |
| `remote/news.dart` | the optional Zhihu Daily source |
| `remote/mcp.dart` | a minimal MCP-over-HTTP client, for web search |
| `remote/log.dart` | the in-memory ring buffer the debug screen reads |
| `writer.dart` | builds the prompt and parses the writer's reply |
| `samples.dart` | the bundled first-run articles |

### `remote/` is pure Dart, and that is load-bearing

Nothing under `data/remote/` may import `package:flutter`. `tool/check_agent.dart`
drives the whole agent layer from a plain Dart program, and one
`package:flutter/foundation.dart` anywhere in the chain pulls in `dart:ui`,
which does not exist outside a Flutter engine. That is why `log.dart` uses plain
callbacks instead of `ValueNotifier` and `print` instead of `debugPrint`.

### The writing agent

The writer is a single request by default and a small agent when — and only
when — at least one optional source is configured. That decision is what keeps
the cost line honest: a reader with no news key and no search key never enters
the loop, so `one call · ~25 s` remains true for them.

The loop is bounded by constants in `domain/agent_budget.dart`, every one of
them checked *before* the blocking operation rather than after. Termination is
structural: three monotonic counters (model calls, tool calls, turns) plus a
wall clock, each checked at the top of every iteration, and no branch re-enters
the loop without consuming one of them.

Two Dart facts shape the code more than anything else:

- **`Future.timeout` is not cancellation.** It completes the future; the socket
  stays open and the response can arrive later, into a turn that is already
  closed. So the loop owns its own `http.Client` and `close()`s it on timeout,
  rebuilding lazily. It must never close `main._api`, which audio and plan
  rewriting also use.
- **`reasoning_content` must be stripped before an assistant turn is sent back.**
  MiMo and DeepSeek reject their own reasoning being echoed. The strip happens
  in exactly one function, `ChatTurn.assistantMessage()`.

### Pictures as an instruction

A photograph of a good sentence, a scene, or a word list from another app is an
instruction, and the pipeline has one rule about it: **a picture is made small
before anything is spent.**

```
image_picker ──▶ data/shrink.dart ──▶ domain/picture.dart ──▶ writer ──▶ api
   the file        decode + scale        the ceiling,        prompt    content
                   to 1568px             stated once         tells it   array
                   + JPEG walk                        what it is
```

Four decisions worth knowing before changing any of it:

- **The ceiling is 2 MB and the cap is 5 pictures** (`domain/picture.dart`). A
  12 MP photo is ~4 MB, and five of those base64'd is a 27 MB request body that
  several providers refuse *before charging anything*. Both numbers are checked
  as executable invariants, not trusted.
- **A file already under the ceiling is passed through untouched.** Re-encoding a
  200 KB screenshot to save nothing is work that makes the picture worse and
  saves nothing.
- **Vision is a per-endpoint fact, not an assumption.** `deepseek-chat` answers
  `400 unknown variant image_url` for a content array, having never read the
  picture. So `WriterEndpoint.supportsVision` gates the write *before the call*,
  and the refusal sentence names the endpoints that would have taken it.
- **Pictures go into the FIRST user message only.** A loop makes several calls;
  re-sending five photographs on every turn would send the same kilobytes four
  times and charge for each one.

**Nothing is stored.** There is no picture table, no gallery, nothing that
outlives the write — the reader already has these in their photo app. The one
thing written to the queue row is the intent (`from a word list`), because a card
that still says `Anything` while five photographs were attached to it is a card
lying about its own state.

The prompt split matters and is easy to get wrong: `ArticleWriter.system` stays
byte-identical for the no-picture path, and `pictureRules` is appended only when
there are pictures. A system prompt describing photographs to a model that was
sent none is a model looking for something that is not there.

### Schema migrations, and the trap in them

`schemaVersion` is **3**. The v1 → v2 upgrade rebuilds `plan_rows` (one `length`
became three bands) and `queue_rows` (`planned_marked` became `planned_band`).
The v2 → v3 upgrade drops `topic`/`focus` from `queue_rows`, drops `topics` from
`plan_rows`, adds `keywords` and `last_seen_day` to `ledger_rows`, and creates
`instruction_rows` and `article_rows`. All of it uses drift's `TableMigration`
rather than drop-and-create, so a reader who had a plan keeps it.

The v2 → v3 upgrade also CONVERTS data: every old topic becomes an instruction
(`"NVDA"` → `"Write about NVDA"`), except the placeholder `Free pick`, which is
deliberately dropped — a saved instruction saying "write about free picks" is
worse than no instruction. The old topics are read with raw SQL *before* the
rebuild, because the column is gone by the time the rebuild finishes.

`article_rows` is new, and it fixes a real defect rather than only enabling one:
before it, an article body lived in memory for the session, so a card came back
after a restart reading `0 words` and opened onto nothing.

**Rebuilding a table drops its triggers.** `queue_at_most_three` is invariant 1
stated by the database, and `TableMigration` on `queue_rows` creates a new
table, copies the rows, drops the old one and renames — taking the trigger with
it. `_installQueueTrigger` is therefore called from **both** `onCreate` and the
end of `onUpgrade`. One function, because two copies drift apart and only one of
them is exercised on a fresh install. After any migration, verify with:

```
SELECT name FROM sqlite_master WHERE type='trigger';   -- queue_at_most_three
```

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

### Single flight, and why the lock is not on the slot

`_write` is the only place money leaves the phone, so exactly one may be in
flight. That rule was first written as `if (slot.isWriting) return` on the card
being written, which was correct for as long as every write began with a tap on
that card. The automatic write broke it twice over, in two different ways:

**The check and the claim must be one expression.** The guard used to sit at the
top of `_write`, and `isWriting = true` was set after the key was read — two
`await`s later. Two callers entering that window both read `false`, both walked
on, and both reached the paid call: two charges, and the second article
overwrote the first. A check separated from its claim by an `await` is not a
check. The lock is now `_writeClaim`, claimed in `!_claimWrite()` with nothing
between the test and the set.

**The lock must not be persisted.** It used to be `QueueSlot.isWriting`, and
`_persistSlots` wrote that flag verbatim. Every other action calls `saveQueue` —
`Done with it` on another card, a reroll, an edit — so any of them landing
mid-flight wrote a `true` that was no longer true. A process that died right
after restored it in `loadQueue`, and the card read "Writing…" forever with
`Write it`, `↻`, `▣` and `Change it` all dead; the only escape was clearing the
app's data. `saveQueue` now always writes `false` and `loadQueue` always reads
`false`. A queue off the disk has no write in flight, because a write in flight
belongs to a process and the process reading it is not that process.

So the flag on the slot is a *picture* of the lock — what the card renders — and
`_writeClaim` is the lock. Every exit from `_write` releases it: success, no key,
a text-only model refusing pictures, a provider refusal, a storage failure, and
an unmounted shell. `_releaseWrite` is idempotent because the exits are many.

### Generation is remote, and there is no local model

Worth stating plainly, because the app is otherwise almost entirely offline and
the distinction decides both the cost and the connection requirement: **there is
no local language model here.** No bundled `gguf`, no ONNX runtime, nothing that
produces text on the device. Every article is written by a remote API over HTTPS
— DeepSeek, MiMo or OpenAI — via `RemoteApi._post`, and that is the only place
money leaves the phone.

Everything else is local: the bundled samples, the bundled 392,695-entry
dictionary, the SQLite database, the word pool and the marking. The device's own
TTS engine speaks, so listening is local too. With no key the app reads, hears
and looks words up in airplane mode for $0.00; it just cannot have a new article
written.

### A paid article lands whole, or not at all

`landArticle` writes the body, the ledger row and the queue row in ONE drift
transaction. They used to be three separate calls in a row, and a process dying
between any two of them — the app swiped out of the recents list, the system
reclaiming memory — left a half-landed article: a body with no card, so an entry
in the library that opens onto nothing, or a card with no ledger row, so a
readable card the library and the storage bar cannot see. Both are garbage the
reader has no way to clear from the interface, and both were reachable without
doing anything wrong.

One transaction is the same guarantee `_persistSlots` already makes for the
queue's three slots. The ordering inside it is still body → ledger → queue, for
the reason it always was: a card that says `ready` while its body is not on the
phone opens nothing after a restart.

What this does NOT close is the third window — money spent, response never
received. The request is already at the provider and a local timeout says nothing
about what they have billed; `RemoteApi._post` says so in its own comment rather
than pretending otherwise. The guarantee is narrower and worth stating exactly:
**a paid article either lands completely or leaves nothing behind to clean up.**
The failure path in `_write` puts the card back to tappable and says both halves
out loud — the money was spent, and nothing landed.

## Design tokens

`core/design/tokens.dart` declares colour, type, spacing, radii and motion once.
Nothing below it re-declares a value. `context.colors` and `context.texts` are
the only ways to reach them.

Two rules that are easy to break by accident:

- Colours are never `#000` or `#fff`; the neutrals are warm.
- Vermilion means "this costs money or is a primary action". Jade means "already
  done". A cost line that says `free` is jade — never vermilion.

### Appearance, and why the reading faces are system families

`AppearanceMode` is `light | dark | system`, and `system` is the default: a
phone that has already been told what its owner prefers should not be asked
again. `system` needs `WidgetsBindingObserver` — **not**
`MediaQuery.platformBrightnessOf`, because `MarginaliaApp` sits above
`MaterialApp` and has no `MediaQuery` to read.

The status-bar icons invert with the surface. They were hard-coded light, which
is right for `warm ink` and invisible on `warm paper`.

`ReadingFace` offers six faces and five of them are **Android system families**.
That is not laziness. Every article here is bilingual, so a face is only good if
the Chinese beside it looks right — and that is decided by what Android
substitutes for glyphs the Latin font lacks. `fonts.xml` answers per family
(`fallbackFor="serif"`), so:

- `serif` → Noto Serif **+ Noto Serif CJK** — a matched pair
- `sans-serif` → Roboto **+ Noto Sans CJK** — a matched pair
- `source-sans-pro` → Adobe's face; Noto Sans CJK is its sibling

A bundled Latin font has no CJK at all, so its Chinese falls back to the
phone's **sans** — serif English over sans Chinese, which is what the app
shipped with and the reason `Noto Serif` is the default. `source-sans-pro` is
not in the AOSP baseline, so it carries `sans-serif` as a fallback list rather
than silently doing nothing on a phone without it.

If you add a face, it must be one the phone already has, or it must ship with
the APK.
