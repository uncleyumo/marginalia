# No-Stop English — System Design v9

Flutter / Android. **Three articles always waiting** — read or hear them whenever you like,
there is no schedule and no night/day. The calendar only remembers what you already did.

New in v9: **your reading configuration became structured data instead of a paragraph** —
`reader · topics · style · gloss · avoid · length · marked`, rendered as seven labelled rows
so a single field can be pointed at, and **`✦ Ask the AI to change it`** rewrites it in plain
language through *the same writer that writes your articles* (one call, `~$0.002`, cost shown
before you spend, **a diff you must accept**, six tappable example prompts to show what to
write) · **`✦ Ask the AI` and the free-text editor both feed one plan object**, and your own
words are sent **verbatim on top of the fields** so nothing typed is ever lost · the Library
was rebuilt as a **scannable shelf** — a colour-coded spine, one title line, one quiet meta
line, the counters in a fixed column, and **the size of every article in KB** · and storage is
now **manageable**: ⌫ frees an article's text and audio while **the read and heard counts stay
forever**, the freed row stays on the list **struck through and marked `deleted`**, and a
standing storage bar says `2.2 MB of 11.7 MB`.

> **The deletion rule in one line: counts are not storage.** Deleting a file does not un-happen
> a reading — so the bytes go and the record stays. See §4e.

New in v8: a **Library** screen — the queue holds three, the library holds **everything**, and
**nothing is ever deleted** (*Done with it* takes a card out of the queue, not the article out of
existence) · **search by title or topic** plus four filters (*worth reading again / never read /
heard but not read / all*) · any archived article **reopens with its counters intact**, a
*from your library* banner and a back button that returns to the shelf · the list is **derived**
(`LEDGER ∪ QUEUE`), never a second copy of the truth · the **Auto / Pinned / One-off slot modes
are removed** as duplicates of gestures the card already has, and Settings → *What you read* now
explains the three real controls instead · the **cost row in the plan sheet says `free`** whenever
nothing will be written, instead of always claiming $0.002.

New in v7: each queue slot has **two states — ready / planned** · **automatic generation
stops on a planned card**, so an unplanned $0.002 call cannot happen · every planned card has
**↻ Give me a different one** (random, zero input, free, instant) · **Done with it** leaves a
*plan*, not an article · the plan sheet was cut from a 6-row spec table to **two fields and one
line of cost** · **Settings is a hub of four panes**, not one long scroll.

Carried over from v6: the mark became a **read counter** (`read N×` / `heard N×`) instead of a finished
flag, and **reading no longer removes an article from the queue** · history is per-article
(*which* articles, read how many times, heard how many times) plus a **Most revisited** ledger ·
the listen player has **⏮ / ⏭** · topic and focus chips are **user-editable presets** ·
"The angle" is now **"The focus"**, with an explanation.

Carried over from v5: the queue replaces the 7-day plan · hearing finishes nothing · topics are
one plan plus three slots · the voice is chosen from a list that was actually probed.

Prototype: `design/prototype.html` · visual system + Settings page in this version.
Design context lives in `.impeccable.md`.

---

## The two rules that now drive everything

> **Rule 1 — Never judge. Only record.**
> The app has no idea whether you remember a word, and it will not pretend to.

> **Rule 2 — Repetition is engineered, not reported.**
> Instead of asking "do you know this?", the system makes sure the word simply turns up again.
> **Again, not tomorrow.** A star raises weight; it does not force a specific day.

These two rules are one idea. Rule 1 kills the quiz. Rule 2 replaces it. The thing that decides
what you see next is **your crucial-words list**, not a scheduler guessing at your memory.

---

## 1. Why no confirm buttons

Self-reported recall is close to fiction, for three reasons:

- people tap *Good* to make the card go away, not because they knew it;
- **recognising** a word when it is shown to you is not the same as **producing** it;
- a quiz turns reading into testing, and testing is exactly what breaks the flow you want.

So every grading surface is gone: no *Again / Good / Easy*, no *Already know*, no
*Save for review*, no "owned" state, no "words you own" number.

**What the app records instead** — raw events, nothing more:

| Event | Weight |
|---|---|
| opened the English gloss | +1 |
| opened the Chinese version | +2 |
| played the word audio | +0.5 |
| replayed a sentence containing it | +0.5 |
| you starred it | +3 |

No event means "learned". An event only means "met, and it cost you something".

---

## 2. The crucial-words list

This is the scheduler, the review queue and the article planner all at once.

```
weight(w) = Σ  value(event) × 0.5 ^ (age_in_days / 7)
```

- **Half-life 7 days.** Old words fade on their own, so the list stays fresh instead of becoming a
  warehouse. A word you met once last month is gone unless you keep meeting it.
- **Encounters compound.** A word that keeps showing up keeps gaining weight — you do not have to
  do anything for that to happen.
- **Starring is the manual boost**, and it is immediate.
- **Below 0.5 the word drops off** the active list, but its history stays in your Words tab.

### How a word gets into a future article

The next time an article is generated — the nightly job, or a topic change — the pipeline:

1. reads the top ~30 words by weight;
2. tells the writer: *use 4–6 of these, naturally, in a real sentence*;
3. picks the remaining new words by general-frequency value for that topic;
4. uses words with weight ≥ 3 **twice inside the same article**.

### "Again" is not "tomorrow"

Starring raises a word's weight **at once** — that is the immediate part. What it does *not* do is
force the word into the next article or rewrite anything.

| Trigger | What happens |
|---|---|
| You star a word | Weight rises now and **holds** until the word really appears again. **No generation runs.** |
| You change a topic | That day is rewritten at once — you changed your mind about what to read, so you should see it change. |
| Days you already read | Never rewritten. Reading N× is N×. |

The word then competes, by weight, for every article generated from that moment on. It may come back
tomorrow or on Thursday. Forcing a specific day would make the article unnatural *and* cost a
rewrite on every star — so we don't.

A star **clears itself** once the word appears in a newly generated article. The wish is fulfilled,
so the list empties on its own instead of accumulating. If the word shows up and you still don't
know it, star it again — that loop is exactly what keeps the list fresh.

---

## 3. What the app is allowed to say about you

| Old (fabricated) | New (recorded) |
|---|---|
| "1,284 words you own" | "1,284 words you have met" |
| "learning / owned" state | "met 12× · last seen 2 days ago" |
| "7 words to review" | "hear it once more" (no grading) |
| streak | days you actually opened |

Every number is a count of something that really happened. Nothing is an inference about your brain.

---

## 4. Shape of the app

```
Queue      → three SLOTS, always · each is either READY or PLANNED
             READY   → title · read N× · heard N× · Read | Listen
             PLANNED → topic · focus · length · cost · Write it · Change · ↻ reroll
Article    → [ Read | Listen ] · every word and sentence has sound + translation
             · ⏮ ▶ ⏭ in the player · "Count this read" at the end
Library    → everything you have read · search + 4 filters · reopen any of it
History    → a calendar that only looks backwards · per-article counts · Most revisited
Words      → Crucial now (with weight bars) · then everything you met
Settings   → hub of four: What you read · Voice · Who writes · The small print
```

### The queue, not the calendar

The app no longer plans days. It keeps **three slots** — not three per day, three full stop.

### Two states per slot, and only two

| State | The card shows | It costs | What you can do |
|---|---|---|---|
| **ready** | title, `read N×`, `heard N×`, Read · Listen | already spent | read, listen, count reads, done with it |
| **planned** | topic, focus, length, cost | **nothing yet** | Write it · Change the plan · ↻ reroll · Not now |

The distinction matters because a slot that holds a plan and a slot that holds an article are
different facts, and every earlier version of this design conflated them. Conflating them meant
either spending money the user had not agreed to, or hiding the next choice until it was too late
to make it.

