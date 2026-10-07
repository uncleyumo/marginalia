# Design context — No-Stop English

> Consumed by the Impeccable skill. Do not infer from code; this is the source of truth.

## Target audience
A Chinese software developer, **beginner-level English**. ~40 min commute each morning
+ ~30 min at home at night. Hard ceiling: **1 hour a day**, and most of it is not
spent looking at the screen (it is spent listening, on a bus).

## Use cases
1. **Night, at home (≈22:00, 20–30 min):** read tomorrow's article. Must not be
   interrupted by dictionary lookups. Wants to stay in English.
2. **Morning, commuting (≈40 min):** press play once. Hands in a pocket, phone in a
   bag, screen off. Lock-screen controls only.
3. **Anytime, 30 seconds:** look up a word. **English gloss first**, Chinese only after
   an explicit tap. Every word and every sentence must be pronouncable.
4. **Rarely:** change what next week's articles are about, in the calendar.

## What the user hates (hard constraints)
- Being **graded**. No "do you know this?", no "mark as learned", no confirm buttons
  that claim he remembered something. The app **records, never judges**.
- **Complication.** Dropdowns, secondary menus, status tables. Everything must be
  reachable in one or two taps, on one screen.
- **Tedious vocabulary memorisation.** Repetition must be engineered into the article,
  not assigned as homework.
- **Reading interrupted** by a translation hunt.

## Brand personality / tone
**A paperback under a warm desk lamp.** Calm, quiet, confident, analogue, bookish.
An editor's pencil, not a dashboard. Warmth without cuteness; seriousness without
austerity. The app should feel like something you read, not something you operate.

Explicitly **not**: Duolingo green, AI purple-blue gradients, neon-on-dark, glassmorphism,
gamified streaks and badges, cheerful illustration mascots.

## Signature moment
The article page: **serif body text on warm paper (or warm ink at night), every word
tappable, unknown words marked with a thin vermilion pencil underline** — like a book
someone has annotated for you. One tap = English gloss + sound. Second tap = Chinese.

## System rules (must hold in every screen)
- **English first, everywhere.** Chinese is always behind one deliberate tap.
- **Never judge.** No self-report of memory, ever.
- **"Again" ≠ "tomorrow."** Starring a word raises its weight in the pool; it does not
  schedule it.
- **Three slots always waiting**, not a rolling window. **Reading never removes one** — each card
  carries `read N×` / `heard N×` counters instead of a finished flag, because reading something once
  is a beginning, not an ending.
- **Two states, visibly different.** `ready` is a solid card with a solid jade dot; `planned` is a
  **dashed vermilion border** with a hollow dashed dot and the word `planned · not written yet`.
  A state the user cannot see at a glance is a state the user will trust wrongly.
- **Never auto-spend.** A planned card stops all writing. The reroll affordance sits **on the
  card**, not behind a menu — an exit you have to go looking for is not an exit.
- **No night, no day.** Reading and hearing are the only two functions; the app never implies
  an hour or a routine.
- **Counts, not verdicts — in the UI too.** A counter is the strongest visual claim allowed. No
  progress ring, no streak flame, no "you have learned N words". A history screen answers *which
  ones and how many times*, never *how well*.
- **Counts are not storage.** Deleting an article frees its **bytes** — text and audio — and
  **never** its `read`/`heard` counters. *You read it five times; that happened.* Freeing disk
  space is honest housekeeping; **resetting the record would be a lie**, because the file was
  never the memory. If an implementation zeroes a counter when storage is freed, it has broken this.
- **A deleted thing stays visible and marked.** It renders struck through, tagged
  `deleted · text and audio removed`, keeps its rank among its own kind, and is still counted in
  *Most revisited*. Hiding the row would hide the *fact* that the file is gone, leaving the user
  to meet a remembered article with no explanation.
- **Storage you cannot see is storage you will not free.** Every saved article carries its size in
  KB, the shelf shows a used-of-budget bar, and Settings → *The small print* quotes the same live
  figures. An article you cannot account for is one you cannot judge.
- **A shelf must be scannable.** **One title line, one quiet meta line, numbers in a fixed column,
  state on the spine.** The earlier row carried three badges plus two stacked counters plus an
  Open button — six competing text objects, and every row looked the same. That is a list you must
  *read*, not one you can *scan*. Two rows differing only in a state word must not look different,
  so the topic lives in the meta line and is not repeated as a badge beside it.
- **A destructive action states what goes and what stays, before it happens.** The free-space
  confirmation is two colour-coded columns — **GOES** (text, audio, KB freed) beside **STAYS**
  (`read 2×`, `heard 1×`, *it stays on this list, marked as deleted*) — plus one sentence in the
  reader's own numbers. "Delete" alone would be a lie of omission, because the app has promised
  repeatedly that nothing is ever deleted and now has a button that says delete.
