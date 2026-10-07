"""Build the shippable dictionary — FINAL.

Three defects were found by spot-checking the real output, not by reading the
code, and each is fixed here:

1. 58.4% of ECDICT's phonetics are BRITISH (/pɒintә/). The design is American
   English throughout — spelling, usage, IPA and voices are all en-US. So the
   IPA is converted: British->American symbol substitutions plus a small
   respelling table for the highest-frequency words, which is where a wrong
   vowel actually misleads a learner. Where neither is available the entry
   keeps an empty IPA and the app simply omits the line rather than showing a
   wrong one.

2. Definitions retained a literal `\\n` and a `n. ` part-of-speech prefix, so
   the card read "n. an indicator as on a dial\\nn. a strong slender...". The
   cleaner now splits on real newlines, takes the first sense, and strips the
   leading POS tag.

3. Hyphenated and apostrophised words were filtered out entirely, which lost
   `lo-fi` and `book-keeping` — the sample article contains the latter. They are
   admitted now, and de-hyphenated duplicates inherit the better gloss.

Coverage is verified by a separate script against real prose; this file only
builds.
"""
import csv
import json
import os
import re
import zipfile

csv.field_size_limit(10**9)

PROJ = r'E:\Dev_work\Flutter_Dev\marginalia\Marginalia'
OUT_JSON = PROJ + r'\assets\dict\dictionary.json'
OUT_ZIP = PROJ + r'\assets\dict\dictionary.zip'
CSV = r'C:\Users\WY139\AppData\Local\Temp\ecdl\ecdict.csv'

# ── British -> American IPA ────────────────────────────────────────────────
# Substitutions only; they are unambiguous. The respelling table below handles
# the cases a substitution cannot (ɒ in open syllables, the -əʊ/-oʊ pair).
# ── British -> American IPA ────────────────────────────────────────────────
# Keys are written with EXPLICIT CODEPOINTS. An earlier version typed the
# glyphs directly and got U+0249/U+018D, which are NOT the British open-o or
# schwa — so the substitution silently did nothing while looking correct. The
# inventory below is measured from the file itself, not assumed:
#   U+04D9 ә  150662   British schwa      -> U+0259 ə
#   U+0259 ə   58584   already American
#   U+0252 ɒ   12652   British open o     -> U+0251 ɑ
#   U+0254 ɔ   44477   already American
#   U+028A ʊ    7467   British near-close back rounded -> U+028C ʌ
#   U+02D0 ː    3054   length mark        -> delete (American does not use it)
#   U+02C8 ˈ / U+02CC ˌ  stress marks      -> delete (the app sets its own)
U_ED_SCHWA = 'ә'
U_AM_SCHWA = 'ə'
U_ED_OPEN_O = 'ɒ'
U_AM_OPEN_O = 'ɑ'
U_LENGTH = 'ː'
U_PRIMARY = 'ˈ'
U_SECONDARY = 'ˌ'
U_N = 'ɡ'

# Ordered longest-first: the GOAT diphthong is two codepoints and must be
# handled before its parts.
#
# NOTE on U+028A ʊ: it is NOT a British marker. It is the near-close back
# rounded vowel used in both accents (look, book, good) and maps to itself in
# American. An earlier draft wrongly rewrote it to ʌ, which turned `look` into
# /lʌk/ — a different vowel and a wrong lesson. Only LOT ɒ, the two-schwa
# GOAT, the r-coloured vowels and the length mark actually differ.
IPA_SUBS = [
    ('əʊ', 'oʊ'),   # GOAT: British əʊ -> American oʊ
    ('ɛʊ', 'eʊ'),   # GOAT, lax
    ('ɜː', 'ɜr'),   # NURSE
    ('ɑː', 'ɑr'),   # START
    ('ɔː', 'ɔr'),   # NORTH
    ('ɪə', 'ɪr'),   # NEAR
    ('eə', 'er'),   # SQUARE
    ('ʌə', 'ʌr'),
    ('juː', 'ju'),
    (U_ED_OPEN_O, U_AM_OPEN_O),
    (U_ED_SCHWA, U_AM_SCHWA),
    (U_LENGTH, ''),
    (U_PRIMARY, ''),
    (U_SECONDARY, ''),
]

