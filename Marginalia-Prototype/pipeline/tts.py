"""Pluggable TTS backends — the code side of the prototype's Settings screen.

The default costs nothing and needs no key.

MiMo is the ONLY online engine, and device is the only offline one. There is
deliberately no third option and no fallback between online providers.

    mimo    Xiaomi MiMo.  OpenAI-compatible: POST {base}/chat/completions with
            messages=[{"role":"user","content":<STYLE>},
                      {"role":"assistant","content":<TEXT TO SPEAK>}] and
            audio={"format":"wav","voice":...}.  The audio comes back base64 in
            choices[0].message.audio.data.  Entirely free right now.
            It publishes NO /voices endpoint, so probe_voices() asks each voice
            for one word and records which ones actually answer.
    device  Nothing is pre-built; the phone's own engine reads single words.
            This is also where the build lands if MiMo has no key — the article
            then has no audio, but every word still has sound.

Neither online backend returns word boundaries, so highlighting is per sentence.
If word-level karaoke ever matters, that needs a different engine — not a
setting in this one.

Config lives in pipeline/settings.json (see settings.example.json).  Every key
is optional; the pipeline works with the file missing entirely.
"""
import base64
import json
import os
import sys
import tempfile
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_PATH = os.path.join(HERE, "settings.json")

DEFAULT_STYLE = ("Neutral American newsreader. Unhurried, clear consonants, "
                 "no drama.")

# The voice catalogue. MiMo publishes NO /v1/audio/voices endpoint — its TTS
# runs through chat completions — so the only way to know which voices actually
# work is to ask each one for a word. That is what probe_voices() does, and the
# result is what the app reads with. Guessing is not good enough: a voice that
# has been retired would silently fail halfway through an article.
VOICES = {
    "mimo": [("Chloe", "en"), ("Mia", "en"), ("Milo", "en"), ("Dean", "en"),
             ("mimo_default", "en"),
             ("冰糖", "zh"), ("茉莉", "zh"), ("苏打", "zh"), ("白桦", "zh")],
    "device": [],
}

DEFAULTS = {
    # The writer is a LIST of access points, not a single choice. Every one of
    # them speaks the same shape — POST {base_url}/responses (OpenAI Responses
    # API) — and only the active one is ever called. Switching is free.
    "writer": {
        "endpoints": [
            {"name": "deepseek", "base_url": "https://api.deepseek.com/v1",
             "api_key": "", "model": "deepseek-chat", "env": "DEEPSEEK_API_KEY"},
        ],
        "active": 0,
    },
    "voice": {
        # MiMo is the engine: it is free, and that is what the user asked for.
        # If its key is missing the pipeline quietly falls back to Edge instead
        # of failing, because Edge needs no key at all.
        "provider": "mimo",
        "words": "device",                 # device | same
        # Which voice reads the article. auto = the first English voice that
        # answered the probe; voice_pick = one chosen by hand. If the chosen
        # voice ever fails, the next working one takes over and the failure is
        # remembered in voice_probe.
        "voice_auto": True,
        "voice_pick": None,
        "voice_probe": {},                 # {voice_id: {"ok": bool, "at": iso}}
        "mimo": {"base_url": "https://api.xiaomimimo.com/v1", "api_key": "",
                 "model": "mimo-v2.5-tts", "voice": "Chloe",
                 "style": DEFAULT_STYLE},
    },
    # What the two vague days are actually about. Change these, not the rotation.
    "topics": {"stock": "NVDA", "music": "indie rock and lo-fi"},
}

ENV_KEYS = {          # never hard-code a key; the environment wins
    "mimo": "MIMO_API_KEY",
}
WRITER_ENV = {        # legacy single-key presets, kept for env-only setups
    "deepseek": "DEEPSEEK_API_KEY",
    "mimo": "MIMO_API_KEY",
    "openai": "OPENAI_API_KEY",
}


def load_settings():
    st = json.loads(json.dumps(DEFAULTS))          # deep copy
    if os.path.exists(SETTINGS_PATH):
        with open(SETTINGS_PATH, encoding="utf-8") as f:
            user = json.load(f)
        for section, values in user.items():
            if isinstance(values, dict) and isinstance(st.get(section), dict):
                for k, v in values.items():
                    if isinstance(v, dict) and isinstance(st[section].get(k), dict):
                        st[section][k].update(v)
                    else:
                        st[section][k] = v
            else:
                st[section] = values
    for prov, env in ENV_KEYS.items():
        if os.environ.get(env):
            st["voice"][prov]["api_key"] = os.environ[env]
    for ep in st["writer"]["endpoints"]:           # per-endpoint env override
        env = ep.get("env")
        if env and os.environ.get(env):
            ep["api_key"] = os.environ[env]
    return st


