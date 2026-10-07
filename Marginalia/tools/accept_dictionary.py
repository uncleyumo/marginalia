"""Final acceptance check on the shipped dictionary artefact.

Everything here reads the file that will actually ship, not the build script's
in-memory state, so a bug in serialisation would be caught.
"""
import json
import re
import zipfile

P = r'E:\Dev_work\Flutter_Dev\marginalia\Marginalia'
z = zipfile.ZipFile(P + r'\assets\dict\dictionary.zip')
raw = z.read('dictionary.json')
D = json.loads(raw.decode('utf-8'))['words']
n = len(D)
print('entries: %d' % n)

fail = []

# 1. every entry must have at least one thing to show
empty = [k for k, v in D.items() if not v['en'] and not v['cn']]
if empty:
    fail.append('%d entries have neither English nor Chinese' % len(empty))
print('1. entries with no gloss at all      : %d' % len(empty))

# 2. British IPA must be gone
brit = set(chr(c) for c in [0x04D9, 0x0252, 0x02D0])
leak = [k for k, v in D.items() if v['ipa'] and any(c in v['ipa'] for c in brit)]
if leak:
    fail.append('%d entries still hold British IPA' % len(leak))
print('2. entries with British IPA          : %d' % len(leak))

# 3. no leaked escape sequences or POS prefixes
nl = [k for k, v in D.items() if v['en'] and '\\n' in v['en']]
pfx = [k for k, v in D.items() if v['en'] and re.match(r'^(n|v|adj|adv|prep|conj|pron)\s*\.\s', v['en'])]
if nl:
    fail.append('%d definitions contain a literal backslash-n' % len(nl))
if pfx:
    fail.append('%d definitions start with a POS prefix' % len(pfx))
print('3. definitions with literal \\n       : %d' % len(nl))
print('   definitions with a POS prefix     : %d' % len(pfx))

# 4. keys must be lowercase and article-safe
badkey = [k for k in D if not re.fullmatch(r"[a-z][a-z'\-]{0,24}", k)]
if badkey:
    fail.append('%d keys are not lowercase article words' % len(badkey))
print('4. keys that are not plain lowercase  : %d' % len(badkey))

# 5. a definition must be a sentence, not a fragment
short = [k for k, v in D.items() if v['en'] and len(v['en']) < 12]
print('5. suspiciously short definitions     : %d' % len(short))

# 6. the words the sample article marks must all resolve with a real gloss
art = json.load(open(P + r'\assets\sample\pointers.json', encoding='utf-8'))
missing = []
for m in art['marks']:
    e = D.get(m['lemma'])
    if not e or (not e['en'] and not e['cn']):
        missing.append(m['lemma'])
if missing:
    fail.append('sample article lemmas unresolved: %s' % missing)
print('6. sample-article lemmas unresolved   : %d %s' % (len(missing), missing or ''))

# 7. Chinese glosses must not be empty strings masquerading as content
blankcn = [k for k, v in D.items() if v['cn'] and not v['cn'].strip('；; ')]
if blankcn:
    fail.append('%d Chinese glosses are blank' % len(blankcn))
print('7. blank Chinese glosses              : %d' % len(blankcn))

print()
print('size: json %.2f MB / zip %.2f MB' % (len(raw) / 1024 / 1024,
      __import__('os').path.getsize(P + r'\assets\dict\dictionary.zip') / 1024 / 1024))
print()
if fail:
    print('FAIL')
    for f in fail:
        print('  - ' + f)
else:
    print('ALL CHECKS PASS')