### Auto-writing stops on a planned card

This is the whole cost guarantee, in one rule:

```python
if any(slot.state == "planned" for slot in queue):
    return                       # do not write anything. Wait.
```

- A planned card means the app has **already shown you what it intends to write** and is waiting.
- It will not spend until you tap **Write it**. So an unexpected $0.002 charge cannot happen while
  you sleep.
- **Done with it** replaces a card with a **plan**, not an article — so the next thing also waits.
- The plan itself is free, instant and rerollable, so *deciding later* costs nothing.

### Reading never empties the queue

An article read once stays, because you may well want to go back to it. "Finished" implied you were
done with it, and one read-through is not being done with an article. Only **Done with it**
replaces a card, and what replaces it is a plan.

### ↻ Give me a different one

On every planned card, and inside the plan sheet:

- **zero input**, **zero calls**, **zero cost**, instant
- picks a random topic + a focus this topic has not been used with

The plan sheet forces a decision; this does not. It is the difference between *"I must choose"*
and *"show me another and I will decide later"*. Its absence is a design failure, not an
oversight — a reroll affordance has to sit **on the card itself**, because a card that only offers
"Build" or "Edit" has no exit for a user who wants neither.

- Want more practice? Come back to the same one. The queue keeps pace with *you*, not a date.
- Each card carries its own **topic pill** — tap it to say what that slot should be about.
- `⋯` on a card gives **write again · change what it is about · done with it**.

### What gets counted — two counters, no verdicts

There is no `finished` boolean anywhere. Each article carries `reads` and `listens`.

| Counter | Increments when | Can the app guess? |
|---|---|---|
| `reads` | you reach the end **and** tap **Count this read** | no — reaching the end is an event, the tap is a tap |
| `listens` | you press play in the Listen tab | no — it is a button |

**The end mark re-arms.** After you count a read, the button returns to grey and reads
`Read 3× so far`. Scroll to the end again and it becomes `Count another read · 3×`. So one
article can honestly be `read 5×` — and a checkbox could never have said that.

**Hearing has its own counter and touches nothing else.** Listening never increments `reads`,
never changes the end mark, never removes the article. You can listen to the same thing on the
commute for a week; the queue does not care, because listening is practice, not a checkpoint.

This is §1 in a new place: the app counts two things it can genuinely observe and never infers a
third. Understanding is not observable, so it is never asked about — and *how many times you came
back* turns out to be the more useful signal than *whether you finished*.

### The Library — the queue is three, the library is everything

The queue is a **working surface**: three cards, always, whatever happens. The Library is the
**archive**: every article that has ever existed in the app.

> **The record is never deleted.** *Done with it* takes a card **out of the queue**. It does not
> take the article **out of existence**. And since v9 you can free an article's **bytes** — which
> removes the text and audio but **never the read and heard counts**, and marks the row rather
> than hiding it (§4e).

This is a correction, not a feature. An earlier version deleted the article on *Done with it* and
kept only a row in the history. That satisfied a counter and destroyed the thing — and **you cannot
re-read what no longer exists.** It also silently contradicted an earlier requirement of this
project: *an article you have read once must still be reachable.*

> **The distinction that matters:** *deleting the record* would be a lie (§4e) — but *freeing the
> file* is honest housekeeping, **provided the record stays and the row is marked**. Both are true
> at once: nothing you read is ever forgotten, and you are never more than about 35 articles deep.

#### The list is derived, never a second copy

```
shelf() = LEDGER  ∪  live QUEUE          (a merge, keyed by title)
```

There is no `library` table. A row is computed from the day's log plus the current queue every
time the screen is drawn, so there is no second version of the truth to fall out of sync. The
badge on each row says which kind of row it is:

| Badge | Meaning |
|---|---|
| `in the queue` (jade) | still one of the three — opening it is an ordinary open |
| the topic name (grey) | archived; it left the queue but never stopped existing |
| `heard only` (vermilion) | `reads == 0 && listens > 0` — heard on the commute, never actually read |

#### The row is a shelf entry, not a badge bag

> **Rebuilt in v9.** The first Library row carried **three badges** (`in the queue` / the topic /
> `heard, never read`) plus **two stacked counters** plus an `Open` button — six competing text
> objects per row, so the eye had nowhere to land and every row looked identical. It was *a list
> you had to read*, not a list you could scan.

The rule that replaced it: **one title line, one quiet meta line, numbers in a fixed column.**

```
┌─┬────────────────────────────────────┬──────────┬────────┐
│▌│ What a Pointer Really Is          │ 5× read │ 412 KB │
│ │ C language · 4 min                 │ 9× heard │   ⌫   │
└─┴────────────────────────────────────┴──────────┴────────┘
 └ spine: jade = in the queue, grey = archived, hollow = deleted
```

| Element | Rule |
|---|---|
| **spine** (4 px) | the state, readable in peripheral vision — **jade** live, **grey** archived, **hollow** deleted. It replaces the state badge entirely. |
| **title** — one line | serif, the only loud thing in the row |
| **meta** — one line, small and grey | the **topic** and the **length**, plus `in the queue` / `heard, never read` only when they are true |
| **counters** — a fixed right column | `5× read` / `9× heard`, always in the same place, so the numbers line up down the screen and are comparable at a glance |
| **size + ⌫** — far right | `412 KB`, and the delete affordance **only on rows that can be deleted** |

The topic is *not* repeated as a badge when the meta line already carries it — `Music · 4 min`
next to a badge reading `MUSIC` is noise, so the badge went and the topic moved into the quiet
line. **Two rows that differ only in a state word must not look different.**

#### Finding an old article again

| Control | Question it answers |
|---|---|
| **Search** `#libQ` | *"which one was that about…?"* — matches title **and** topic, so `pointer`, `NVDA` and `music` all find things |
| **Worth reading again** `reads ≥ 2` | *"what do I keep going back to?"* |
| **Never read** `reads == 0` | *"what is still waiting for me?"* |
| **Heard but not read** `reads == 0 && listens > 0` | *"what have I only skimmed on the commute?"* |
| **Deleted** `gone` | *"what did I free, and how much?"* — see §4e |
| **All** | everything |

Rows sort **live rows first**, then by `reads + listens` descending, so the articles that actually
occupied your attention float to the top without any extra control — and a deleted row keeps its
rank among its own kind instead of being dumped at the bottom.

#### Reopening an archived article

Tapping a row that is **not** in the queue opens it as a read, with:

* a banner — `from your library` + the title — so you always know why this article has no card;
* the back button retargeted to **`‹ Library`** instead of `‹ Queue`, so leaving an old article
  returns to the shelf and not to the three;
* **both counters still live** — you can count another read and listen again, and the toast says
  `✓ read 3× · still in your library`;
* the queue untouched. Reading an archived article does not promote it back into the queue.

Leaving the article screen for any reason clears the library context, so the banner and the
retargeted back button can never leak into the ordinary queue flow.

### No night, no day
There is **no night mode and no morning mode** anywhere in the app. Reading and listening are two
functions with two buttons; which one you use, and when, is yours. (The prototype's Dark/Light
switch is chrome on the demo page, not part of the app.)

The word sheet ends with **★ I want to see this word again** instead of *Already know /
Save for review*. That is the only explicit input the app asks you for — and it is a wish, not a
self-assessment.

---

## 4c. Topics — one plan, three slots

The requirement was three things at once: flexible enough to take **a very detailed request**,
able to run on its own if the user **does nothing**, and cheap enough that **rework is rare**.
Those pull in different directions, so they are separated into three layers.

### Layer 1 — the Plan (written once, read every time)

> **Changed in v9.** This used to be one free-text box holding a paragraph. It is now a
> **structured object** — seven named fields — because *"your plan is a blob of prose* cannot be
> pointed at, cannot be diffed, and cannot be rewritten field by field. The moment the LLM is
> allowed to edit it, prose stops being a workable format.

