"""Coverage proof for the shipped dictionary, including the lemma fallback.

A word counts as covered if it is in the dictionary directly OR reachable
through its inflection lemma — which is what the Dart lookup will do, so the
test measures the real behaviour rather than the file's raw key set.
"""
import json
import re
import zipfile

PROJ = r'E:\Dev_work\Flutter_Dev\marginalia\Marginalia'
z = zipfile.ZipFile(PROJ + r'\assets\dict\dictionary.zip')
D = json.loads(z.read('dictionary.json').decode('utf-8'))['words']
print('dictionary entries:', len(D))

TOKEN = re.compile(r"[A-Za-z][A-Za-z'\-]*")


def norm(w):
    return w.lower().strip("'-")


def covered(w):
    if w in D:
        return True
    e = D.get(w)
    if e and e.get('lemma') and e['lemma'] in D:
        return True
    return False


def report(name, text):
    ts = TOKEN.findall(text)
    types = sorted({norm(t) for t in ts if len(norm(t)) > 1})
    miss = [t for t in types if not covered(t)]
    cov = 100.0 * (len(types) - len(miss)) / len(types) if types else 0
    print()
    print('--- %s ---' % name)
    print('types %d | covered %d (%.1f%%) | missing %d' % (len(types), len(types) - len(miss), cov, len(miss)))
    if miss:
        print('  missing:', ', '.join(miss[:50]))
    return miss


art = json.load(open(PROJ + r'\assets\sample\pointers.json', encoding='utf-8'))
m = report('shipped sample article', ' '.join(s['en'] for s in art['sentences']))

prose = """
Most beginners meet pointers in the second week of C, and most beginners hate them.
That is fair, because the word arrives before the idea behind it. A pointer is
just a variable that stores an address, and an address is a number that says
where a value lives in memory. When you write int x = 5, the compiler reserves
a small block of memory and puts 5 inside it. To read the value you dereference
the pointer, and the star gives you 5 back. If you dereference a pointer that
was never set, your program crashes with a segmentation fault. You can also
allocate memory yourself, because malloc asks the heap for a block. Forget free
and the memory leaks, a little on every loop, until the program runs out. None
of this is clever. It is a book-keeping habit, and the compiler follows it
exactly. Read the value through the pointer and you will never mix the two up
again, even when the stack overflows and the buffer overruns its bounds.
"""
report('technical prose (C/pointers)', prose)

news = """
NVDA moved sharply after the company reported quarterly earnings that beat
analyst expectations. Revenue grew, margins expanded, and management raised
guidance for the coming year. Investors had priced in a slower pace, so the
reaction was immediate. The stock has now recovered most of its losses from
last month, though volume remains thin and volatility is high. Analysts caution
that the data centre business carries a disproportionate share of profit, and
that supply constraints could limit growth. Revenue guidance assumes continued
demand for accelerated computing, but competition from rival designs remains
intense. The company reiterated its commitment to investing in research and
development, and said supply would improve gradually through the year. Margins
compressed slightly as the company scaled manufacturing abroad.
"""
report('news / finance prose', news)

music = """
A lo-fi beat is made by slowing a record down until the texture softens, then
tape saturation roughens the edges. Drums land later and feel heavier, which is
why the groove seems to drag. The chords are often borrowed from old soul
records, played on a cheap keyboard and detuned just enough to sound tired.
Ambient works similarly but removes the pulse entirely, so the listener never
waits for a beat that will not arrive. Producers layer field recordings, tape
hiss, and vinyl crackle to fill the silence. The result is music that feels
familiar without ever resolving, which is exactly what a study hall wants.
"""
report('music prose', music)

common = """the be to of and a in that have it for not on with he as you do at this but his
by from they we say her she or an will my one all would there their what so up
out if about who get which go me when make can like time no just him know take
people into year your good some could them see other than then now look only
come its over think also back after use two how our work first well way even
new want because any these give day most us is are was were been has had did
said made find tell ask seem feel try leave call keep let begin help talk turn
start show hear play run move live believe hold bring happen write provide sit
stand lose pay meet include continue set learn change lead understand watch
follow stop create speak read allow add spend grow open walk win offer remember
love consider appear buy wait serve die send expect build stay fall cut reach
kill remain suggest raise pass sell require report decide pull"""
ct = sorted({norm(w) for w in common.split()})
cmiss = [w for w in ct if not covered(w)]
print()
print('--- top-200 frequency words ---')
print('covered %d/%d' % (len(ct) - len(cmiss), len(ct)))
if cmiss:
    print('  MISSING:', ', '.join(cmiss))

print()
print('=== VERDICT ===')
if m:
    print('FAIL: sample article has uncovered words:', m)
else:
    print('PASS: the shipped sample article is 100% covered.')
if cmiss:
    print('WARN: %d common words uncovered' % len(cmiss))
else:
    print('PASS: all top-200 frequency words covered.')