def active_writer(settings=None):
    """The one access point that will actually be called."""
    st = settings or load_settings()
    eps = st["writer"].get("endpoints") or []
    i = st["writer"].get("active", 0)
    return eps[i] if 0 <= i < len(eps) else (eps[0] if eps else None)


# ---------------------------------------------------------------- mimo
class Mimo:
    name, needs_key, word_timing = "mimo", True, False

    def __init__(self, cfg):
        self.base = cfg["base_url"].rstrip("/")
        self.key = cfg.get("api_key", "")
        self.model = cfg.get("model", "mimo-v2.5-tts")
        self.voice = cfg.get("voice", "Chloe")
        # The style instruction is a plain sentence the user can edit. MiMo
        # reads it as direction, not as text to speak.
        self.style = cfg.get("style") or DEFAULT_STYLE

    def synthesize(self, text, path):
        # MiMo's contract is specific and easy to get wrong:
        #   user      = the STYLE instruction (optional for preset voices)
        #   assistant = the TEXT TO SPEAK — never the user message
        #   audio     = {"format": ..., "voice": <preset id>}
        r = requests.post(
            f"{self.base}/chat/completions",
            headers={"Authorization": f"Bearer {self.key}"},
            json={
                "model": self.model,
                "messages": [
                    {"role": "user", "content": self.style},
                    {"role": "assistant", "content": text},
                ],
                "audio": {"format": "wav", "voice": self.voice},
                "modalities": ["text", "audio"],
            }, timeout=180)
        r.raise_for_status()
        b64 = r.json()["choices"][0]["message"]["audio"]["data"]
        raw = base64.b64decode(b64)
        with open(path, "wb") as f:
            f.write(raw)
        return [], len(raw)                      # no word boundaries available

    def probe(self):
        if not self.key:
            return "no-key", "MIMO_API_KEY is not set"
        return "ok", f"{self.model} · {self.voice}"


# ---------------------------------------------------------------- device
class Device:
    name, needs_key, word_timing = "device", False, False

    def __init__(self, cfg=None):
        pass

    def synthesize(self, text, path):            # nothing to build on the server
        return [], 0

    def probe(self):
        return "ok", "Android TTS, runs on the phone"


# MiMo is the only online engine. Device is the only offline one. There is
# deliberately no third option and no silent swap between online providers.
BACKENDS = {"mimo": Mimo, "device": Device}


# ------------------------------------------------- which voice reads, and why
def _en_voices(provider):
    return [v for v, lang in VOICES.get(provider, []) if lang == "en"]


def resolve_voice(settings=None, provider=None):
    """Return (voice_id, why). 'why' is shown in the build log so a silent
    substitution is never invisible."""
    st = settings or load_settings()
    prov = provider or st["voice"]["provider"]
    probe = st["voice"].get("voice_probe") or {}
    working = [v for v in _en_voices(prov) if (probe.get(v) or {}).get("ok")]
    fallback = _en_voices(prov)[0] if _en_voices(prov) else None
    if st["voice"].get("voice_auto", True):
        if working:
            return working[0], f"auto · 1 of {len(working)} probed English voices"
        return fallback, "auto · nothing probed yet, using the first known voice"
    pick = st["voice"].get("voice_pick")
    if pick and (probe.get(pick) or {}).get("ok") is False:
        return (working[0] if working else fallback), \
               f"auto · {pick} failed last time, moved on"
    return (pick or working[0] if working else pick or fallback), "picked by hand"


