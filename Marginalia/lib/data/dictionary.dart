// The offline dictionary.
//
// 392,695 entries, shipped as a 10.4 MB zip and inflated once into the app's
// private directory. The whole point is the promise in DESIGN: a lookup is
// $0.00, offline, and works in airplane mode. There is no API fallback — if a
// word is missing, the app says so honestly rather than reaching for a network.
//
// Why a zip and not the json: the uncompressed dictionary is 38.9 MB, and
// bundling that would add 39 MB to the APK for nothing. The app pays 10.4 MB.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'zip.dart';

/// One entry, exactly the four fields the card renders.
///
/// `lemma` is the fallback target: `crashes` carries `lemma: 'crash'`, so a tap
/// on an inflection still finds a definition. Without it a dictionary that
/// cannot answer `says` looks broken.
@immutable
class DictEntry {
  const DictEntry({
    required this.ipa,
    required this.pos,
    required this.en,
    required this.cn,
    this.lemma,
  });

  final String ipa;
  final String pos;

  /// The English gloss. May be empty — ECDICT has no English for some words —
  /// and the card then shows the Chinese behind the usual tap and says so.
  final String en;

  final String cn;
  final String? lemma;

  bool get hasEnglish => en.trim().isNotEmpty;
  bool get hasChinese => cn.trim().isNotEmpty;

  @override
  String toString() => 'DictEntry(${lemma ?? ''} $en)';
}

/// Why a lookup came back empty.
///
/// The distinction matters: a word that is genuinely absent is a fact the app
/// should state plainly, while a dictionary that failed to load is a fault it
/// should admit rather than paper over.
enum LookupMiss {
  /// Not in the dictionary. Perfectly normal for a proper noun or a ticker.
  notFound,

  /// The dictionary has not finished loading yet.
  notLoaded,
}

class Dictionary {
  Dictionary._(this._words, this.loadedAt);

  final Map<String, DictEntry> _words;
  final DateTime loadedAt;

  int get size => _words.length;
  bool get isLoaded => _words.isNotEmpty;

  static const String _zipAsset = 'assets/dict/dictionary.zip';
  static const String _fileName = 'dictionary.json';

  /// Where the inflated dictionary lives.
  ///
  /// Its own subdirectory, not the support directory itself. Two reasons, both
  /// learned the hard way:
  ///
  ///  - On a fresh install the support directory does not exist yet, so anything
  ///    written into it fails with
  ///      PathNotFoundException: Cannot rename file to .../dictionary.json
  ///    `create(recursive: true)` fixes the parent, and doing it here means every
  ///    caller gets it.
  ///  - The database file lives in the same directory, and inflating 39 MB
  ///    there meant the dictionary work and the drift schema migration ran
  ///    concurrently on the same directory. Rename failed while the database was
  ///    being created beside it. A separate directory removes the interaction.
  static Future<File> _targetFile() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'dict'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  /// Load once, then reuse. Re-inflating 39 MB on every launch would be a
  /// pointless cost, so the inflated file is kept and only re-read if missing.
  static Future<Dictionary> load({AssetBundle? bundle}) async {
    final File file = await _targetFile();
    if (!file.existsSync()) {
      await _inflate(bundle ?? rootBundle, file);
    }
    return _parse(file);
  }

  /// Exposed for a first-run check: does the inflated dictionary exist?
  static Future<bool> isInstalled() async {
    final File file = await _targetFile();
    return file.exists();
  }

  /// Delete the inflated copy. The next [load] re-inflates it. Used by a
  /// "repair" action, never silently.
  static Future<void> uninstall() async {
    final File file = await _targetFile();
    if (file.existsSync()) await file.delete();
  }