The plan is read before **every** article, so **detail here costs nothing per article** — it rides
along in the same call. This is still the single cheapest place to express intent.

```jsonc
// settings.json → queue.plan
{
  "reader": "software developer, comfortable with code, new to finance English",
  "topics": ["C language", "NVDA"],
  "avoid": ["three paragraphs of background before the point",
            "explanations of things I already know"],
  "style": ["start with the thing itself", "short sentences", "say it once"],
  "gloss": ["finance words", "anything where a wrong guess would be embarrassing"],
  "length": 300,
  "marked": 6,
  "raw":   "I read software-dev blogs and I am following NVDA. …"
}
```

| Field | Kind | What it decides |
|---|---|---|
| `reader` | text | **the vocabulary ceiling** — what may be assumed known |
| `topics` | list | where articles may come from |
| `style` | list | how it should read |
| `gloss` | list | which words get the plain-language treatment (§4b) |
| `avoid` | list | **what to hold back** — the rules that stop a fluent-but-wrong draft |
| `length` | number | words per article |
| `marked` | number | words marked at most |
| `raw` | text | **your own words, verbatim** |

Two of these carry more weight than they look:

- **`reader` is the ceiling.** Every other field says what to *do*; this one says what may be
  *assumed*. It is why "explain any finance word" and "never explain C basics" can both be true
  at once, which a single paragraph cannot express without one clause cancelling the other.
- **`avoid` is the negative space.** The failure mode of a fluent model is not saying too little,
  it is saying too much of the wrong thing. `avoid` is the only field that can stop it.

#### `raw` is never dropped

The named fields are what the UI can show and rewrite. But a user may want to say something no
field holds, so **`raw` is kept exactly as typed and appended to the writer prompt verbatim**,
after the structured fields. Ask-the-AI edits fields; it does not eat `raw`. Nothing the user
typed is ever silently discarded.

#### How it renders

Seven rows, each **a mono label and a serif value** — a list field shows its items as tags, a
number shows the number with its hint inline, and an empty field says *nothing yet* / *not set —
the app decides* rather than showing a blank. Plus a final **Your words** row that only appears
when `raw` is non-empty, so the free text is visibly *additional*, never *the plan*.

Settings → *What you read* therefore has **no textarea at all**: it renders the plan, and offers
**✦ Ask the AI to change it** (costs one call) or **Write it myself** (free).

### Layer 1b — Ask the AI to change it

> The requirement: *make the configuration in "What you read" writable **or polishable by the
> LLM** — just the same LLM which is used to generate articles — and before generating, give the
> user an input window to write some prompt, **plus default prompts to demonstrate what to
> write**.*

So the user does not learn a JSON schema. They say a sentence, and the **same writer**, on the
**same active endpoint**, on the **same `/responses` shape** they already configured for
articles, turns it into a proposed plan.

| Step | What happens | Cost |
|---|---|---|
| open the sheet | empty box + **six example prompts**, tappable | free |
| tap an example | it **appends** to whatever you already typed, then you keep writing | free |
| the spec block | *who reads it · endpoint · what changes · cost* — shown **before** you spend | free |
| **✦ Rewrite my plan** | one call to the writer | **~$0.002 · ~15 s** |
| the result | a **diff**: every changed field, `was` struck through, `→ now` in jade | free |
| **Use this plan** / **Keep my plan as it is** | commit, or discard | free |

Four decisions inside that table, each one earned:

1. **The examples are real prompts, not labels.** *Stop explaining C basics — I know pointers*,
   *Any finance word must be explained like I'm new to it*, *Never start with background*,
   *Add lo-fi and ambient music*, *Longer articles, around 500 words*. An empty box with a
   placeholder teaches nothing; a tappable sentence teaches by example. They **append** rather
   than replace, so two can be combined into one request.
2. **The diff is not optional.** *"Your plan changed"* is a claim, and **a claim you cannot see is
   the same thing this whole project exists to avoid** — the same reason tapping a word shows the
   English gloss before the Chinese. The proposed plan is held in `kNext` and **nothing is written
   until Use this plan**.
3. **The scrim refuses to dismiss while a rewrite is pending** (`SCRIM.dataset.locked`). You may
   swipe away a blank sheet; you may not discard a paid-for result by tapping outside it.
4. **Typing again invalidates the diff** (`kNext=null`), because a diff for a request you have
   edited is a lie about what you asked.

**Your plan only — articles already written stay.** Rewriting the plan must not touch, invalidate
or regenerate anything already on the phone. That line is stated in the spec block, in the UI,
before the call.

> In the prototype this is `fakeRewrite(q)` — the exact seam where the real
> `POST {base}/responses` call goes. It applies keyword rules to the plan and returns a diff.

### Layer 2 — the three cards (the queue has exactly three)

> **The Auto / Pinned / One-off slot modes have been removed.** See §4d.

A card is not configured by a mode; it is *written* or *planned*, and that is the only distinction
that matters (see §4, "Two states per slot, and only two"). Where a slot mode used to live, the
"What you read" pane now carries a **three-row explanation instead of a control**:

| If you want to… | Do this |
|---|---|
| change one right now | tap the topic pill on its card |
| change the next one | **Change the plan**, on its card |
| change nothing | **↻ Give me a different one** |

Three ways to act, and no fourth control to understand.

### Layer 3 — the focus (generated, shown, editable)

> **A focus is the lens the topic is written through.** Same topic + different focus = a
> genuinely different article. "Pointers" written as *why they trip beginners up* and as *a bug
> they cause in real code* share no sentences. Empty → the app picks a focus it has not used on
> that topic yet, which is what makes **write again** a new piece rather than a reroll.

Each build picks one: *why it trips beginners up*, *the one-line mental model*, *a bug it causes in
real code*… Used focuses are remembered per topic so the same article is not written twice.

It was called "angle" and nobody knew what it meant. **If a word has to be explained in the UI, the
concept is not finished** — so it is now "the focus", with a one-sentence plain explanation
directly under the field, and a worked example in the sheet.

### Presets are yours to edit

The topic chips and focus chips offered in the spec sheet are a plain editable list in
Settings → Topics:

- **✕ on any chip** removes it everywhere, immediately. Delete what you never tap.
- **+ Add a topic / + Add a focus** appends whatever you type; it appears in the spec sheet on the
  next open.
- No nesting, no categories, no enable/disable. It is a list, because it is used like a list.

Defaults ship as: topics `C language · NVDA · Music · Git · Reading`, focuses
`why it trips beginners up · the one-line mental model · what the machine actually does ·
a bug it causes in real code · the mistake everyone makes once`. Stored in
`settings.json → topics.presets`.

### The plan sheet — deliberately almost empty

It has **two inputs, one block of numbers, three buttons**. That is the whole screen.

| On the sheet | Why it is there |
|---|---|
| What it is about | the only thing you usually want to change |
| The focus *(optional)* | empty → the app picks one it has not used on this topic |
| Topic / Focus / Length / Voice / **Cost** | the cost line is the only reason to look |
| **Write it · ~25 s** | the one thing that spends money |
| **Give me a different one** | zero input, zero cost — see above |
| **Not now** | leaving is a legitimate answer |

Removed from the v6 version: a six-row spec table, a second heading, a paragraph explaining what
a focus is, and a separate cancel/confirm pair. Each of those was defending a decision the user
did not need to defend. **The test for a screen like this: if it needs explaining before it can be
used, it is the wrong screen.**

### Why this does not waste money

The expensive step is always preceded by a free one.

1. **Plan before prose.** A plan is free, instant and rerollable; only **Write it** costs a call.
   Iterating on the cheap artefact is the whole trick — and because `reroll` is free, iterating is
   always the cheaper option, which is exactly the behaviour the cost rule wants to encourage.
