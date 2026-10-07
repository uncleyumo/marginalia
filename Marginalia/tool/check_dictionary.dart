// Verify the zip decoder against the real shipped archive.
//
// The dictionary is 10.4 MB of deflate-compressed json, and the decoder in
// lib/data/dictionary.dart is hand-written because Dart's core has no zip
// reader. A decoder that has never been run against the real file is not a
// decoder, it is a guess — so this runs it, then checks that the words the
// sample article needs actually resolve.
//
//   dart tool/check_dictionary.dart

import 'dart:convert';
import 'dart:io';

import '../lib/data/zip.dart';

int _fail = 0;
int _checks = 0;

void check(String name, bool ok, [String detail = '']) {
  _checks++;
  if (ok) {
    print('  ok   $name');
  } else {
    _fail++;
    print('  FAIL $name${detail.isEmpty ? '' : '  -> $detail'}');
  }
}

void main(List<String> args) {
  final String zipPath = args.isEmpty
      ? 'assets/dict/dictionary.zip'
      : args.first;

  print('Marginalia — dictionary check');
  print('');
  print('decoding $zipPath with the app\'s own _ZipDecoder');

  final List<int> bytes = File(zipPath).readAsBytesSync();
  check('the archive is not empty', bytes.isNotEmpty);
  check('it starts with the zip local-header signature',
      bytes.length > 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04,
      'got ${bytes.take(4).toList()}');

  final Archive archive = ZipDecoder(bytes).decode();
  check('it holds exactly one member', archive.files.length == 1,
      'got ${archive.files.length}');
  check('the member is dictionary.json',
      archive.files.first.name == 'dictionary.json',
      'got ${archive.files.first.name}');

  final List<int> raw = archive.files.first.content;
  check('it inflates to something large', raw.length > 30 * 1024 * 1024,
      'got ${raw.length} bytes');

  final Object? decoded = jsonDecode(utf8.decode(raw));
  check('the inflated bytes are valid json', decoded is Map);
  final Map<String, dynamic> root = (decoded as Map).cast<String, dynamic>();
  final Map<String, dynamic> words =
      (root['words'] as Map).cast<String, dynamic>();
  check('it has a `words` map', words.isNotEmpty);
  check('and it is the size we shipped', words.length > 390000,
      'got ${words.length}');

  // the four fields the card renders, and nothing else
  final Object? first = words['pointer'];
  check('an entry is an object', first is Map);
  if (first is Map) {
    check('it has ipa/pos/en/cn',
        first.containsKey('ipa') &&
            first.containsKey('pos') &&
            first.containsKey('en') &&
            first.containsKey('cn'));
  }

  // the words the shipped sample article marks must resolve, including the
  // inflections that only work through the lemma fallback
  final List<String> mustResolve = <String>[
    'pointer', 'address', 'dereference', 'reserve', 'block', 'allocate',
    'heap', 'segmentation', 'crash', 'memory', 'compiler', 'variable',
    'value', 'beginner', 'meet', 'week', 'second', 'hate', 'fair', 'inside',
    'small', 'write', 'read', 'forget', 'ask', 'never', 'set',
    // inflections — the whole reason `lemma` exists
    'pointers', 'crashes', 'asks', 'says', 'reserves', 'leaks', 'follows',
    // hyphens and apostrophes, which a naive [a-z] filter would have dropped
    'book-keeping', "don't",
  ];
  final List<String> missing = <String>[];
  for (final String w in mustResolve) {
    final Object? e = words[w];
    if (e is! Map) {
      missing.add(w);
      continue;
    }
    final String lemma = (e['lemma'] as String?) ?? '';
    if (lemma.isNotEmpty && words[lemma] == null) missing.add('$w->$lemma');
  }
  check('every word the sample marks resolves (directly or via lemma)',
      missing.isEmpty, 'missing: $missing');

  // English-first is the product promise, so measure it honestly
  int withEn = 0;
  int withCn = 0;
  words.forEach((String _, Object? v) {
    if (v is! Map) return;
    if (((v['en'] as String?) ?? '').trim().isNotEmpty) withEn++;
    if (((v['cn'] as String?) ?? '').trim().isNotEmpty) withCn++;
  });
  final double enPct = 100 * withEn / words.length;
  final double cnPct = 100 * withCn / words.length;
  print('');
  print('  entries with an English gloss : $withEn (${enPct.toStringAsFixed(1)}%)');
  print('  entries with a Chinese gloss : $withCn (${cnPct.toStringAsFixed(1)}%)');
  check('Chinese coverage is near-total', cnPct > 95.0, '${cnPct.toStringAsFixed(1)}%');
  // English is the known weakness of the source data; the app is built to
  // degrade honestly rather than to pretend, so this is a floor, not a target
  check('English coverage clears the floor the UI relies on', enPct > 38.0,
      '${enPct.toStringAsFixed(1)}%');

  print('');
  print('=' * 60);
  if (_fail == 0) {
    print('ALL $_checks CHECKS PASSED  (${words.length} entries)');
  } else {
    print('$_fail of $_checks CHECKS FAILED');
  }
  print('=' * 60);
  if (_fail > 0) throw StateError('$_fail dictionary check(s) failed');
}