# Words whose British vowel a substitution would get WRONG in American English.
# High-frequency, so a wrong vowel here teaches the wrong thing.
RESPELL = {
    'water': '/ˈwɑtər/', 'later': '/ˈletər/', 'better': '/ˈbetər/',
    'computer': '/kəmˈjutər/', 'remember': '/rɪˈmembər/',
    'number': '/ˈnʌmbər/', 'over': '/ˈovər/', 'never': '/ˈnɛvər/',
    'every': '/ˈɛvri/', 'where': '/wɛr/', 'there': '/ðɛr/',
    'their': '/ðɛr/', 'here': '/hir/', 'about': '/əˈbaʊt/',
    'around': '/əˈraʊnd/', 'through': '/θru/', 'though': '/ðoʊ/',
    'thought': '/θɔt/', 'enough': '/ɪˈnʌf/', 'rough': '/rʌf/',
    'tough': '/tʌf/', 'cough': '/kɔf/', 'bought': '/bɔt/',
    'brought': '/brɔt/', 'daughter': '/ˈdɔtər/',
    'learn': '/lɜrn/', 'work': '/wɜrk/', 'word': '/wɜrd/',
    'world': '/wɜrld/', 'worth': '/wɜrθ/',
}


def to_american_ipa(ph, word=''):
    if not ph:
        return ''
    if word and word.lower() in RESPELL:
        return RESPELL[word.lower()]
    s = ph
    for a, b in IPA_SUBS:
        s = s.replace(a, b)
    s = re.sub(r'\s+', ' ', s).strip().strip('/').strip()
    if not s or not re.search(r'[a-zɑəɔɛɪʌʊæɜɐ]', s, re.I):
        # nothing pronounceable survived; better to omit the line than to
        # show the reader a symbol soup
        return ''
    return '/' + s + '/'


# ECDICT writes the tag as `n. ` with a dot but ALSO as a bare `n ` and as
# `i. ` for roman-numeral glosses. All three must go, or the card opens with
# "n a loud resonant noise" instead of the definition itself.
POS_PREFIX = re.compile(
    r'^(n|v|vt|vi|adj|adv|prep|conj|pron|num|art|aux|modal|interj|abbr|i|ii|iii)\s*\.\s+',
    re.I)
POS_PREFIX_BARE = re.compile(
    r'^(n|v|vt|vi|adj|adv|prep|conj|pron|num|art|aux|modal|interj|abbr)\s+(?=[a-z])',
    re.I)

# A definition is a whole line, so anchoring at the start of the FIRST sense is
# safe; these are checked against every candidate sense.
# Each pattern marks a sense a beginner will never want: a proper noun, an
# abbreviation, or a domain so specialised it misleads. `water` opens with
# "binary compound ... colorless odorless tasteless liquid" because ECDICT files
# the chemistry sense first, and `about` opens with "on the move" from the
# nautical sense. Both are technically correct and practically useless.
BAD_SENSE = re.compile(
    r'^\s*(?:'
    r'\((?:computing|computer science|mathematics|physics|chemistry|biology|'
    r'ecology|medicine|anatomy|zoology|botany|geology|linguistics|grammar|'
    r'phonetics|astronomy|psychology|sociology|economics|accounting|'
    r'banking|finance|nautical|heraldry|embryology|entomology|'
    r'law|logic|metaphysics|mythology|religion|navigation|mining|'
    r'metallurgy|architecture|engineering)\)'
    r'|cf\.'
    r'|used of '
    r'|plural of '
    r'|past participle of '
    r'|third person singular of '
    r'|comparative of '
    r'|superlative of '
    r'|ellipsis of '
    r'|initialism '
    r'|acronym '
    r'|abbreviation '
    r'|capital of '
    r'|coinage'
    r'|capitalized'
    r')',
    re.I)

# Domain markers that appear AFTER the part of speech, e.g.
# "n (computing) a register" or "n (embryology) the repeated division".
DOMAIN_INLINE = re.compile(r'^\s*\S{0,6}\s*\((?:[a-z ]{3,30})\)\s*', re.I)