2. **The Plan is free to edit** and is read at build time, so tuning it never triggers a rebuild.
3. **Changing a slot does not touch existing articles.**
4. **Regenerate = new focus, same topic**, which is far more likely to land than a new topic.
   The spec sheet pre-fills a focus this topic has not been used with, so a reroll is never a
   reroll.
5. **Done with it is the only destructive act**, and it installs a **plan** — never a call.
6. **The cost of a rebuild is displayed** where you decide, not hidden in a monthly total.

### State machine

```
queue.size == 3                      invariant, always
slot.state ∈ {planned, ready}        never anything else

  reached the end + tap          →  slot.reads++         (article stays; mark re-arms)
  press play                      →  slot.listens++       (never touches reads)

  autofill()                       →  if any planned: STOP
                                   →  else: fill empty slots with plans (free)

  write_it(i)                      →  planned → ready       ONE call, ~$0.002
  reroll(i)                        →  a new plan            ZERO calls, $0.00
  edit_plan(i)                     →  a new plan            ZERO calls, $0.00
  done_with(i)                     →  ready → planned       ZERO calls, $0.00
                                   →  LEDGER[title] ||= {reads, listens}   ← it becomes
                                                                        a library row
  regenerate(i)                    →  plan sheet → write    ONE call

  open_from_library(title)         →  article screen, banner on, back → ‹ Library
                                   →  reads++ / listens++ still work; queue untouched

  ask_ai(prompt)                  →  kNext = proposed plan      ONE call, ~$0.002
                                   →  NOTHING written until the user accepts
  apply_plan(kNext)                →  PLAN = kNext, kNext = null  ZERO calls
  edit_raw(text)                  →  PLAN.raw = text verbatim    ZERO calls

  free_space(title)               →  GONE[title] = kb            ZERO calls
                                   →  LEDGER[title].kb = 0
                                   →  r and l are NOT touched     ← the whole rule
                                   →  row stays, struck through, marked
                                   →  refused if the card is live in the queue
  open_from_library(title)         →  REFUSED if GONE[title] — no empty article page

  // there is no path where reading alone changes queue.size
  // there is no path that deletes a record — only one that frees bytes
```

> **Two lines carry the design.** `article.reads++` is the only thing a read does, and it does not
> touch the queue — so reading can never remove an article. And `if any planned: STOP` is what
> makes the cost predictable: **the app can never spend money you did not tap for.** An
> implementation that auto-writes on a timer, or refills a "done" slot with an article instead of a
> plan, has broken v7 even though every individual line looks reasonable.
>
> And two lines carry v9: **`kNext` gates the plan rewrite** (a paid-for result is never applied
> without a tap, and never lost to a stray tap outside the sheet) and **`free_space` never writes
> `r` or `l`** (counts are not storage).

---

## 4d. The slot modes are gone — and why

Earlier versions of Settings → *What you read* carried three **SLOT 1 / SLOT 2 / SLOT 3** controls,
each with an **Auto / Pinned / One-off** mode. They are removed: `SLOTS`, `renderSlots()` and the
whole control are gone from the prototype.

**Why they had to go**

1. **They duplicated capability that already exists.** Every queue card already has a topic pill,
   a **Change the plan** button and a **↻ Give me a different one**. *Pinned* is "keep this topic,
   new focus" = reroll. *One-off* is "a request in my own words" = the plan sheet. *Auto* is the
   default state of a card that has nothing on it. Three modes were saying the same thing three
   times in a place you have to go and remember.
2. **They were indexed by position in a queue that is not ordered.** SLOT 1 is "the first of
   three," but the three cards are interchangeable — you read whichever you like, and a finished
   card is replaced by a plan wherever it happens to sit. A control addressed by position on an
   unordered set is a control that will eventually be wrong.
3. **They cost a whole settings card to explain.** The user could not tell what the section was
   for — which is a design failure regardless of how reasonable the feature underneath was.

**What replaced them:** nothing that *does* something — a three-row plain-language explanation
naming the three real controls, and the sentence *"There are no slot numbers to set up."* An
explanation is allowed here precisely because **every row points at a place the finger already
goes.** A row that asked for a value would be a control, and a control is what we just deleted.

> **General rule this produced:** a control that duplicates a gesture available on the object
> itself is worse than no control, because it makes the user reconcile two places instead of one.
> If a *mode* cannot be justified by a decision the user makes with new information, it is not a
> mode — it is a setting to delete.

---

## 4e. Storage — freeing space without losing history

> The requirement: *articles in the library should be deletable to save storage, but **statistical
> data does not need to be cleared**, and you should **mark** the article that had been deleted.
> Saved articles should be marked with their memory consumption.*

### The rule

> ### Counts are not storage.

An article is **text (a few KB) + audio (a few hundred KB)** — audio is ~95% of it. A `reads`/`listens`
counter is **a record of something that happened**. These are different kinds of thing, so they get
different fates:

| | Goes | Stays |
|---|---|---|
| **Free the space** | the text, the audio, the bytes | `reads`, `listens`, the row, the title, the day it appeared in history |

**You read it 5 times. That happened.** Deleting the file does not un-happen it. Losing read
history because you freed 400 KB would be a terrible trade and a stupid bug — so the implementation
touches `kb`, and **must never touch `r` or `l`.**

```js
// the entire deletion, in the prototype
GONE[title] = a.kb;         // bytes freed
if (LEDGER[title]) LEDGER[title].kb = 0;
// a.r and a.l are not read, not written, not reset. Ever.
```

### Storage is shown, so freeing it is a decision and not a guess

| Where | What it says |
|---|---|
| **Library, under the filters** | a bar: `2.2 MB` `of 11.7 MB`, plus `1 deleted · 389 KB freed · their read counts are still counted above` |
| **Every shelf row** | its own size in the right-hand column — `412 KB`, `366 KB`, `344 KB` |
| **Settings → The small print** | `Kept on the phone: 1.8 MB · 389 KB freed`, and `If you delete one → the counts stay` |

The bar and the small-print line are **rendered from the same numbers**, and the library is
re-rendered whenever Settings opens — so the figure is never stale. An article you cannot account
for is an article you will not delete; an article you can see is one you can judge.

### A deleted row stays on the list, marked

It does **not** vanish. It renders **struck through**, in place, with the tag
**`deleted · text and audio removed`**, size shown as `—`, and it keeps sorting **by its real
attention** (`reads + listens`) inside a group that sinks below the live rows. Three deliberate
choices:

1. **It stays visible.** Removing the row would hide the fact that the file is gone, and the user
   would meet an article they remember with no explanation.
2. **It keeps its place by attention.** *You did not delete it because it stopped mattering, and
   the list must not imply that it did.* So sorting is `Number(a.gone) - Number(b.gone)`, then
   attention — live rows first, but a deleted row is never demoted below a less-read live one
   arbitrarily.
3. **It is counted in *Most revisited* forever.** That is the whole point of the rule.

A fifth filter, **Deleted**, isolates them, so the marked state is also a way to *browse* rather
than only to apologise.

### Deletion is guarded in three places

Deleting is destructive, and the two cases where it would be wrong are blocked **three times each**
— because a guard in one layer is a guard that the next refactor will move.

| Guard | Where |
|---|---|
| **A live queue card cannot be deleted** | no ⌫ rendered at all (`a.gone\|\|a.live` → no button); `confirmFree()` returns early with `that one is in your queue — Done with it first`; the confirm handler re-checks `a.live` |
| **A deleted article cannot be opened** | `openFromLibrary()` returns on `GONE[title]`; the row click handler returns on `.gone`; the row is visually inert (no hover, default cursor) |