def probe_voices(settings=None, provider=None, english_only=True, save=True):
    """Ask every voice for one short utterance and record what came back.

    MiMo has no voice-list endpoint, so this is the only honest source of
    "available voices". One word per voice, and MiMo TTS is currently free.
    """
    st = settings or load_settings()
    prov = provider or st["voice"]["provider"]
    out = {}
    for voice, lang in VOICES.get(prov, []):
        if english_only and lang != "en":
            continue
        cfg = dict(st["voice"].get(prov, {}))
        cfg["voice"] = voice
        try:
            be = BACKENDS[prov](cfg)
            _, nbytes = be.synthesize(
                "Hi.", os.path.join(tempfile.gettempdir(), "_voice_probe.bin"))
            out[voice] = {"ok": bool(nbytes),
                          "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
        except Exception as e:
            out[voice] = {"ok": False, "err": str(e)[:90],
                          "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    if save:
        st["voice"].setdefault("voice_probe", {}).update(out)
        if os.path.exists(SETTINGS_PATH):          # never create one by probing
            with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
                json.dump(st, f, ensure_ascii=False, indent=2)
    return out


def make_backend(settings=None, provider=None, voice=None):
    st = settings or load_settings()
    provider = provider or st["voice"]["provider"]
    if provider not in BACKENDS:
        raise SystemExit(f"unknown TTS provider: {provider}")
    cfg = st["voice"].get(provider, {})
    be = BACKENDS[provider](cfg)
    needs = getattr(be, "needs_key", False)
    if needs and not getattr(be, "key", ""):
        # MiMo is the only online engine, so there is no other online engine to
        # fall back to. Drop to on-device instead: the package still builds, the
        # article just has no pre-built audio, and every word still has sound
        # because the phone pronounces it itself.
        print(f"  [mimo has no key — no article audio this run; "
              f"words still use the on-device engine]", file=sys.stderr)
        provider = "device"
        be = Device()
    chosen, why = (voice, "explicit") if voice else resolve_voice(st, provider)
    if chosen and hasattr(be, "voice"):
        be.voice, be.voice_how = chosen, why
    return be


def synthesize(text, path, provider=None, settings=None):
    """Write audio for text to path. Returns (word_boundaries, nbytes).

    boundaries is [] for every provider except Edge — the pipeline must handle
    that (highlighting degrades to sentence level).
    """
    return make_backend(settings, provider).synthesize(text, path)


# ---------------------------------------------------------------- cost
COST_PER_MONTH = {"mimo": 0.0, "device": 0.0}


def estimate(settings=None):
    """Monthly cost, 30 articles. A writer with no key costs nothing — it simply
    does not run, which is exactly what the Settings screen shows."""
    st = settings or load_settings()
    prov = st["voice"]["provider"]
    words_same = st["voice"].get("words") == "same"
    ep = active_writer(st)
    writer_key = ep and (ep.get("api_key") or "").strip()
    return {
        "writer": 0.05 if writer_key else 0.0,
        "article_voice": COST_PER_MONTH.get(prov, 0.0),
        "single_words": COST_PER_MONTH.get(prov, 0.0) if words_same else 0.0,
    }


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="TTS backends: probe, resolve, cost")
    ap.add_argument("--probe-voices", action="store_true",
                    help="ask every English voice for one word and record it")
    ap.add_argument("--all-languages", action="store_true",
                    help="with --probe-voices, do not skip non-English voices")
    args = ap.parse_args()

    st = load_settings()
    prov = st["voice"]["provider"]
    print(f"  provider   {prov}")
    print(f"  word audio {st['voice']['words']}")

    if args.probe_voices:
        res = probe_voices(st, english_only=not args.all_languages)
        for v, r in res.items():
            mark = "✓ works" if r["ok"] else "✕ failed"
            print(f"    {v:18s} {mark:9s} {r.get('err','')}")
        print()

    voice, why = resolve_voice(st)
    print(f"  voice      {voice}  ({why})")
    for name in ("mimo", "device"):
        be = BACKENDS[name](st["voice"].get(name, {}))
        kind, msg = be.probe()
        t0 = time.time()
        try:
            _, nbytes = be.synthesize("This is a pointer.", "/tmp/_tts_probe.bin") \
                if kind == "ok" and name != "device" else ([], 0)
            print(f"  {name:8s} {kind:7s} {msg:40s} "
                  f"{nbytes/1024:7.1f} KB  {time.time()-t0:5.1f}s")
        except Exception as e:
            print(f"  {name:8s} FAIL    {type(e).__name__}: {str(e)[:60]}")
    c = estimate(st)
    print(f"  estimate  writer ${c['writer']:.2f} + voice ${c['article_voice']:.2f} "
          f"+ words ${c['single_words']:.2f} / month")
