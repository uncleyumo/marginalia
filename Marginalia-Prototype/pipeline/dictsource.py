"""Dictionary sources.

ECDICT (free, offline, 770k entries) is the real one. The stub keeps the pipeline
runnable before the dictionary is downloaded.
"""
import json
import os
import re
import sqlite3

HERE = os.path.dirname(__file__)
DATA = os.path.join(HERE, "..", "data")
ECDICT_DB = os.path.join(DATA, "ecdict.db")


def _clean_translation(t):
    """ECDICT gives every sense at once. That is a dictionary dump, not an answer.

    Sort the computing sense first (this is a developer's vocabulary) and keep the
    list short, so 'address' reads '[计] 地址, 寻址' instead of '住址, 演说, 举止, 求爱'.
    """
    if not t:
        return ""
    parts = [p.strip() for p in re.split(r"\n|；|;", t) if p.strip()]
    keep = []
    for p in parts:
        p = re.sub(r"^\W*\w+\.\s*", "", p)
        if p and len(p) < 40:
            keep.append(p)
    keep.sort(key=lambda s: 0 if s.startswith("[计]") else 1)   # computing sense wins
    return "；".join(keep[:3])


def _clean_definition(d):
    if not d:
        return ""
    parts = [p.strip() for p in re.split(r"\n", d) if p.strip()]
    return " ".join(parts[:2])[:240]


class Ecdict:
    def __init__(self, path=ECDICT_DB):
        self.ok = os.path.exists(path)
        self.con = sqlite3.connect(f"file:{path}?mode=ro", uri=True) if self.ok else None

    def lookup(self, word):
        if not self.ok:
            return None
        for w in (word, word.lower()):
            row = self.con.execute(
                "SELECT phonetic, definition, translation, pos FROM stardict WHERE word=? LIMIT 1",
                (w,)).fetchone()
            if row:
                break
        if not row:
            return None
        pho, dfn, trans, pos = row
        return {"ipa": pho or "", "pos": pos or "",
                "en": _clean_definition(dfn), "cn": _clean_translation(trans)}


class Stub:
    def __init__(self):
        with open(os.path.join(HERE, "stub_dict.json")) as f:
            self.tbl = json.load(f)

    def lookup(self, word):
        return self.tbl.get(word.lower())


def get():
    return Ecdict() if os.path.exists(ECDICT_DB) else Stub()