Opening a deleted article would land you on an **empty article page** — a screen that looks broken
and cannot be repaired from where you are. Instead: *its text and audio were freed · write it again
if you want it back.* And **write it again** is one tap, because the plan and the topic are still
there. That is what makes deletion safe: **it is reversible, at a price, and the price is stated.**

### The confirmation states the trade before it happens

Two colour-coded columns, and one sentence that uses the reader's own numbers:

```
  GOES                          STAYS
  the text                      read 2×
  the audio                     heard 1×
  389 KB freed                  it stays on this list, marked as deleted

  You read it 2×. That happened, and it is still counted in your
  history and in Most revisited after this. Only the file goes.
  If you want it back, it is one Write it again.
```

> **A destructive action must state what goes and what stays, before it happens.** "Delete" alone
> would be a lie of omission here, because the user has been told repeatedly that *nothing is ever
> deleted* — and now there is a button that says delete. The sheet is where those two facts are
> reconciled.

### "Won't defecate everywhere" — one day's folder, one file per article

Storage stays bounded because of where files live, not because of a cleanup job:

```
<app>/files/<YYYY-MM-DD>/<article_id>.json     the text
<app>/files/<YYYY-MM-DD>/<article_id>.wav      the audio
<app>/files/<YYYY-MM-DD>/<article_id>.words.json  per-word glosses
<app>/db/no-stop.db                            counters, history, plan
<app>/dict/ecdict.db                           the offline dictionary (once, shared)
```

- **One folder per day, three files per article** — no per-word files, no temp files, no
  `cache_1`, `cache_2`, no orphan `.tmp`. Wiping a day is one directory removal.
- **The dictionary is shared and never copied per article.** 851 MB, fetched once.
- **Audio is generated per article, then owned by it.** Freeing an article removes exactly its
  folder's files; nothing else is touched, so there is no reference counting and no way to orphan.
- **The budget is stated** (11.7 MB ≈ 35 articles) so the ceiling is a number the user can plan
  around, not a surprise.

---

## 5. Cost

| Part | Choice | Monthly |
|---|---|---|
| 1 article/day | LLM + web search, cheap model | $0.05 – 1 |
| Gloss + sentence translation | 1 batch call/article | included |
| Rewrites after a topic change | rare — a few a month | < $0.05 |
| Dictionary for every word | ECDICT, offline, 770k entries | $0 |
| Article + sentence audio | MiMo TTS (currently free, no quota) | $0 |
| Word audio | on-device `flutter_tts` | $0 |
| Compute | GitHub Actions free tier (~60 of 2,000 min) | $0 |
| Hosting / sync | GitHub Releases | $0 |
| **Total** | | **≈ $0 – 1.5 / month** |

Dropping spaced repetition also removed a scheduled-review table, a card state machine and a
daily-cron duplicate. Less code, less storage, fewer bugs.

## 4b. Two kinds of gloss, deliberately different

| Where | What you get |
|---|---|
| Reading, tapping an amber word | a short **English** definition written for *that sentence* — LLM, ~1 call a day |
| Words tab, or tapping any word | the **full dictionary entry** from ECDICT — every sense, **computing sense first** |

ECDICT has an `audio` column and it is **empty** for essentially every entry, which settles word
pronunciation: it has to be on-device TTS. That is fine — it is free.

### The dictionary is now real

ECDICT is downloaded and working: **3.4 M entries**, 851 MB on disk, opened read-only.
The first build produced **141 glosses across 86 distinct words** — every word in the article.

Its raw output is a dictionary dump, so the cleaner sorts the `[计]` computing sense first.
*address* now reads `[计] 地址, 寻址；住址, 演说…` instead of leading with 住址, 演说, 举止, 求爱.

If you ever want literally **zero** cost, run a local model (Ollama) on your own machine and drop
the API bill to nothing — the trade-off is it only runs when that machine is awake.

---

## 6. Pipeline

```
nightly, or on star / topic change (debounced 60s, max 3/day)
  planner   → topic for date D
  selector  → top 30 crucial words by decayed weight
  writer    → LLM + web search → 250–450 words · 94–96% known · uses 4–6 crucial words
  profiler  → lemmatise, mark amber / blue
  glosser   → ECDICT entry + A2 simplification of the English definition
  speaker   → TTS backend (MiMo · the only online engine) · per-sentence audio
  packager  → day-2026-10-07.zip → GitHub Release
```

---

## 7. Build order

| M | Deliverable |
|---|---|
| M1 | **Pipeline only** — the writer against the golden set, glosses, translations, audio, crucial-word selector. **The only blocker.** |
| M2 | Flutter shell: Queue + Article(Read) + Settings (writer endpoints, MiMo voice, plan/slots/presets) + offline package load |
| M3 | Listen mode with **⏮ ▶ ⏭** + lock-screen controls; `listens++` |
| M4 | History: per-article `reads`/`listens` per day, day totals, Most revisited |
| M5 | Words tab with crucial weights + word/sentence audio |
| M6 | **Done with it** → immediate replacement, so `queue.size == 3` survives a real delete |

M3 and M4 are separated on purpose: the player is a reading tool, the ledger is a reporting tool,
and merging them hides both.

---

## 8. Visual system (v4 — Impeccable pass)

**Direction: a paperback under a warm desk lamp.** Not Duolingo green, not AI purple-blue,
not neon-on-dark. A book someone annotated for you with a vermilion pencil.

| Token | Value |
|---|---|
| Neutrals | warm ink / warm paper in **OKLCH**, tinted, never `#000`/`#fff` |
| Vermilion `~30%` | primary action, star, weight bar, the *new-word* pencil rule |
| Jade | "written, on your phone", "met before" |
| Lamp amber | "still writing", night glow, warnings |
| Serif | **Newsreader** (optical size) — anything you *read*: article, lemma, titles |
| Sans | **Schibsted Grotesk** — anything you *operate*: buttons, labels, chips |
| Mono | **IBM Plex Mono** — IPA, timestamps, API keys, counts |
| Motion | 100 / 300 / 500 ms, `cubic-bezier(.16,1,.3,1)`, transform + opacity only |

One warm, low-glare surface. Two, if you ever want a bright one — but **neither is a schedule**:
there is no night mode and no morning mode, and the app draws no conclusion from the hour.

| | **Ink** |
|---|---|
| `--paper` | `oklch(21% .018 66)` |
| `--ink` | `oklch(94% .012 84)` |
| feel | low glare, warm |

Details that carry the personality: **paper grain** over the whole page (SVG turbulence at 5%),
**hairline rules** instead of card-in-card, **hatched** weight bars (an engraved bar, not a
gradient), a thin **vermilion pencil rule** under unknown words instead of a highlighter block,
and a bottom-nav indicator that slides on `transform` only. `prefers-reduced-motion` is honoured.

Settings lives behind a **gear on the Queue screen** — not a fifth tab, because you asked for
fewer entries, not more. It is one flat screen: five sections, no sub-menus, no dropdowns.
There is **no Appearance section** — that was the night/day design, and it is gone.

---

## 9a. Settings is a hub, not a scroll

The v6 Settings screen was one page holding, in order: writer endpoints, a test button, the plan,
three slots, preset chips, cost figures, MiMo fields, the voice list, a probe, word pronunciation,
and housekeeping numbers. It needed scrolling, and scrolling is how a frequently-tuned control
ends up hiding behind a never-touched one.

v7 splits it into a **hub of four panes**, ordered by how often they are touched:

| Row | Contains | How often |
|---|---|---|
| **What you read** | the structured plan, Ask-the-AI, preset chips | often — this is what you tune |
| **Voice** | MiMo engine, style, voice list, probe | occasionally |
| **Who writes the articles** | endpoint list, active switch, test | once, then never |
| **The small print** | cost, storage, dictionary, word pronunciation | almost never |

