#!/usr/bin/env bash
# ECDICT — free offline dictionary, 3.4M entries. 216 MB download, 851 MB unpacked.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data
test -f data/ecdict.db && { echo "ecdict.db already there"; exit 0; }
curl -sSL -o data/ecdict.zip \
  "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict.zip"
python3 -c "
import zipfile
z = zipfile.ZipFile('data/ecdict.zip')
name = next(n for n in z.namelist() if n.endswith('ecdict.db') or n.endswith('.csv'))
print('extracting', name)
open('data/ecdict.db','wb').write(z.read(name))
"
test -f data/ecdict.db || python3 -c "
import csv, sqlite3
import zipfile
z = zipfile.ZipFile('data/ecdict.zip')
name = next(n for n in z.namelist() if n.endswith('.csv'))
con = sqlite3.connect('data/ecdict.db')
con.execute('''CREATE TABLE stardict (id INTEGER PRIMARY KEY, word TEXT, sw TEXT,
  phonetic TEXT, definition TEXT, translation TEXT, pos TEXT, collins INTEGER,
  oxford INTEGER, tag TEXT, bnc INTEGER, frq INTEGER, exchange TEXT, detail TEXT,
  audio TEXT)''')
with z.open(name) as f:
    r = csv.reader((l.decode('utf-8', 'replace') for l in f))
    next(r)
    con.executemany('INSERT INTO stardict VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                    [row + [''] * (15 - len(row)) for row in r])
con.commit()
print('built stardict from csv')
"
rm -f data/ecdict.zip
echo "ok: $(du -h data/ecdict.db | cut -f1)"
