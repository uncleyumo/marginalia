// Writing an article — the one path in this app that costs money.
//
// It is reachable from two kinds of place and no others: a tap on a planned
// card's Write it, and the app's own automatic write. There is no timer, no
// WorkManager, no background task, and no call on app launch. The automatic
// entry point is `_ShellState._maybeAutoWrite`, and everything that would let
// it widen is gathered in `_ShellState._mayAutoWrite` — which is the gate, and
// the only one. `Queue.mayAutoWrite` looks like a gate and is not: it reads
// `!hasPlannedSlot`, which is the inverse of what the app does, and it has no
// callers.
//
// Everything the model returns is treated as untrusted. The word count and the
// reading time are COMPUTED from the text that came back, never read out of the
// json, because a model asked for a 300-word article will cheerfully return 180
// words and call it 300 — and a card that lies about its own length is the exact
// failure this project exists to avoid.

import 'dart:convert';

import '../domain/difficulty.dart';
import '../domain/models.dart';
import '../domain/picture.dart';
import '../domain/plan.dart';
import 'remote/agent.dart';
import 'remote/api.dart';
import 'remote/news.dart';

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
- Mark the words a reader at this level would genuinely not know. There is NO
  target number of marks and no minimum. Marking a word that did not need it
  makes the text harder to read and the list less useful, so when in doubt mark
  fewer rather than more. Three well-chosen words beat ten padded ones, and an
  article with no marks at all is a perfectly good answer.
- "keywords" is an array of three to six short English words saying what the
  article is about. Concrete nouns, lowercase, one to three words each. They go
  on the card so the reader can see at a glance what this one is. Do not repeat
  the title, and do not use them as a summary sentence.
- You choose the subject unless you are told the reader asked for something
  specific. When you choose, choose something surprising: this reader gets
  three of these a day, and the fourth article about the same idea in different
  words is worse than a strange one.
''';

  /// Added when tools are available. Kept apart from [system] so the fast path
  /// sends exactly the prompt it has always sent.
  static const String toolRules = '''
You may look things up before you write. Two things to be honest about when you
do:

- If you read a story, it is written in CHINESE and you are writing ENGLISH.
  Read it, understand it, then write your own article about the idea. Do NOT
  translate it, do NOT follow its sentences, and do NOT reproduce any phrase
  from it. The reader is paying for something new, not for a translation.
- If a search tells you something you did not know, use it. If it contradicts
  what you were about to write, believe the search.
- If a tool fails, do not ask it again. Write the article from what you already
  have. An article written without research is worth far more to the reader than
  a third attempt at the same failing call.
''';

  /// Added when the reader attached pictures.
  ///
  /// Kept apart from [system] because the fast path must send exactly the prompt
  /// it has always sent — a reader with no pictures is not told about a feature
  /// they are not using, and a system prompt that describes pictures to a model
  /// that was sent none is a model looking for something that is not there.
  ///
  /// WHAT IT HASHT TO DO, and it is more than "look at the pictures":
  ///
  ///   1. Say what the pictures ARE. The reader does not label them, and the
  ///      difference between "a sentence I liked" and "a word list I am
  ///      memorising" is the difference between an article about the sentence's
  ///      idea and an article that USES those words. So the model is asked to
  ///      work out which it is looking at.
  ///   2. Say what to do when there are also words. The two cases the brief
  ///      calls out — pictures only, and pictures plus a sentence — are handled
  ///      separately below, because "write about this" and "write about this
  ///      and also that" are different instructions.
  ///   3. Refuse to treat a picture as a script. A photograph of a page is not
  ///      a request to transcribe it. This is the same rule the news tool
  ///      already follows, for the same reason.
  static const String pictureRules = '''
The reader attached photographs to this request. They are above, in order.

WHAT TO DO WITH THEM — in this order:

- Work out what each one IS. They are usually one of three things: a GOOD
  SENTENCE the reader met somewhere, a SCENE worth writing about, or a WORD
  LIST they are memorising in another app. Judge from what is actually in the
  picture, not from what you expected.
- A sentence: take the IDEA, not the words. Write your own article about what
  it says. Do not quote it, do not translate it, and do not open with it.
