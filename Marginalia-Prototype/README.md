# Marginalia — English, annotated as you read it

> **Offline-first English reader for Android.** Three articles are always waiting. Read them
> whenever you like — there is no schedule, no streak, and no verdict.
> **Flutter · Android only · American English · MiMo is the only online TTS engine.**

---

## Start here

| If you want… | Open |
|---|---|
| **see it working** | `prototype/prototype.html` — open in any browser, no server, no network. It is the whole app. |
| **build it** | `docs/DESIGN.md` — the system design, v9. It is the source of truth. |
| **keep the visuals consistent** | `docs/impeccable-design-context.md` — the design system rules. Read before changing any screen. |
| **wire up voice** | `pipeline/tts.py` — MiMo + on-device only. Run `python3 tts.py --probe-voices` once. |
| **configure** | `pipeline/settings.example.json` — copy to `settings.json`, fill in what you use. Every field is optional. |

---

## What this app is

The core loop: **three articles are always ready.** No day-planning, no "today's task", no
marking things done. Read on the couch, hear on the bus.

The two ideas that carry the whole design:

**1. It records, it never judges.** There is no button anywhere that asks whether you remember a
word, and no progress ring claiming you have "learned N words". Words you tap get *heavier* in a
pool; they do not get scheduled. `read 3×` and `heard 2×` are the strongest claims the UI is
allowed to make about you.

**2. English first, always.** Tap any word in any article and you get the **English** gloss plus
sound. Chinese appears only if you tap again — the same rule in the article, the sentence, and the
words list. Looking something up must never mean leaving the page.

---

## The one thing still missing

> ### M1 — the article writer
>
> The prototype fakes article generation. The real one calls **`POST {base_url}/responses`**
> (OpenAI Responses API) — the draft prompt is **§10 of `docs/DESIGN.md`**, and it is a **draft
> to be validated, not a finished thing**. Build the golden-set validation loop first, then write
> articles.
>
> **Do not wire the prompt in and move on.** It has not passed its acceptance criteria yet.

You need one LLM key (DeepSeek is cheapest) and one MiMo key (free). **With no keys at all the app
still works** — on-device voice, offline ECDICT dictionary, $0.00.

---

## Reference

### The five rules an implementation must not break

1. **Three slots, always.** `queue.size == 3` is an invariant.
2. **Two states only:** `planned` / `ready`. If any slot is `planned`, **write nothing and wait** —
   an unplanned $0.002 call must be impossible. This is the app's cost ceiling.
3. **Reading never removes an article.** A read only does `reads++`.
4. **Counts are not storage.** Freeing an article's bytes removes its text and audio and **never**
   its read/heard counters. *You read it five times; that happened.*
5. **No night/day concept**, and **no `finished` boolean**, anywhere.

### Layout

```
docs/DESIGN.md                     system design v9 — the source of truth
docs/impeccable-design-context.md  visual system + design rules
prototype/prototype.html           the working prototype (single file, offline)
pipeline/tts.py                    MiMo (online) + device (offline). No Edge, no Qwen.
pipeline/dictsource.py             ECDICT — the free offline dictionary
pipeline/settings.example.json     all configuration; every field optional
tools/fetch_ecdict.sh              fetch the dictionary on a fresh machine (~851 MB)
```

### What is **not** in this package, and why

| Excluded | Why |
|---|---|
| `data/ecdict.db` (851 MB) | The dictionary. Fetched once via `tools/fetch_ecdict.sh`. Far too large to ship. |
| `out/` (3 MB of built packages) | Output of the **superseded rolling-7-day pipeline**. Design v9 replaced it with the queue. |
| `pipeline/planner.py`, `build_window.py`, `build.py`, `speaker.py`, `packager.py`, `player_template.html`, `nightly.yml` | **Obsolete.** They build a rolling 7-day window and still reference `edge_tts` / `qwen`, both removed. `build_window.py` has some value as a fixture harness; the rest should be deleted rather than ported. |
| `probe.py`, `stub_dict.json`, `fixtures/` | Development scaffolding for the vocabulary-level probe. Not needed to build the app. |
| Screenshots | The prototype is the artefact; screenshots of it add nothing. |

> **Known drift:** `docs/DESIGN.md` → *Known drift* lists what to delete before M2. Trust it over
> anything still sitting in the old repository tree.

---

## Cost

| Operation | Calls | Cost |
|---|---|---|
| Reading, hearing, looking up a word | 0 | **$0.00** |
| Changing the plan by hand | 0 | **$0.00** |
| `↻ Give me a different one` | 0 | **$0.00** |
| **✦ Ask the AI to change it** | 1 | ~$0.002 |
| **Write it** (an article) | 1 | ~$0.002 |
| All TTS (MiMo) | — | free |
| Everything, with no keys at all | — | **$0.00** |