Two rules make it work:

1. **The hub summarises state, so nothing has to be opened to be checked.** Each row shows its
   current value — `MiMo · Chloe · 5/5 voices probed`, `3 endpoints · DeepSeek active`,
   `5 of 7 fields set · 10 preset chips`. The summary is live: probing the voices updates the
   hub row immediately, and because **storage changes when a library row is freed**, the library
   is re-rendered on every open of Settings so *The small print* never quotes a stale figure.
2. **A rarely used function never shares a screen with a commonly used one.** This is the whole
   reason for the split, and it is a stronger rule than "put the important stuff first" — ordering
   alone still makes the small print sit inside the scroll.

Re-entering Settings always lands on the hub, never on the pane you left. A settings screen that
remembers where you were is a settings screen you cannot get out of.

> **What you read** is now the **only** pane with two ways in: **✦ Ask the AI to change it** (one
> call, diff before apply) and **Write it myself** (free). It has no textarea of its own — the plan
> renders as seven labelled rows, so a field can be pointed at instead of re-read inside prose.

> **The small print** gained two honest rows: `Kept on the phone → 1.8 MB · 389 KB freed` and
> `If you delete one → the counts stay`. They are the storage half of §4e, placed where the cost
> figures already were.

---

## 9. Settings — MiMo for voice, a list of `/responses` endpoints for writing

**Voice is MiMo, full stop — and it is the only online engine.** It is entirely free, so it is the
default and there is nothing else to configure. The one other engine is the phone's own, which is
offline and always available. If MiMo has no key, the build degrades to on-device rather than
failing: the article then has no pre-built audio, but every word still has sound.

**The writer is a list, not a choice.** You can add as many model access points as you like and
switch by tapping; only the *active* one is ever called. Every one of them speaks the
same shape and there are no alternatives to configure:

```
POST {base_url}/responses        # the OpenAI Responses API, nothing else
```

| Field | Example |
|---|---|
| Name | `deepseek` |
| Base URL | `https://api.deepseek.com/v1` |
| API key | stored in the Android Keystore / a repo secret — never in the repo |
| Model | `deepseek-chat` |

The UI shows the resolved call under the fields (`POST https://api.deepseek.com/v1/responses`) so
a wrong base URL is visible before you pay for it. Switching endpoints never rewrites anything.

There are exactly two, and no third is planned:

| Engine | Key | Online/offline | Word timing | Cost / month |
|---|---|---|---|---|
| **Xiaomi MiMo** | `MIMO_API_KEY` | **online** — the only one | none — highlighting falls back to the sentence | $0.00 |
| **On-device** | none | offline, airplane mode | none | $0.00 |

Because MiMo is the only online engine, there is **no fallback to configure**. If it is
unreachable the build lands on device: the article simply has no pre-built audio, and every word
still has sound because the phone pronounces it. That is a degradation, not a swap — one fewer
engine to reason about, and no silent substitution between online providers.

Word-level highlighting (karaoke) needs word boundaries, which MiMo does not return. Sentence-level
highlighting is what the app does. If per-word timing ever matters, that is a different engine —
not a setting in this one.

### The voice is chosen from a list that was actually tested

MiMo publishes **no `/v1/audio/voices` endpoint** — its TTS runs through chat completions, and
there is nothing to list. A hard-coded list of nine names is a guess: a voice can be retired,
renamed, or gated, and you would find out halfway through an article. So the list is **probed**:

```
Probe all →  for each English voice: one tiny synthesis ("Hi.")
             ✓ works / ✕ failed, cached with a timestamp
```

The article is then read with **the first English voice that answered**. Pick one by hand and it
stays picked; if it ever fails during a build, the app moves to the next working one and remembers
the failure. The same resolved voice is used when the article audio is built, so what you hear
matches what you read.

| Voice | Language | Notes |
|---|---|---|
| `Chloe`, `Mia`, `Milo`, `Dean` | en-US | the preset English voices |
| `mimo_default` | en-US | MiMo's own default |
| `冰糖`, `茉莉`, `苏打`, `白桦` | zh-CN | shown, but never auto-picked for this app |

**How it should sound** is a plain sentence, not a setting. MiMo takes the style direction in the
`user` message and the text to speak in the `assistant` message — getting these backwards is the
one easy way to break it:

```json
{ "model": "mimo-v2.5-tts",
  "messages": [{"role":"user","content":"Neutral American newsreader. Unhurried, clear consonants."},
               {"role":"assistant","content":"<the article>"}],
  "audio": {"format":"wav","voice":"Chloe"} }
```

`python3 tts.py --probe-voices` runs it for real and writes the results into `settings.json`.

**American English only, everywhere**: US spelling, US usage, US IPA, and en-US voices
(Aria / Guy / Jenny / Andrew; Chloe / Mia / Milo / Dean). The Housekeeping row states it so it
cannot be forgotten later.

### Single words

**On-device, free, offline** by default — ECDICT's `audio` column is empty, so there is no
other free route. Switching to "same voice as the article" costs a small call per word.

### Cost card (live)

Recomputes as you tap: writer $0.00 without a key, voice by provider, words by choice,
ECDICT $0.00. Keys stay in the **Android Keystore** and go only to the base URL you typed;
the nightly build runs on your machine or in GitHub Actions secrets. There is no server.

### Code side

`pipeline/tts.py` implements the four backends behind one call
(`synthesize(text, path, provider=...)` → `(word_boundaries, nbytes)`), configured by
`pipeline/settings.json` (`settings.example.json` documents every field). `python3.11 tts.py`
probes every voice and prints the monthly estimate — the CLI twin of "Probe all" and "Test voice"
in the prototype. `build.py --tts mimo|device` picks one for a single run and **reports the engine
that actually ran**, because a missing MiMo key silently becomes on-device.

Multiple articles per day are already in the plan model: `planner.tasks_for(date, overrides)`
returns a **list** of topics for a day, `build_window.py` builds each one
(`out/<date>/taskN/`), and `settings.json → topics.extra` can add articles to a date without
touching the rotation.

---

## 10. The writer prompt — the part that must not be rushed

> **This section is the product.** The app never asks "do you know this?", so the *only* thing
> standing between a smooth read and a frustrating one is whether the writer marks the right
> words. Mark too many and the page turns into a field of red pencil — reading stops being
> reading. Mark too few and the reader hits a wall mid-sentence. Mark the wrong *kind* and the
> gloss answers a question the reader did not have.
> The prompt below is a **draft to be validated**, not a finished thing. Do not wire it in and
> move on.

### Two tiers, deliberately different

| | **unfamiliar** (生词) | **difficult** (难词) |
|---|---|---|
| Meaning | the word itself is outside the reader's vocabulary | the word is probably known, but **this sentence** is not |
| Trigger | lemma outside the reader's pool | known lemma used in a secondary sense, idiom, phrasal verb, or technical re-use |
| Example | *dereference* | *since* (= because, not 从那以后) · *block* (of memory) · *leak* |
| Reader gets | a one-line **English** definition in *simpler* words, then 中文 behind a tap | "**here it means X, not Y**" — the trap, in terms of this sentence |

The distinction matters because the two need opposite treatments. An unfamiliar word needs a
definition. A difficult word needs a **contrast** — defining it is useless, because the reader
already knows the common sense and the sentence still does not parse. Both tiers get 中文, but
for `difficult` the Chinese must explain the *usage*, not translate the word.

### Inputs the prompt must receive

1. **The reader's pool** — the top-N frequency list (starts at 500, grows with the Day-0
   placement check), everything ever seen, and the crucial list with weights. This is what makes
   "unfamiliar" a fact rather than a guess.
2. The topic, the length budget, and the crucial words to seed (with weights — the heaviest must
   appear at least once).
