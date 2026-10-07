// Writing an article — the one path in this app that costs money.
//
// It is reachable from exactly one place: a tap on a planned card's Write it.
// There is no timer, no WorkManager, no background task, and no call on app
// launch. `Queue.mayAutoWrite` exists so that no future code path can widen
// this one by accident.
//
// Everything the model returns is treated as untrusted. The word count and the
// reading time are COMPUTED from the text that came back, never read out of the
// json, because a model asked for a 300-word article will cheerfully return 180
// words and call it 300 — and a card that lies about its own length is the exact
// failure this project exists to avoid.

import 'dart:convert';

import '../domain/models.dart';
import '../domain/plan.dart';
import 'remote/api.dart';

/// Builds the prompt and parses the answer. No Flutter, no storage: this is a
/// pure function of (plan, topic, focus) and one HTTP response.
class ArticleWriter {
  ArticleWriter(this._api);

  final RemoteApi _api;

  /// What the model is told, and why each instruction is there.
  static const String system = '''
You write short English articles for one reader who is learning English.

Rules, all of which matter:
- Output ONE json object and nothing else. No prose before or after it.
- "sentences" is an array of {"en": "...", "cn": "..."}. Every sentence needs a
  natural Chinese translation. English first, always en-US.
- "marks" is an array of {"surface": "...", "lemma": "...", "tier": "..."}.
  "surface" must appear verbatim in the sentence it belongs to. "lemma" is the
  dictionary form. "tier" is either "unfamiliar" (the reader has never met it)
  or "difficult" (they have met it and it is still hard). Never "known".
- Write plain sentences a person would say out loud. No headings, no bullet
  lists, no rhetorical questions, no summary paragraph at the end.
- Do not explain the topic. Explain it by being clear, not by announcing that
  it is about to be explained.
- Respect every "avoid" instruction absolutely. Holding something back is the
  whole point of those instructions.
''';

  /// The user's half: the plan, verbatim, plus the shape demanded.
  Future<Article> write({
    required String articleId,
    required String topic,
    required String focus,
    required ReadingPlan plan,
    required int words,
    required int marked,
    required String apiKey,
    required WriterEndpoint endpoint,
  }) async {
    final String user = _userPrompt(
      topic: topic,
      focus: focus,
      plan: plan,
      words: words,
      marked: marked,
    );

    final String raw = await _api.write(
      endpoint: endpoint,
      apiKey: apiKey,
      system: system,
      user: user,
    );

    return parse(raw,
        articleId: articleId, topic: topic, focus: focus, marked: marked);
  }

  String _userPrompt({
    required String topic,
    required String focus,
    required ReadingPlan plan,
    required int words,
    required int marked,
  }) {
    final StringBuffer b = StringBuffer();
    b.writeln('Topic: $topic');
    if (focus.trim().isNotEmpty) b.writeln('Lens: $focus');
    b.writeln('About $words words, with at most $marked words marked.');
    b.writeln();
    b.writeln('The reading plan, field by field:');
    if (plan.reader.trim().isNotEmpty) {
      b.writeln('- The reader is: ${plan.reader}');
    }
    if (plan.topics.isNotEmpty) {
      b.writeln('- Articles may come from: ${plan.topics.join(', ')}');
    }
    if (plan.style.isNotEmpty) {
      b.writeln('- How it should read: ${plan.style.join('; ')}');
    }
    if (plan.gloss.isNotEmpty) {
      b.writeln('- Explain these plainly: ${plan.gloss.join('; ')}');
    }
    if (plan.avoid.isNotEmpty) {
      b.writeln('- Hold all of this back: ${plan.avoid.join('; ')}');
    }
    // Verbatim, and last, so nothing typed is edited away by a field above it.
    if (plan.raw.trim().isNotEmpty) {
      b.writeln();
      b.writeln('In the reader\'s own words, verbatim:');
      b.writeln(plan.raw.trim());
    }
    b.writeln();
    b.writeln('Answer with this exact shape:');
    b.writeln('{"title":"...","sentences":[{"en":"...","cn":"..."}],'
        '"marks":[{"surface":"...","lemma":"...","tier":"unfamiliar"}]}');
    return b.toString();
  }

