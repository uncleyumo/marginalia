// DESIGN §4e — counts are not storage.
//
// This is the file the whole project is built around, so it is deliberately
// plain Dart with no Flutter import and no code generation: the five
// invariants must be checkable by reading, and by running, without a widget
// binding or a build step.
//
// "You read it five times; that happened." Deleting an article's bytes removes
// its text and audio and NEVER its read or heard counters. Freeing disk space is
// honest housekeeping; resetting the record would be a lie, because the file
// was never the memory.

/// Why an article's bytes were released.
///
/// The distinction is the whole point: a `gone` article keeps its row, its
/// place in the sort order, and its place in *Most revisited*. Only the bytes
/// are gone.
enum GoneReason {
  /// The reader freed the space deliberately. The common case.
  freedByUser,

  /// The phone was low on space. Same effect, different wording.
  freedForSpace,
}

/// The two states a queue slot can be in, and there are only two.
///
/// An earlier design conflated "there is a plan" with "there is an article",
/// which meant it either spent money nobody agreed to spend, or hid the next
/// choice until it was too late to make it. Splitting them makes the expensive
/// step always deliberate — and because a plan is free, instant and rerollable,
/// deciding later costs nothing.
///
/// There is deliberately no `finished` state and no `finished` bool anywhere
/// (invariant 5). Reading an article once is a beginning, not an ending.
enum SlotState {
  /// A spec exists. The article does NOT. Nothing has been paid for.
  planned,

  /// The article exists and can be read or heard.
  ready,
}

/// What a marked word is.
///
/// `unfamiliar` and `difficult` are the two tiers the writer emits, and they
/// earn two different colours: a vermilion pencil rule for a word the reader has
/// not met, a jade one for a word that is merely hard.
///
/// There is no `known`. The app records, it never judges — a "I know this"
/// button is the exact thing this product refuses to build.
enum MarkTier {
  /// Not met before. Vermilion pencil rule.
  unfamiliar,

  /// Met, but hard. Jade rule.
  difficult,
}

/// One word the writer marked, resolved to a position in the article.
class Mark {
  const Mark({
    required this.surface,
    required this.lemma,
    required this.sentenceIndex,
    required this.tier,
  });

  /// The exact text as printed, e.g. `pointers` for lemma `pointer`.
  final String surface;

  /// The dictionary form, e.g. `pointer`.
  final String lemma;

  final int sentenceIndex;
  final MarkTier tier;

  @override
  bool operator ==(Object other) =>
      other is Mark &&
      other.surface == surface &&
      other.lemma == lemma &&
      other.sentenceIndex == sentenceIndex &&
      other.tier == tier;

  @override
  int get hashCode => Object.hash(surface, lemma, sentenceIndex, tier);

  @override
  String toString() =>
      'Mark($surface -> $lemma @s$sentenceIndex, ${tier.name})';
}

/// A sentence: English, its Chinese, and optionally a pre-built audio file.
class Sentence {
  const Sentence({
    required this.english,
    required this.chinese,
    this.audioPath,
  });

  final String english;
  final String chinese;

  /// Null when the article has no audio — which is the normal case with no
  /// MiMo key. The listen view then falls back to the device engine per
  /// sentence. DESIGN promises: with no key at all, every word still has sound.
  final String? audioPath;
}

/// An article the reader can open.
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.topic,
    required this.sentences,
    required this.marks,
    required this.wordCount,
    required this.minuteEstimate,
    this.focus = '',
  });

  final String id;
  final String title;

  /// A topic IS its own display name — one string, no id/name table to keep in
  /// sync. DESIGN's deliberate simplification.
  final String topic;

  /// The lens the topic was written through. Same topic + different focus is a
  /// genuinely different article.
  final String focus;

  final List<Sentence> sentences;
  final List<Mark> marks;
  final int wordCount;
  final int minuteEstimate;
}

/// The article's own on-disk footprint, tracked SEPARATELY from its counts.
///
/// This is the type that makes invariant 4 hard to violate by accident: the
/// only way to change [kilobytes] is through [freeSpace], and that method
/// physically cannot reach [reads] or [listens] because they are not parameters
/// of anything it calls.
class LedgerEntry {
  LedgerEntry({
    required this.articleId,
    required this.title,
    required this.topic,
    this.reads = 0,
    this.listens = 0,
    this.kilobytes = 0,
    this.goneReason,
    this.freedKilobytes = 0,
  });