- A scene: describe what is happening and why it is interesting. The article is
  ABOUT the thing in the picture.
- A word list: those words are the vocabulary to USE. Write an article that
  uses as many of them as will fit naturally, in real sentences — not listed,
  not defined, not in the order they appear. This is the whole reason the
  reader photographed a flashcard app.

- If the reader ALSO wrote a sentence, that sentence is the subject and the
  pictures are the material. Do both: write what they asked for, and draw the
  vocabulary, the scene or the idea out of the photographs.
- If the reader wrote NOTHING and attached only pictures, the pictures ARE the
  subject. Pick the most interesting one and build from there; the others are
  supporting material.
- If a picture is unreadable, or is not any of the three things above, ignore
  it and say nothing about it. A photograph you cannot read is not a reason to
  write a worse article.

WHAT NEVER TO DO: transcribe text out of a picture into the article. A page of
somebody else's prose, reproduced in your sentences, is not an article this
reader paid for. Take the idea or the vocabulary and write something new.
''';

  /// The user's half: the plan, verbatim, plus the shape demanded.
  ///
  /// There is no `marked` argument and there will not be one again. How many
  /// words get marked is the writer's judgement; the app measures the result.
  /// See `difficulty.dart` for why asking for a number made the list worse.
  ///
  /// There is no `topic` argument either. The subject is either a sentence the
  /// reader typed ([instruction]) or the writer's own choice — and in the
  /// second case this method says so out loud, because a model told nothing
  /// about a subject tends to reach for the safest, most obvious one.
  ///
  /// [agent] is null for the fast path: no tools configured, so the loop is not
  /// started at all and this is exactly the single call it has always been. That
  /// is the default reader — no news key, no search key — and it is why the cost
  /// line can still say "one call" without lying.
  Future<Article> write({
    required String articleId,
    required ReadingPlan plan,
    required int words,
    required String apiKey,
    required WriterEndpoint endpoint,
    String instruction = '',
    List<NewsItem> news = const <NewsItem>[],
    List<String> recentTitles = const <String>[],
    List<String> metWords = const <String>[],
    // Words the reader starred and still owes showings for. Unlike `metWords`,
    // which is an offer, every word here MUST appear: a star is a promise the
    // app has to keep countable.
    List<String> mustUseWords = const <String>[],
    List<Picture> pictures = const <Picture>[],
    AgentLoop? agent,
    void Function(AgentResult)? onResult,
  }) async {
    final String user = _userPrompt(
      plan: plan,
      words: words,
      instruction: instruction,
      news: news,
      recentTitles: recentTitles,
      metWords: metWords,
      mustUseWords: mustUseWords,
      pictures: pictures,
    );

    final String raw;
    // What this run is FOR, in the reader's words, with the subject in it.
    // The log stamps this on every line, so "which article is this about?"
    // is answered on the card rather than by decoding a run id. Truncated
    // because a log label is a label, not a prompt.
    final String subject = instruction.trim();
    final String what = subject.isEmpty
        ? (pictures.isEmpty
            ? 'Writing an article (subject left to the writer)'
            : 'Writing an article from ${pictures.length} '
                'picture${pictures.length == 1 ? '' : 's'}')
        : 'Writing an article: ${_oneLine(subject)}';

    // Pictures change the system prompt, so the two paths are separate from here
    // down. The fast path is byte-for-byte what it has always been.
    final String prompt =
        pictures.isEmpty ? system : '$system\n\n$pictureRules';

    if (agent == null) {
      raw = await _api.write(
        endpoint: endpoint,
        apiKey: apiKey,
        system: prompt,
        user: user,
        what: what,
        pictures: pictures,
      );
    } else {
      final AgentResult r = await agent.run(
        system: prompt,
        user: user,
        what: what,
        pictures: pictures,
      );
      onResult?.call(r);
      raw = r.content;
    }

    return parse(raw, articleId: articleId);
  }

  /// One quiet line, short enough to be a label.
  static String _oneLine(String s) {
    final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 60 ? t : '${t.substring(0, 60)}…';
  }

  /// Build the user message.
  ///
  /// The shape of this is the whole argument against `topic`: what to write
  /// about is either ONE SENTENCE THE READER TYPED or nothing at all, and
  /// everything else here is about how it should read.
  String _userPrompt({
    required ReadingPlan plan,
    required int words,
    required String instruction,
    required List<NewsItem> news,
    required List<String> recentTitles,
    required List<String> metWords,
    required List<String> mustUseWords,
    required List<Picture> pictures,
  }) {
    final StringBuffer b = StringBuffer();

    // Today, so the writer has something to vary on. Free, offline, and the
    // cheapest possible source of "this one is different from the last one".
    b.writeln('Today is ${_todayLine()}.');
    b.writeln();

    // The three cases, in the order they actually occur:
    //
    //   words + pictures  — the sentence is the subject, the pictures the
    //                       material. Both are stated, so the model does not
    //                       have to guess which one wins.
    //   pictures only     — there is NO sentence, and saying so out loud is the
    //                       difference between a model that reads the
    //                       photographs and one that asks what the subject is.
    //                       This is the case the brief singles out, and it is
    //                       the one a naive implementation gets wrong: without
    //                       this branch the prompt says "NOTHING has been
    //                       chosen for you, pick the subject yourself" and the
    //                       model cheerfully ignores the pictures entirely.
    //   words only        — unchanged, and the ordinary case.
    if (instruction.trim().isNotEmpty) {
      b.writeln('The reader asked for this specifically:');
      b.writeln('«${instruction.trim()}»');
      if (pictures.isNotEmpty) {
        b.writeln('They also attached ${pictures.length} '
            'picture${pictures.length == 1 ? '' : 's'}, above. Write what they '
            'asked for and draw the material out of the photographs.');
      } else {
        b.writeln('Write that. Everything below governs HOW it should read, '
            'not what it is about.');
      }
    } else if (pictures.isNotEmpty) {
      b.writeln('The reader attached ${pictures.length} '
          'picture${pictures.length == 1 ? '' : 's'} and wrote NOTHING. The '
          'photographs ARE the request.');
      b.writeln('Read them, work out what each one is — a sentence they liked, '
          'a scene, or a word list they are memorising — and build the article '
          'from the most interesting one.');
    } else {
      b.writeln('NOTHING has been chosen for you. Pick the subject yourself, '
          'and make it something this reader would not have guessed.');
    }
    b.writeln();

    if (recentTitles.isNotEmpty) {
      b.writeln('You have written these recently — do not repeat them, and do '
          'not write another article on the same subject in different words:');
      for (final String t in recentTitles) {
        b.writeln('- $t');
      }
      b.writeln();
    }

    // The 30 headlines, when the news source is on. They go in the MESSAGE
    // rather than behind a tool: they are already here, they are free, and
    // making the model spend a paid round trip to read a list it could have
    // been handed is waste.
    if (news.isNotEmpty) {
      b.writeln('Today\'s Zhihu Daily headlines. One of these is a good place '
          'to start — read one with read_story if it looks promising, or '
          'ignore them all and write about something else:');
      for (final NewsItem n in news) {
        b.writeln('${n.index}. ${n.title}');
      }
      b.writeln();
    }

    // The plan, through the plan's OWN renderer.
    //
    // This used to be a second, hand-written list of the same five fields, and
    // the two had already drifted: the copy here said "Articles may come from"
    // where the plan said "Topics may come from". Two renderings of one object
    // is the second copy of the truth this project refuses to keep.
    b.write(plan.toPrompt());
    b.writeln();

    // A star is a PROMISE, so its words are stated separately and without the
    // optional wording below. "Use four to six of them" is exactly what must
    // not be said about a word the reader asked for twice.
    if (mustUseWords.isNotEmpty) {
      b.writeln('The reader asked to meet these words again. EACH of them must '
          'appear at least once, in a natural sentence. An ordinary inflection '
          '(plural, past tense, -ing, adverb) counts; a different word does '
          'not. Do not list them, do not translate them, do not define them — '
          'just use them:');
      for (final String w in mustUseWords) {
        b.writeln('- $w');
      }
      b.writeln();
    }

    if (metWords.isNotEmpty) {
      b.writeln('This reader recently met these words: ${metWords.join(', ')}.');
      b.writeln('Use four to six of them naturally, in real sentences — not '
          'listed, not defined, just used.');
      b.writeln();
    }

    b.writeln('About $words words.');
    b.writeln();
    b.writeln('Answer with this exact shape:');
    b.writeln('{"title":"...","titleCn":"...",'
        '"keywords":["...","..."],'
        '"sentences":[{"en":"...","cn":"..."}],'
        '"marks":[{"surface":"...","lemma":"...","tier":"unfamiliar"}]}');
    b.writeln('`titleCn` is the same title in Chinese, short and natural — '
        'the reader looks at the title first and may not know the words in it.');
    return b.toString();
  }

  static const List<String> _weekdays = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// `Tuesday, 7 October 2026 — autumn`, in the northern hemisphere's seasons.
  ///
  /// The season is stated rather than computed from the hemisphere, because the
  /// app does not know where the reader is and inventing one would be worse
  /// than saying nothing. It is a nudge towards variety, not a fact the article
  /// has to be about.
  static String _todayLine([DateTime? now]) {
    final DateTime n = now ?? DateTime.now();
    final String season = switch (n.month) {
      3 || 4 || 5 => 'spring',
      6 || 7 || 8 => 'summer',
      9 || 10 || 11 => 'autumn',
      _ => 'winter',
    };
    return '${_weekdays[n.weekday - 1]}, ${n.day} ${_months[n.month - 1]} '
        '${n.year} — $season';
  }

  /// Parse the answer. Throws [RemoteFailure] rather than returning a half-built
  /// article: a card that shows a title with no body is worse than an error,
  /// because it looks like something the app wrote on purpose.
  ///
  /// EVERY failure here is thrown about a response that already came back 2xx,
  /// and on the agent path that is after two to five PAID calls — `parse` runs
  /// after `agent.run()` returns (`write`, line 212). So each of these carries
  /// the money with it via `_api.spentFailure`, rather than defaulting to
  /// `spent: false` and telling the reader nothing was spent about an article
  /// they had paid for. That sentence was the single worst thing this app could
  /// say, and it was saying it on exactly the path that costs the most.
  Article parse(
    String raw, {
    required String articleId,
  }) {
    final Object? decoded = _decode(raw);
    if (decoded is! Map) {
      throw _api.spentFailure(
          'The writer answered in a shape this app cannot read. Nothing was '
          'saved.');
    }

    final Object? title = decoded['title'];
    final Object? rawSentences = decoded['sentences'];
    if (title is! String || title.trim().isEmpty || rawSentences is! List) {
      throw _api.spentFailure(
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
      throw _api.spentFailure(
          'The writer answered with no sentences. Nothing was saved.');
    }

    // Counted BEFORE the marks, because the cap is derived from it. See below.
    final int wordCount = _count(sentences);

    // The cap is a guard against a pathological answer, not a setting and not a
    // target: `markCapFor` allows 1 mark per 4 words, five times the density at
    // which an article already reads as Hard. Nothing the writer would
    // plausibly return comes near it, so the difficulty the reader sees is
    // always the difficulty the writer actually wrote.
    final int cap = markCapFor(wordCount);

    final List<Mark> marks = <Mark>[];
    final Set<String> seen = <String>{};
    final Object? rawMarks = decoded['marks'];
    if (rawMarks is List) {
      for (final Object? m in rawMarks) {
        if (m is! Map) continue;
        if (marks.length >= cap) break;
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

    // Keywords are a DISPLAY aid, so nothing here may fail because of them. A
    // model that returned a string instead of a list, or one long sentence
    // instead of three words, still produced a good article — and throwing it
    // away over a caption would be trading something paid for against
    // something cosmetic.
    final List<String> keywords = _keywords(decoded['keywords']);

    // The Chinese title is an aid, not a requirement: a model that skipped it
    // still produced a title the reader can tap for word meanings. Empty is
    // the honest answer rather than a placeholder that pretends to be one.
    final Object? titleCn = decoded['titleCn'] ?? decoded['title_cn'];

    // Counted here, not read from the json. See the file header.
    return Article(
      id: articleId,
      title: title.trim(),
      titleCn: titleCn is String ? titleCn.trim() : '',
      keywords: keywords,
      sentences: sentences,
      marks: marks,
      wordCount: wordCount,
      minuteEstimate: (wordCount / 200).ceil().clamp(1, 60),
    );
  }

  /// At most six keywords, each at most three words, no duplicates.
  ///
  /// The cap is on the CARD, not on the model: six short words is what fits on
  /// one quiet line, and a card that has to wrap its keywords has stopped being
  /// a glance.
  static List<String> _keywords(Object? raw) {
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final Object? k in raw) {
      if (k is! String) continue;
      final String w = k.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (w.isEmpty || w.length > 40) continue;
      if (w.split(' ').length > 3) continue;
      if (!seen.add(w.toLowerCase())) continue;
      out.add(w);
      if (out.length >= 6) break;
    }
    return out;
  }

  // ── the plan, rewritten by the same model ───────────────────────────────

  /// What the model is told when it is editing the PLAN rather than writing.
  ///
  /// The field-by-field types are spelled out because the answer is parsed back
  /// into `ReadingPlan` and a field of the wrong type has to be dropped rather
  /// than crash the sheet. Everything here is a constraint on SHAPE; what the
  /// plan should say is the reader's request, not this prompt's business.
  static const String planSystem = '''