- **A long scrolling sheet needs a scrim.** A sheet taller than the screen, floating over an
  undimmed page, reads as broken rather than as an overlay. The scrim **refuses to dismiss while a
  paid-for result is unaccepted** — you may swipe away a blank sheet, never discard a result you
  paid for by tapping outside it.
- **A paid-for change is shown as a diff, never asserted.** "Your plan changed" is a claim, and a
  claim you cannot see is the same failure this whole project exists to avoid — the same reason a
  tapped word shows the English gloss before the Chinese. The proposal is held aside and nothing is
  written until the user accepts; editing the request again invalidates the diff, because a diff
  for a request you changed is a lie about what you asked.
- **Teach by example, not by placeholder.** The Ask-AI box ships with six tappable real prompts
  that *append* to what you already typed. An empty field with a grey placeholder teaches nothing.
- **Structured data, not prose blobs, once a machine edits it.** The reading configuration is
  seven named fields (`reader · topics · style · gloss · avoid · length · marked`) rendered as
  labelled rows, plus a `raw` field sent **verbatim** on top. Prose cannot be pointed at, diffed,
  or rewritten field by field — and the user's own words are never dropped to make room for
  structure.
- **A screen you have to scroll is a screen that hides something.** Anything used more than once a
  week gets its own screen; anything used once a year goes in **the small print**, never beside
  something common. Order is not enough — separation is.
- **A hub row summarises state**, so nothing must be opened just to check whether it is right.
  Summary text is live: change something inside, the hub row updates. And if the summarised value
  can change elsewhere — storage changes when a shelf row is freed — re-render on every open, so
  the figure is never stale.
- **Nothing you have read is ever forgotten.** The queue is a working surface of three; the Library
  is the archive of everything. *Done with it* moves a card out of the queue — it never removes an
  article from existence. A row that left the queue is **archived, not gone**, and it must stay
  reachable, because an article you cannot find is an article you cannot re-read.
- **An archive is a first-class screen, not a settings pane.** It gets a nav slot of its own, a
  search field, and filters that are *questions* ("worth reading again"), not states ("active").
  Sort by attention (`reads + listens`) so the articles that actually mattered float up on their own.
- **A control that duplicates a gesture on the object is worse than no control.** The Auto / Pinned /
  One-off slot modes were deleted for exactly this reason. If a *mode* cannot be justified by a
  decision the user makes with new information, it is a setting to delete — not a card to add to
  Settings.
- **An explanation is allowed; a control is not.** Where a section used to hold a control, a plain
  three-row list naming the real gestures may take its place, provided **every row points at a place
  the finger already goes.** A row that asked for a value would be a control, and a control is what
  we just deleted.
- **Price must be stated where the decision is made, and it must be true.** The plan sheet's cost row
  says `free` whenever nothing will be written. A "$0.002" beside an action that spends $0 is a lie
  the user plans around. Free is a good outcome, so it gets **jade** — never vermilion, which is
  reserved for spending.
- **Cost near zero by default.** The default configuration must work with **no API key
  at all** (free TTS + on-device voice + offline dictionary).

## Screens (v9)
| Screen | What it is for | Frequency |
|---|---|---|
| **Queue** | the three waiting; read or write | daily |
| **Article** | Read / Listen; every word has sound + gloss | daily |
| **Library** | everything, searchable, with sizes; reopen or free space | weekly |
| **History** | the calendar, looking backwards only | rarely |
| **Words** | Crucial now, then everything you met | daily, 30 s |
| **Settings** | hub of four panes | rarely |

Two of these were once one screen and one was a settings card. Splitting them is the whole point:
a rarely used function must never share a screen with a common one.

## Visual system (v9)
- **Palette:** warm ink neutrals; **vermilion** (60/30/10 → 30%) for
  primary action, star, weight, "new word"; **jade** for "ready / met before / done";
  **lamp amber** for "still writing". All in OKLCH, all neutrals tinted, never `#000`/`#fff`.
  **One accent on a screen** — colour is never applied to a whole card and never to body text.
  **Declared at the app level, not on a subtree** — a token scoped to one widget's ancestor
  resolves to nothing elsewhere and renders transparent, which is exactly what happened to every
  bottom sheet before v9.
- **Type:** `Newsreader` (serif, optical size) for anything read;
  `Schibsted Grotesk` for anything operated; `IBM Plex Mono` for IPA and API keys.
  Modular scale, 1.25–1.3 ratio, `clamp()` on display sizes. **In a data view the label is mono
  and the value is serif** — so the eye can tell *what kind of thing this is* from *what it says*
  without reading either.
- **One surface, no schedule:** a single warm low-glare ink. No theme switch in the app at all —
  the day/night distinction was removed, not renamed.
- **Motion:** 100 / 300 / 500 ms, `cubic-bezier(0.16,1,0.3,1)`, transform + opacity only,
  `prefers-reduced-motion` honoured.
- **Texture:** fine paper grain, hairline rules, hatched bars — no blurs, no glow.