  final String articleId;
  final String title;
  final String topic;

  /// How many times the reader has read this THROUGH. A count, never a verdict.
  int reads;

  /// How many times it was played. Independent of [reads].
  int listens;

  /// Size on disk RIGHT NOW. Zero once the bytes are freed.
  int kilobytes;

  /// How many KB were freed, if they were. Kept separately from [kilobytes]
  /// because the shelf has to keep saying "1.2 MB freed" AFTER the size is
  /// gone — zeroing the size and losing the number together would leave the
  /// reader with no way to account for what happened.
  int freedKilobytes;

  /// Non-null when the bytes are gone. The row stays either way.
  GoneReason? goneReason;

  bool get isGone => goneReason != null;

  /// Count one full read. The article STAYS — reading never removes it.
  void countRead() => reads++;

  /// Count one listen. This deliberately does not touch [reads]: hearing an
  /// article is not reading it, and conflating the two is how a reader ends up
  /// with a record that claims they read something they only heard on a bus.
  void countListen() => listens++;

  /// Release the bytes. The counts are not parameters of this method, so they
  /// cannot be reset by it. That is the whole point of the signature.
  void freeSpace({GoneReason reason = GoneReason.freedByUser}) {
    freedKilobytes += kilobytes;
    kilobytes = 0;
    goneReason = reason;
  }
}

/// One row per (day, article). The ONLY record of what happened.
///
/// *Most revisited* and the calendar numbers are both GROUP BY queries over
/// this one table. Storing a per-article total as well would be the "second
/// copy of the truth" the prototype refuses to create — the two could disagree,
/// and then the app would be showing a number it cannot explain.
class DayLogRow {
  DayLogRow({
    required this.day,
    required this.articleId,
    required this.title,
    this.reads = 0,
    this.listens = 0,
    this.minutes = 0,
  });

  /// Local calendar day as `YYYY-MM-DD`. A String rather than a DateTime so a
  /// stored row never shifts when the device timezone does.
  final String day;

  final String articleId;
  final String title;

  int reads;
  int listens;
  int minutes;
}

/// One slot in the queue. Exactly one of [state] and the article fields is
/// meaningful, and which one is stated by [state] — not inferred from nulls.
class QueueSlot {
  QueueSlot({
    required this.articleId,
    required this.state,
    this.article,
    this.topic = '',
    this.focus = '',
    this.plannedWords = 0,
    this.plannedMarked = 0,
    this.isWriting = false,
  });

  /// Stable across a planned->ready transition. The card keeps its identity so
  /// the transition does not reorder the queue underneath the reader.
  final String articleId;

  final SlotState state;

  /// Non-null exactly when [state] is [SlotState.ready].
  final Article? article;

  /// The topic a planned article WILL be about. A topic IS its display name.
  final String topic;

  /// The lens, visible on a planned card so the choice is made before spending.
  final String focus;

  final int plannedWords;
  final int plannedMarked;

  /// True while a write is in flight. Distinct from [state]: this is a
  /// transient, not one of the two resting states.
  bool isWriting;

  bool get isPlanned => state == SlotState.planned;
  bool get isReady => state == SlotState.ready;

  /// The label a topic pill shows. A card whose topic is empty is a free pick,
  /// which is a legitimate state, not missing data.
  String get topicLabel => topic.isEmpty ? 'Free pick' : topic;

  QueueSlot copyWith({
    SlotState? state,
    Article? article,
    String? topic,
    String? focus,
    int? plannedWords,
    int? plannedMarked,
    bool? isWriting,
  }) =>
      QueueSlot(
        articleId: articleId,
        state: state ?? this.state,
        article: article ?? this.article,
        topic: topic ?? this.topic,
        focus: focus ?? this.focus,
        plannedWords: plannedWords ?? this.plannedWords,
        plannedMarked: plannedMarked ?? this.plannedMarked,
        isWriting: isWriting ?? this.isWriting,
      );

  @override
  String toString() => 'QueueSlot($articleId, ${state.name}'
      '${isWriting ? ', writing' : ''}, topic: $topic)';
}