You edit a reading plan for an app that writes short English articles for one
reader who is learning English. You do not write articles.

Output ONE json object and nothing else. No prose before or after it. The
object has exactly these keys:
- "reader": string. Who the reader is and what they already know. This is the
  vocabulary ceiling — it is what stops the writer explaining pointers to
  someone who writes code.
- "topics": array of strings. Where articles may come from.
- "style": array of strings. How the writing should read.
- "gloss": array of strings. Words or ideas to explain in plain language.
- "avoid": array of strings. What to hold back. This is the field that stops a
  fluent but wrong draft, so never empty it without being asked to.
- "shortWords": integer, 50 to 2000. What "short" means, in words.
- "mediumWords": integer, 50 to 2000. What "medium" means.
- "longWords": integer, 50 to 2000. What "long" means.

Rules:
- Change only what the request asks for. Every other field must come back
  exactly as it was given, byte for byte.
- Add to the existing arrays; do not replace them, unless the request is
  explicitly to remove something.
- Keep shortWords <= mediumWords <= longWords.
- Write the field VALUES in the reader's own language where they already are.
  Do not translate what is already there.
''';

  /// Ask the model for a new plan, held aside as a diff.
  ///
  /// Returns a [PlanRewrite], never a bare plan: "your plan changed" is a claim
  /// the reader has to be able to SEE, so the proposal travels with the list of
  /// fields that differ and nothing is written until they accept it.
  Future<PlanRewrite> rewritePlan({
    required ReadingPlan plan,
    required String request,
    required String apiKey,
    required WriterEndpoint endpoint,
  }) async {
    final StringBuffer b = StringBuffer();
    b.writeln('The plan as it stands:');
    b.writeln(jsonEncode(<String, Object?>{
      'reader': plan.reader,
      'style': plan.style,
      'gloss': plan.gloss,
      'avoid': plan.avoid,
      'shortWords': plan.shortWords,
      'mediumWords': plan.mediumWords,
      'longWords': plan.longWords,
    }));
    if (plan.raw.trim().isNotEmpty) {
      b.writeln();
      b.writeln('The reader also wrote, in their own words, verbatim:');
      b.writeln(plan.raw.trim());
    }
    b.writeln();
    b.writeln('The change they asked for:');
    b.writeln(request.trim());

    final String raw = await _api.write(
      endpoint: endpoint,
      apiKey: apiKey,
      system: planSystem,
      user: b.toString(),
      // The plan is a "which configuration" question, not an article. Saying
      // so on the log card is the difference between "something failed" and
      // "the plan rewrite failed".
      what: 'Rewriting your reading plan: ${_oneLine(request)}',
    );

    final ReadingPlan proposal = _planFrom(raw, plan);
    return PlanRewrite(proposal: proposal, changes: _diff(plan, proposal));
  }

  /// Read a plan out of an answer, falling back to [old] field by field.
  ///
  /// NEVER throws on a bad field. A rewrite that got seven fields right and one
  /// wrong should hand the reader seven changes, not an error — the whole
  /// reason the diff exists is that they get to look before it lands, so a
  /// partly-wrong answer costs them nothing but a glance.
  ///
  /// The one thing that IS an error: no usable json at all. There is nothing to
  /// show and nothing to fall back to but the old plan, and silently returning
  /// the old plan would make the sheet say "no changes" about a call that
  /// failed. That is the same lie as a card that shows a title with no body —
  /// and it is a lie about a paid call, so it carries the money too.
  ReadingPlan _planFrom(String raw, ReadingPlan old) {
    final Object? decoded = _decode(raw);
    if (decoded is! Map) {
      throw _api.spentFailure(
          'The writer answered in a shape this app cannot read. Your plan was '
          'not touched.');
    }

    /// Strings only, trimmed, empties dropped. A number or a nested object in a
    /// list field is a type error, not a value to coerce.
    List<String> list(Object? v, List<String> fallback) {
      if (v is! List) return fallback;
      final List<String> out = <String>[
        for (final Object? x in v)
          if (x is String && x.trim().isNotEmpty) x.trim(),
      ];
      // An empty list where there was content is a deletion nobody asked for;
      // `avoid` is the field that stops a fluent-but-wrong draft, and a rewrite
      // that silently emptied it would be a rewrite that made the app worse.
      return out.isEmpty && fallback.isNotEmpty ? fallback : out;
    }

    String text(Object? v, String fallback) =>
        v is String && v.trim().isNotEmpty ? v.trim() : fallback;

    /// A length is clamped into the range the sheet's stepper offers, so a
    /// model that answers `"mediumWords": 30000` cannot produce a card that
    /// asks for thirty thousand words.
    int number(Object? v, int fallback) =>
        v is int ? v.clamp(50, 2000) : fallback;

    final int short = number(decoded['shortWords'], old.shortWords);
    final int medium = number(decoded['mediumWords'], old.mediumWords);
    final int long = number(decoded['longWords'], old.longWords);

    // Ordered, because a plan where "long" is shorter than "short" is a plan
    // whose three bands mean nothing. Sorting is the only repair that keeps all
    // three numbers the model chose.
    final List<int> ordered = <int>[short, medium, long]..sort();

    return ReadingPlan(
      reader: text(decoded['reader'], old.reader),
      style: list(decoded['style'], old.style),
      gloss: list(decoded['gloss'], old.gloss),
      avoid: list(decoded['avoid'], old.avoid),
      shortWords: ordered[0],
      mediumWords: ordered[1],
      longWords: ordered[2],
      // Carried through untouched. Ask-the-AI edits fields; it does not eat the
      // reader's own words.
      raw: old.raw,
    );
  }

  /// Which fields actually differ, for the diff the sheet renders.
  ///
  /// Compared as rendered text, so a change of whitespace or of list order is
  /// not reported as a change — a diff that lists fields nothing happened to
  /// teaches the reader to stop reading it.
  List<PlanChange> _diff(ReadingPlan before, ReadingPlan after) {
    final List<PlanChange> out = <PlanChange>[];

    void one(PlanField field, String was, String now) {
      if (was.trim() == now.trim()) return;
      out.add(PlanChange(field: field, was: was, now: now));
    }

    one(PlanField.reader, before.reader, after.reader);
    one(PlanField.style, before.style.join(', '), after.style.join(', '));
    one(PlanField.gloss, before.gloss.join(', '), after.gloss.join(', '));
    one(PlanField.avoid, before.avoid.join(', '), after.avoid.join(', '));
    one(PlanField.lengthShort, '${before.shortWords}',
        '${after.shortWords}');
    one(PlanField.lengthMedium, '${before.mediumWords}',
        '${after.mediumWords}');
    one(PlanField.lengthLong, '${before.longWords}', '${after.longWords}');
    return out;
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