3. Nothing else. The writer does not get the reader's history in prose; it gets the pool as data.

### Hard rules (draft v1)

1. **Budget: at most 1 mark per 25 running words** (≈12 in a 300-word article). Density beats
   completeness. Over budget → drop the lowest-value marks.
2. **First occurrence only.** A word met twice in one article is marked once.
3. **Never mark** proper nouns, numbers, code identifiers, or anything in the top-500 unless it
   is a `difficult` usage.
4. An `unfamiliar` definition must be **simpler than the word**: A2 vocabulary, ≤ 12 words, never
   the word itself, never a synonym rarer than the word. If you cannot define it more simply,
   **rewrite the sentence without that word** — that is the correct answer, not a worse gloss.
5. A `difficult` explanation must name the actual trap and refer to *this* sentence
   ("here it means because, not from that time"), never a generic dictionary line.
6. **American English only** — spelling, usage, examples, IPA. No British-only senses.
7. **Zero marks is a valid answer.** Never pad to look thorough.
8. Marks are annotations. The article must read perfectly if every mark is ignored — a mark may
   never be required to understand the sentence (that is what rewriting is for).

### Output contract (strict JSON, no prose)

```json
{"title": "…",
 "sentences": [{"i": 0, "en": "…", "cn": "…"}],
 "marks": [
   {"surface": "dereference", "lemma": "dereference", "sentence": 3,
    "tier": "unfamiliar",
    "en": "to follow a pointer and read the value it points at",
    "cn": "解引用：顺着指针读取它所指向的值"},
   {"surface": "since", "lemma": "since", "sentence": 5,
    "tier": "difficult",
    "why": "here it means 'because', not 'from that time'",
    "cn": "这里是『因为』，不是『自从』"}]}
```

`en`/`why`/`cn` are written by the model in the same call — no second pass, no extra cost.

### Acceptance criteria — a prompt is "done" only when all of these pass

1. **Golden set**: the hand-labelled fixture article plus three more on other topics. Tier
   agreement with hand labels ≥ 90%; mark / don't-mark agreement ≥ 95%.
2. **Simpler-than check** (mechanical): no `unfamiliar.en` contains a word in a *higher*
   frequency band than the word being defined (`wordfreq` zipf).
3. **Budget check** (mechanical): ≤ 1 mark per 25 running words in every golden article.
4. **A cold read by you**: if you tapped more than ~10 times in one article, the density is
   wrong — tighten the budget, do not tune the wording.
5. **Regression**: every prompt change re-runs the golden set. The prompt is versioned
   (`PROMPT_V1`, `PROMPT_V2`, …) and the golden results are stored next to it.

### Draft prompt (v1 — unvalidated)

```text
SYSTEM
You write one short English article a day for one specific reader: a Chinese software
developer who is a beginner reader of English. Everything you output is American
English — spelling, usage, examples.

READER
- Known vocabulary: roughly the {{known_top}} most frequent English words, plus every
  lemma in KNOWN. Anything outside that pool is a candidate for tier "unfamiliar".
- KNOWN: {{known_lemmas}}
- CRUCIAL (word: weight): {{crucial}}   — the heaviest ones must appear, naturally,
  at least once each. Never define them inside the text; the app does that.

TASK
1. Write {{min_words}}–{{max_words}} words about TOPIC: {{topic}}. CEFR-A2 grammar.
   Short declarative sentences, average under 16 words, one idea per sentence.
2. Mark words afterwards, as an editor with one red pencil and a strict budget:
   at most {{budget}} marks in the whole article.

MARKING
- tier "unfamiliar": the lemma is outside the reader's pool. "en" = a one-line
  definition in words SIMPLER than the word (≤ 12 words, A2 vocabulary, never the
  word itself, never a rarer synonym). If you cannot define it more simply, rewrite
  the sentence without that word and do not mark it.
- tier "difficult": the lemma IS in the reader's pool, but this sentence will trip
  him — a secondary sense, an idiom, a phrasal verb, a fixed technical phrase.
  "why" = the trap, in terms of THIS sentence ("here it means because, not from
  that time"). "cn" = what the sentence means, not a translation of the word.
- First occurrence only. Never proper nouns, numbers, or code.
- Zero marks is an acceptable answer. Never pad.
- The article must read perfectly with every mark ignored.

OUTPUT
JSON only, exactly this shape, no commentary:
{"title": str, "sentences": [{"i": int, "en": str, "cn": str}],
 "marks": [{"surface": str, "lemma": str, "sentence": int,
            "tier": "unfamiliar"|"difficult",
            "en": str, "why": str, "cn": str}]}
```

---

## 11. Decided — 2026-10-06

You did not need to answer these to get a working app, so they are decided **and** they are
settings. Nothing here is locked in.

| Question | Decision | Why | How to change |
|---|---|---|---|
| LLM call shape | **`POST {base}/responses`** — OpenAI Responses API, no alternative | One shape to support, any provider that speaks it | Settings → Writer · add as many as you like |
| TTS engine | **MiMo is the only online engine**; on-device is the only offline one | Free, and there is nothing else to configure | nothing to switch — by design |
| Which voice reads | **Auto — the first en-US voice that answered a probe** | MiMo has no voice-list endpoint; guessing is how a retired voice breaks a build | Settings → Voice → Probe all, or `voice_pick` |
| How many wait | **Three slots, always** | No plan to maintain, no empty morning | `settings.json → queue.size` |
| Slot states | **Exactly two — `planned` and `ready`** | A slot holding a plan and a slot holding an article are different facts | — |
| When the app may write | **Only when every slot is `ready` and you tapped Write it** | An unplanned $0.002 charge must be impossible | — |
| What "Done with it" leaves | **A plan, not an article** — and a **library row** | The next thing should also wait for you, and the article must not vanish | — |
| Reroll | **On the card and in the sheet** — random, zero input, $0.00 | "Show me another" must not require a decision first | `.reroll` |
| Plan sheet | **Two fields, one cost line, three buttons** | If a screen needs explaining before use, it is the wrong screen | `nsheet` |
| Cost row in the sheet | **Says `free` whenever nothing will be written** — plan edit and Done-with-it both write nothing | A "$0.002" shown next to an action that spends $0 is a lie the user plans around | `paintSpec()` |
| Settings shape | **Hub of four panes, live summaries** | A rare function must not share a screen with a common one | — |
| Slot modes (Auto/Pinned/One-off) | **Removed** | They duplicated gestures the card already has, and were indexed by position in an unordered queue | — |
| Where the topic can be changed | **On the card** — topic pill, Change the plan, ↻ reroll | A setting that duplicates a gesture on the object is worse than no setting | — |
| Archive | **The Library** — queue is three, library is everything, **nothing is ever deleted** | You cannot re-read what no longer exists | `shelf()` |
| Library list storage | **Derived: `LEDGER ∪ QUEUE`** — no second table | No second copy of the truth to fall out of sync | `shelf()` |
| Finding an old article | **Search by title or topic, plus 4 filters** | "Which one was that about?" is the actual question | Library screen |
| Opening an archived article | **Banner on, back becomes `‹ Library`, both counters still work** | An old article must never be a dead end | `openFromLibrary()` |
| What a read does | **`reads++`, and nothing else** — the article stays | One read-through is not being done with an article | — |
| Hearing | **`listens++` only** — never touches `reads`, never needs a mark | Listening is practice, not a checkpoint | — |
| Calendar | **History only** — no future, nothing to plan | Planning ahead was the most complex part and the least used | — |
| History detail | **Per article** — which ones, `read N×`, `heard M×`, plus **Most revisited** | "Read 1 thing 5×" and "read 5 things once" are different days | — |
| Player | **⏮ ▶ ⏭** — step one line back or forward, playback continues | One sentence that did not land should not cost you the rest | — |
| Topics | **One plan (free text) + three cards** (each ready or planned) | Detailed when you want detail, random when you do not | Settings → What you read |
| Presets | **A plain editable chip list** — ✕ to delete, + to add | It is used like a list, so it is built like a list | Settings → Topics → Presets |
| Before any build | **A one-line spec** — topic, focus, length, voice, cost | Editing the spec is free; only building costs | the sheet on write again / change topic / done with it |
| Android | minSdk **26**, target **34** | Covers every phone in use; MediaSession and WorkManager only need 21 | `build.gradle` |
| Stock / music grounding | **NVDA** · **indie rock + lo-fi** | Placeholders so the writer has something real to talk about | the Plan, or `settings.json → topics` |
| English variant | **American only** — spelling, usage, IPA, en-US voices | One variant, no surprises | Housekeeping row in Settings |
| Reading config shape | **A structured object** — `reader · topics · style · gloss · avoid · length · marked`, plus `raw` verbatim | A blob of prose cannot be pointed at, diffed, or rewritten field by field — and the LLM now edits it | `queue.plan` |
| Who polishes the plan | **The same writer, the same `/responses` endpoint, one call** | One model to configure, one bill to watch | `fakeRewrite()` seam |
| Applying a rewrite | **A diff you must accept** (`was` struck → `→ now`), `kNext` gates the write | A claim you cannot see is what this whole project exists to avoid | `ksheet` |
| Plan-edit examples | **Six tappable real prompts** that append, not replace | An empty box with a placeholder teaches nothing; a sentence teaches by example | `ASK_EXAMPLES` |
| Freeing storage | **Text + audio go; `reads`/`listens` stay forever** | **Counts are not storage** — deleting a file does not un-happen a reading | `free_space()` |
| A deleted article | **Stays on the shelf, struck through, tagged `deleted`, still in *Most revisited*** | Hiding the row would hide the fact that the file is gone | `gone` |
| Deleting a live queue card | **Blocked** — no ⌫, plus a guard in the confirm handler | You did not free it to free it; it is still waiting to be read | `confirmFree()` |
| Opening a deleted article | **Refused** — says so, and points at **Write it again** | An empty article page looks broken and cannot be repaired from there | `openFromLibrary()` |
| Showing storage | **A bar, per-row KB, and the same figures in The small print** | An article you cannot account for is one you will not free | `renderLib()` |
| Library row shape | **One title line, one quiet meta line, counters in a fixed column, state on the spine** | Six text objects per row is a list you must read, not one you can scan | `renderLib()` |