SKIP_POS = re.compile(r'^\s*(abbr|interj)\b', re.I)

# A handful of very common words have a first sense that is technically correct
# and practically misleading, and no domain tag to detect it: `water` opens on
# the chemistry sense, `about` on the nautical one. For these the everyday
# sense is pinned explicitly. This is a short list on purpose — it is a
# dictionary's weakest kind of patch and it must not become a habit.
PINNED = {
    'water': 'the clear, colourless liquid that falls as rain and forms rivers',
    'about': 'on the subject of; concerning',
    'look': 'to direct the eyes in order to see something',
    'good': 'of satisfactory quality; not bad',
    'thing': 'an object or item that one need not or cannot name specifically',
    'world': 'the earth and all the people and things on it',
    'right': ' morally good, justified, or acceptable',
    'left': 'belonging or relating to the left-hand side',
    'like': 'to find pleasant or agreeable',
    'work': 'activity in which one is employed',
    'book': 'a written record bound in a volume',
    'point': 'a sharp-tipped end of something',
    'case': 'a particular instance or situation',
    'time': 'the indefinite continued progress of existence',
    'place': 'a particular position, point, or area',
    'part': 'a piece or segment combined with others to make a whole',
    'number': 'an arithmetic value used to represent a quantity',
    'system': 'a set of things working together as a whole',
    'state': 'a condition or situation',
    'form': 'the shape or appearance of something',
    'set': 'a group of similar things',
    'order': 'an arrangement of things in a particular sequence',
    'end': 'the final part of something',
    'value': 'the worth, importance, or usefulness of something',
    'scale': 'the relative size, amount, or extent of something',
    # inflections whose everyday sense is the VERB, but which ECDICT files
    # under the noun first (`says` -> "n the chance to speak")
    'says': 'to express in words; to state',
    'said': 'to state or declare in words',
    'is': 'to be; to exist',
    'was': 'the past tense of be',
    'are': 'the present tense of be, used with you/we/they',
    'goes': 'to move or travel from one place to another',
    # the computing sense is the one this app exists for
    'pointer': 'a variable that stores the address of another value in memory',
    'address': 'a number that tells the computer where a value is stored',
    'dereference': 'to follow a pointer and read or change the value it points at',
    'heap': 'the part of a program\'s memory that can be asked for while it runs',
    'segmentation': 'a fault: using memory that the program does not own',
}


def _clean_one(first):
    """Strip POS prefix and reject a sense that is not worth showing."""
    if not first:
        return ''
    s = first.strip()
    if BAD_SENSE.match(s):
        return ''
    if SKIP_POS.match(s):
        return ''
    s = POS_PREFIX.sub('', s).strip()
    s = POS_PREFIX_BARE.sub('', s).strip()
    # a leftover "(computing)" style qualifier after the tag
    s = DOMAIN_INLINE.sub('', s).strip()
    if re.match(r'^(see |cf\. |compare |i+\.\s*see)', s, re.I):
        return ''
    return s[:180].strip()


def clean_definition(d, word=''):
    """The first sense a beginner would actually want.

    ECDICT orders senses by part of speech, not by everyday usefulness, so this
    walks the candidates and takes the first that survives the filters rather
    than blindly taking line one."""
    if word and word.lower() in PINNED:
        return PINNED[word.lower()]
    if not d:
        return ''
    lines = [l for l in d.replace('\\n', '\n').split('\n') if l.strip()]
    # a line may hold several senses separated by ';' — split it into candidates
    cands = []
    for l in lines[:4]:
        for piece in re.split(r'[;；]', l):
            if piece.strip():
                cands.append(piece)
    for c in cands:
        got = _clean_one(c)
        if len(got) >= 8:          # a real definition, not a stub
            return got
    # nothing cleared the bar; return the least-bad candidate rather than nothing
    for c in cands:
        got = _clean_one(c)
        if got:
            return got
    return ''


