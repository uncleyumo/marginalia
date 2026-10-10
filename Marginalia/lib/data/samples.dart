// Loading the bundled sample articles.
//
// A fresh install with no API key must still have something to read, or the app
// opens on three plans and nothing else — which reads as "this app is broken"
// rather than "this app is waiting for you". So the sample ships in the bundle
// and is installed into the queue on first run.
//
// The cost of that decision is that a plan is a PLAN and an article is an
// ARTICLE, and installing a sample must not look like a spend. It doesn't touch
// money, and it does not mark a slot as anything the reader did.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../domain/models.dart';

/// One article as it sits in the bundle.
class SampleArticle {
  const SampleArticle({
    required this.id,
    required this.title,
    required this.sentences,
    required this.marks,
    required this.wordCount,
    required this.minuteEstimate,
    this.keywords = const <String>[],
    this.titleCn = '',
  });

  final String id;
  final String title;
  final String titleCn;

  /// What the sample is about, in the same shape the writer now returns.
  /// Replaces the single `topic` the bundle used to carry.
  final List<String> keywords;

  final List<Sentence> sentences;
  final List<Mark> marks;
  final int wordCount;
  final int minuteEstimate;

  /// Kilobytes on disk. Text only — there is no audio for a bundled sample, so
  /// the storage line stays honest rather than claiming an audio file that does
  /// not exist.
  int get kilobytes => (wordCount * 6 ~/ 1024) + 1;

  /// Map a bundled tier onto the two the app actually has.
  ///
  /// DESIGN has exactly two: `unfamiliar` (not met) and `difficult` (met, but
  /// hard). There is deliberately no `known`, so a third value in the data must
  /// collapse onto one of the two rather than invent a third colour. `learned`
  /// in the sample data means met-but-hard, which IS `difficult`.
  ///
  /// An earlier version treated anything that was not `difficult` as
  /// `unfamiliar`, which turned all seven `learned` marks into vermilion — a
  /// wrong colour on the majority of the words, and a wrong LESSON: the reader
  /// would have been told these were new when they were only hard.
  static MarkTier _tierOf(Object? raw) =>
      raw == 'unfamiliar' ? MarkTier.unfamiliar : MarkTier.difficult;

  static SampleArticle? fromJson(Map<String, dynamic> j) {
    final Object? rawSentences = j['sentences'];
    final Object? rawMarks = j['marks'];
    if (rawSentences is! List || rawMarks is! List) return null;

    final List<Sentence> sentences = <Sentence>[];
    for (final Object? s in rawSentences) {
      if (s is! Map) continue;
      final Object? en = s['en'];
      final Object? cn = s['cn'];
      if (en is! String) continue;
      sentences.add(Sentence(
        english: en,
        chinese: cn is String ? cn : '',
        // No audio file ships with a sample, and DESIGN's promise is that a
        // missing audio file is normal and the device engine covers it.
        audioPath: null,
      ));
    }
    if (sentences.isEmpty) return null;

    final List<Mark> marks = <Mark>[];
    for (final Object? m in rawMarks) {
      if (m is! Map) continue;
      final Object? surface = m['surface'];
      final Object? lemma = m['lemma'];
      final Object? idx = m['sentence'];
      final Object? tier = m['tier'];
      if (surface is! String || lemma is! String || idx is! int) continue;
      marks.add(Mark(
        surface: surface,
        lemma: lemma,
        sentenceIndex: idx,
        tier: _tierOf(tier),
      ));
    }

    return SampleArticle(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      titleCn: '${j['titleCn'] ?? j['title_cn'] ?? ''}',
      keywords: _keywords(j['keywords']),
      sentences: sentences,
      marks: marks,
      wordCount: j['wordCount'] is int ? j['wordCount'] as int : 0,
      minuteEstimate:
          j['minuteEstimate'] is int ? j['minuteEstimate'] as int : 3,
    );
  }

  Article toArticle() => Article(
        id: id,
        title: title,
        titleCn: titleCn,
        keywords: keywords,
        sentences: sentences,
        marks: marks,
        wordCount: wordCount,
        minuteEstimate: minuteEstimate,
      );
}

/// Read the keywords out of the bundled json, tolerating anything.
///
/// A sample with no keywords is a normal sample — the field was added after the
/// bundle was written, and a missing list must not cost the reader the article.
List<String> _keywords(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final Object? k in raw)
      if (k is String && k.trim().isNotEmpty) k.trim(),
  ];
}

/// Reads the bundled samples. Called once, at boot.
Future<List<SampleArticle>> loadSamples({AssetBundle? bundle}) async {
  final AssetBundle b = bundle ?? rootBundle;
  // Only one sample ships today. The list shape is deliberate: adding a second
  // must not change any call site.
  const List<String> paths = <String>['assets/sample/pointers.json'];
  final List<SampleArticle> out = <SampleArticle>[];

  for (final String path in paths) {
    try {
      final String raw = await b.loadString(path);
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final SampleArticle? a = SampleArticle.fromJson(
        decoded.cast<String, dynamic>(),
      );
      if (a != null) out.add(a);
    } catch (e) {
      // A missing sample must not stop the app: the reader can still write
      // their own articles, and an empty queue is not a crash.
      debugPrint('sample $path unavailable: $e');
    }
  }
  return out;
}