Single-word pronunciation stays **on-device** in every configuration — ECDICT ships no audio,
and it is the only free, offline route.

There is **no night/day concept left anywhere** — not in the model, not in the UI, not in the
naming. Reading and hearing are the two functions; when you use them is yours.

There is also **no `finished` boolean left anywhere.** It was replaced by two counters in v6,
because "finished" quietly implied you were done with an article and you were not — one read is a
beginning. If an implementation adds a finished flag back, it has undone the v6 change.

And there is **no timer that writes articles.** v6 refilled a dropped slot immediately, which
meant a $0.002 call the user never agreed to. v7 leaves a **plan** instead, and refuses to write
while any plan is waiting. That single rule is the app's cost ceiling.

And there is **no code path anywhere that resets a read count.** v9 added a button that frees an
article's bytes, and the temptation in that code is to reset the row because the article is gone.
**The record is not the file.** If an implementation zeroes `r` or `l` when storage is freed, it has
broken the one rule that makes the history worth keeping.

### History data shape

```jsonc
// one row per day, per article — this is what "which ones?" needs
{"day":"2026-10-03","article_id":"a17","title":"What a Pointer Really Is",
 "reads":1,"listens":3,"minutes":9}

// derived, never stored separately: totals per day, and the "Most revisited" ranking
// LEDGER = Σ over days of (reads, listens) grouped by article_id
```

Storage rule: **the per-day per-article rows are the source of truth.** The day totals and the
revisit ranking are queries over them, never their own table — otherwise they drift.

### What this unlocks

- `pipeline/tts.py --probe-voices` asks every English voice for one word and records what works;
  `resolve_voice()` then reads with the first one that answered, and the failure of a hand-picked
  voice is remembered and moved past.
- `tools/fetch_ecdict.sh` re-fetches the dictionary on a fresh machine.

### Known drift — fix before M2

`pipeline/planner.py` and `pipeline/build_window.py` still build a **rolling 7-day window**, which
is the design this version replaces. They remain useful as a fixture harness
(`build_window.py` renders the hand-written fixtures and reports what it cannot build), but the
real pipeline is now the queue: **build on demand, three in flight, one call per replacement.**
The nightly workflow should become "top the queue back up to three if the writer has a key", not
"pre-build seven days".

The fixture harness also predates the counter model, so `build_window.py` still writes a
per-day `finished` flag. It is fine for fixtures — but the app must never read it.

**M1 is the only blocker**: implement §10 — the writer prompt, the golden set, and the
validation loop. The prompt is a **draft to be validated, not a finished thing** — do not wire it
in and move on. Once it passes the five acceptance criteria, the queue fills itself.

---

## 12. Prototype bugs found while building v9

Recorded because each one is a **class** of bug, not a one-off, and the Flutter app has the same
three hazards.

### 1. A palette scoped to one element made every sheet transparent

`--surface`, `--paper`, `--ink` … were declared on `.phone`. The bottom sheets are children of
`<main>`, which does **not** descend from `.phone`, so every `var(--surface)` in a sheet resolved
to nothing and `backgroundColor` came back `rgba(0,0,0,0)`. Short sheets hid it; the tall
scrolling Ask-AI sheet exposed it.

**Fix:** hoist the palette to `:root, .phone, .viewport`, and mirror the theme onto
`<html data-theme>` so anything outside `.phone` still resolves.

> **Class:** *a design token declared on a subtree is not available outside it.* In Flutter this
> is `Theme.of(context)` reaching for a colour that only exists in a local `TextStyle` — the
> widget compiles and renders transparent. Declare tokens at the app level, always.

### 2. A sheet anchored to the document instead of the phone

`.sheet{position:absolute;bottom:0}` was positioning against `<main>`, which is
`display:grid;align-items:start`, so `bottom:0` fell to the bottom of the grid and the sheet hung
off the page.

**Fix:** the scrim and all sheets now live **inside `.phone`** (`position:relative;overflow:hidden`).

> **Class:** *an absolutely-positioned overlay needs a positioned ancestor it actually shares.*
> Verify the parent chain, not the intent.

### 3. There was no scrim at all

`grep` for `scrim|rgba(0` returned nothing. Every sheet floated over an undimmed page, so a long
scrolling sheet read as broken rather than as an overlay.

**Fix:** a `.scrim` inside `.phone`, driven by a `MutationObserver` on each sheet's `class`, so
the seven call sites that add/remove `"up"` cannot drift out of sync. The scrim **refuses to
dismiss while a plan rewrite is unaccepted** (`SCRIM.dataset.locked`).

> **Class:** *a modal without a backdrop is a rectangle.* And a scrim toggle duplicated across
> every call site is a bug waiting to happen — observe the state, do not restate it.

### Also fixed

- `paintCost is not defined` in the delete handler (the real name is `renderCost()`). The
  `ReferenceError` silently swallowed the toast, which is why the first delete test showed the
  default *✓ saved on this phone*.
- A duplicated `<nav id="nav">` + `<div id="toast">` block, and an unclosed
  `<section class="screen">`, moved every sheet's parent and changed `.phone`'s extent. Found with
  a `HTMLParser` stack walker that reports `MISMATCH closing </div> at line N, unclosed: [...]` —
  **worth keeping as a check**; a stray `</div>` silently re-parents the entire UI.