  /// Parse the answer. Throws [RemoteFailure] rather than returning a half-built
  /// article: a card that shows a title with no body is worse than an error,
  /// because it looks like something the app wrote on purpose.
  Article parse(
    String raw, {
    required String articleId,
    required String topic,
    required String focus,
    required int marked,
  }) {
    final Object? decoded = _decode(raw);
    if (decoded is! Map) {
      throw const RemoteFailure(
          'The writer answered in a shape this app cannot read. Nothing was '
          'saved.');
    }

    final Object? title = decoded['title'];
    final Object? rawSentences = decoded['sentences'];
    if (title is! String || title.trim().isEmpty || rawSentences is! List) {
      throw const RemoteFailure(
          'The writer answered without an article in it. Nothing was saved.');
    }

    final List<Sentence> sentences = <Sentence>[];
    for (final Object? s in rawSentences) {
      if (s is! Map) continue;
      final Object? en = s['en'];
      final Object? cn = s['cn'];
      if (en is! String || en.trim().isEmpty) continue;
      sentences.add(Sentence(
        english: en.trim(),
        chinese: cn is String ? cn.trim() : '',
      ));
    }
    if (sentences.isEmpty) {
      throw const RemoteFailure(
          'The writer answered with no sentences. Nothing was saved.');
    }

    final List<Mark> marks = <Mark>[];
    final Set<String> seen = <String>{};
    final Object? rawMarks = decoded['marks'];
    if (rawMarks is List) {
      for (final Object? m in rawMarks) {
        if (m is! Map) continue;
        if (marks.length >= marked) break;
        final Object? surface = m['surface'];
        final Object? lemma = m['lemma'];
        if (surface is! String || lemma is! String) continue;
        final String surf = surface.trim();
        final String lem = lemma.trim().toLowerCase();
        if (surf.isEmpty || lem.isEmpty || !seen.add(lem)) continue;
        final int at = _sentenceOf(sentences, surf);
        if (at < 0) continue; // a mark the reader cannot find is not a mark
        marks.add(Mark(
          surface: surf,
          lemma: lem,
          sentenceIndex: at,
          tier: m['tier'] == 'unfamiliar'
              ? MarkTier.unfamiliar
              : MarkTier.difficult,
        ));
      }
    }

    // Counted here, not read from the json. See the file header.
    final int wordCount = _count(sentences);
    return Article(
      id: articleId,
      title: title.trim(),
      topic: topic,
      focus: focus,
      sentences: sentences,
      marks: marks,
      wordCount: wordCount,
      minuteEstimate: (wordCount / 200).ceil().clamp(1, 60),
    );
  }

  /// Tolerate a fenced block and a stray sentence around it. Models wrap json in
  /// ``` even when told not to, and rejecting the whole article over a fence
  /// would be refusing to read an answer that is plainly there.
  Object? _decode(String raw) {
    String s = raw.trim();
    final int fence = s.indexOf('```');
    if (fence >= 0) {
      final int start = s.indexOf('\n', fence);
      final int end = s.lastIndexOf('```');
      if (start > 0 && end > start) s = s.substring(start + 1, end);
    }
    final int first = s.indexOf('{');
    final int last = s.lastIndexOf('}');
    if (first < 0 || last <= first) return null;
    s = s.substring(first, last + 1);
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Which sentence a marked word actually sits in. The model is not asked for
  /// the index and is not trusted to have one, because a mark pointing at the
  /// wrong sentence colours the wrong word in the reader's own text.
  int _sentenceOf(List<Sentence> sentences, String surface) {
    final String needle = surface.toLowerCase();
    for (int i = 0; i < sentences.length; i++) {
      final RegExp word = RegExp('\\b${RegExp.escape(needle)}\\b',
          caseSensitive: false);
      if (word.hasMatch(sentences[i].english)) return i;
    }
    return -1;
  }

  static int _count(List<Sentence> sentences) {
    int n = 0;
    for (final Sentence s in sentences) {
      n += RegExp(r"[A-Za-z][A-Za-z'\-]*").allMatches(s.english).length;
    }
    return n;
  }
}