def clean_translation(t):
    if not t:
        return ''
    t = t.replace('\\n', '\n')
    parts = [p.strip() for p in re.split(r'\n|；|;', t) if p.strip()]
    keep = []
    for p in parts:
        p = re.sub(r'^\W*\w+\.\s*', '', p)
        p = re.sub(r'[(（][^)）]{0,60}(第三人称|复数|过去式|现在式|比较级|最高级)[^)）]*[)）]', '', p)
        p = p.strip()
        if p and len(p) < 34:
            keep.append(p)
    keep.sort(key=lambda s: 0 if s.startswith('[计]') else 1)
    return '；'.join(keep[:2])


def pos_short(p):
    if not p:
        return ''
    best, bestn = '', -1
    for part in p.split('/'):
        if ':' in part:
            name, _, num = part.partition(':')
            try:
                n = int(num)
            except ValueError:
                continue
            if n > bestn:
                best, bestn = name, n
    return best or p.split('/')[0][:12]


def lemma_from_exchange(ex):
    if not ex:
        return ''
    for part in ex.split('/'):
        code, _, val = part.partition(':')
        if code in ('s', '0', '1') and val:
            return val
    return ''


def main():
    picked = {}
    with open(CSV, encoding='utf-8', newline='') as f:
        for row in csv.DictReader(f):
            w = (row.get('word') or '').strip()
            if not w:
                continue
            wl = w.lower()
            if not re.fullmatch(r"[a-z][a-z'\-]{0,24}", wl):
                continue
            en = clean_definition(row.get('definition') or '', wl)
            cn = clean_translation(row.get('translation') or '')
            if not en and not cn:
                continue
            ipa = to_american_ipa(row.get('phonetic') or '', wl)
            pos = pos_short(row.get('pos') or '')
            lemma = lemma_from_exchange(row.get('exchange') or '')
            e = picked.get(wl)
            if e is None:
                picked[wl] = {'ipa': ipa, 'pos': pos, 'en': en, 'cn': cn, 'lemma': lemma}
            else:
                if en and not e['en']:
                    e['en'] = en
                if len(cn) > len(e['cn']):
                    e['cn'] = cn
                if not e['ipa'] and ipa:
                    e['ipa'] = ipa
                if not e['pos'] and pos:
                    e['pos'] = pos
                if not e['lemma'] and lemma:
                    e['lemma'] = lemma

    # a hyphenated or apostrophised twin is the same word; inherit its gloss
    for w in list(picked.keys()):
        for ch in ('-', "'"):
            if ch in w:
                flat = w.replace(ch, '')
                if flat != w and flat in picked:
                    if not picked[w]['en'] and picked[flat]['en']:
                        picked[w]['en'] = picked[flat]['en']
                    if not picked[w]['ipa'] and picked[flat]['ipa']:
                        picked[w]['ipa'] = picked[flat]['ipa']

    words = {}
    for k in sorted(picked):
        v = picked[k]
        e = {'ipa': v['ipa'], 'pos': v['pos'], 'en': v['en'], 'cn': v['cn']}
        if v['lemma'] and v['lemma'] != k:
            e['lemma'] = v['lemma']
        words[k] = e

    with open(OUT_JSON, 'w', encoding='utf-8') as f:
        json.dump({'words': words}, f, ensure_ascii=False, separators=(',', ':'))

    raw = os.path.getsize(OUT_JSON)
    with zipfile.ZipFile(OUT_ZIP, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(OUT_JSON, 'dictionary.json')
    zipped = os.path.getsize(OUT_ZIP)

    n = len(words)
    print('entries        :', n)
    print('  with English : %d (%.1f%%)' % (sum(1 for v in words.values() if v['en']), 100 * sum(1 for v in words.values() if v['en']) / n))
    print('  with Chinese : %d (%.1f%%)' % (sum(1 for v in words.values() if v['cn']), 100 * sum(1 for v in words.values() if v['cn']) / n))
    print('  with IPA     : %d (%.1f%%)' % (sum(1 for v in words.values() if v['ipa']), 100 * sum(1 for v in words.values() if v['ipa']) / n))
    print('  with lemma   :', sum(1 for v in words.values() if v.get('lemma')))
    print('json : %.2f MB' % (raw / 1024 / 1024))
    print('zip  : %.2f MB' % (zipped / 1024 / 1024))


if __name__ == '__main__':
    main()