  static Future<void> _inflate(AssetBundle bundle, File target) async {
    // Decode to bytes first: rootBundle gives a ByteData, and the zip codec
    // needs a Uint8List. Doing it in one pass avoids a String round-trip on
    // 10 MB of binary.
    final ByteData data = await bundle.load(_zipAsset);
    final List<int> zipBytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // Decode synchronously-ish: the archive holds ONE member, so there is no
    // streaming to do and an isolate would only add handshake cost.
    final Archive archive = ZipDecoder(zipBytes).decode();
    final List<int> raw = archive.files.first.content;

    // Write via a temporary name and rename, so an interrupted first launch
    // cannot leave a half-written file that later looks "installed".
    final File tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(raw, flush: true);
    // Some Android filesystems refuse a rename onto a path whose parent was
    // created moments ago in the same breath. Creating the directory before the
    // temp write, and retrying the rename once, is cheaper than losing the whole
    // dictionary to a filesystem hiccup.
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      final Directory parent = target.parent;
      if (!parent.existsSync()) await parent.create(recursive: true);
      await tmp.rename(target.path);
    }
  }

  /// Parse the inflated json.
  ///
  /// This runs on a BACKGROUND ISOLATE, and that is not an optimisation — it is
  /// the difference between the app opening and not. `jsonDecode` on a 39 MB
  /// string is one long synchronous block, and on the UI isolate it froze the
  /// first frame for about five seconds:
  ///     Skipped 306 frames! The application may be doing too much work on its
  ///     main thread.
  /// The reader came to read. A five-second blank screen before the first
  /// article is the opposite of that promise.
  ///
  /// The isolate returns the finished map, which is copied once on transfer.
  /// That copy is a few hundred milliseconds and happens off the critical path
  /// of the first frame; the freeze was not the copy, it was the parse.
  static Future<Dictionary> _parse(File file) async {
    final Map<String, DictEntry> entries = await compute(_parseInIsolate, file.path);
    return Dictionary._(entries, DateTime.now());
  }

  /// The isolate entry point. It must be a top-level or static function with a
  /// single sendable argument — hence the path, not the File.
  static Map<String, DictEntry> _parseInIsolate(String path) {
    final File file = File(path);
    final String raw = file.readAsStringSync();
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('dictionary.json is not an object');
    }
    final Object? words = decoded['words'];
    if (words is! Map<String, dynamic>) {
      throw StateError('dictionary.json has no `words` map');
    }
    return _parseEntry(words);
  }

  static Map<String, DictEntry> _parseEntry(Map<String, dynamic> words) {
    final Map<String, DictEntry> out = <String, DictEntry>{};
    words.forEach((String k, Object? v) {
      out[k] = _one(k, v);
    });
    return out;
  }

  static DictEntry _one(String key, Object? v) {
    if (v is! Map) {
      return const DictEntry(ipa: '', pos: '', en: '', cn: '');
    }
    String s(String name) {
      final Object? x = v[name];
      return x is String ? x : '';
    }

    final String lemma = s('lemma');
    return DictEntry(
      ipa: s('ipa'),
      pos: s('pos'),
      en: s('en'),
      cn: s('cn'),
      lemma: lemma.isEmpty || lemma == key ? null : lemma,
    );
  }

  /// The lookup the Article screen uses.
  ///
  /// Order matters: exact form first, because `pointers` has its own entry and
  /// the reader tapped that. Only then the lemma, which is what makes an
  /// inflection resolve.
  (DictEntry?, String) lookup(String surface) {
    final String w = surface.toLowerCase().trim();
    final DictEntry? direct = _words[w];
    if (direct != null) {
      // the surface form has its own entry — prefer it, and only fall through to
      // the lemma when that entry carries no English to show
      if (direct.hasEnglish || direct.lemma == null) return (direct, w);
      final DictEntry? viaLemma = _words[direct.lemma!];
      if (viaLemma != null) return (viaLemma, direct.lemma!);
      return (direct, w);
    }
    return (null, w);
  }

  /// A lookup that reports WHY it missed, so the sheet can be honest rather
  /// than showing a blank card.
  (DictEntry, LookupMiss) resolve(String surface) {
    const DictEntry nothing =
        DictEntry(ipa: '', pos: '', en: '', cn: '');
    if (!isLoaded) return (nothing, LookupMiss.notLoaded);
    final (DictEntry? found, _) = lookup(surface);
    if (found != null) return (found, LookupMiss.notFound);
    return (nothing, LookupMiss.notFound);
  }
}
