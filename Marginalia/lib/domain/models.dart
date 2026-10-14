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

import 'difficulty.dart';
import 'plan.dart' show LengthBand;

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
    required this.sentences,
    required this.marks,
    required this.wordCount,
    required this.minuteEstimate,
    this.keywords = const <String>[],
    this.titleCn = '',
  });

  final String id;
  final String title;

  /// The title in Chinese, when the writer produced one.
  ///
  /// Empty for older articles and for anything written before this field
  /// existed. Empty is a real state, not a broken one: the title is still
  /// tappable for word-by-word meaning either way, which is the part a reader
  /// stuck on a title actually needs.
  final String titleCn;

  /// What the article is about, in three to six words the WRITER chose.
  ///
  /// This is what replaced `topic`. A topic was a label the reader had to pick
  /// in advance from a list they had to maintain; a keyword list is produced
  /// after the fact by the thing that actually knows what it wrote. It is
  /// strictly more accurate — `pointers · memory · C` says more than `C
  /// language` ever did — and it costs the reader nothing to keep.
  ///
  /// May be empty. An article without keywords is a normal article, not a
  /// broken one: the writer is asked for them, not required to produce them,
  /// and a card with a title and no keywords is still a card you can read.
  final List<String> keywords;

  final List<Sentence> sentences;
  final List<Mark> marks;
  final int wordCount;
  final int minuteEstimate;

  /// How hard this text is, worked out from the words the writer chose to mark.
  ///
  /// A getter, not a stored field. The body already states everything this
  /// needs, and a stored copy could disagree with the text it describes —
  /// which is the "second copy of the truth" this project refuses to create.
  /// The price is that a stub article read back from the database (no
  /// sentences in memory) has no band, exactly as it has no word count today.
  ///
  /// The count is in RUNNING WORDS, the unit the coverage research uses: a word
  /// the reader does not know is unknown every time it appears, not only the
  /// first time. So `pointers` marked once and printed three times costs three.
  Difficulty? get difficulty {
    if (wordCount <= 0 || marks.isEmpty) {
      return difficultyOf(unknownTokens: 0, totalTokens: wordCount);
    }
    // Both shapes, because the writer marks whichever the sentence used.
    final Set<String> forms = <String>{
      for (final Mark m in marks) ...<String>[
        m.surface.toLowerCase(),
        m.lemma.toLowerCase(),
      ],
    };
    int unknown = 0;
    for (final Sentence s in sentences) {
      unknown += countUnknownTokens(s.english, forms);
    }
    return difficultyOf(unknownTokens: unknown, totalTokens: wordCount);
  }
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
    this.topic = '',
    this.keywords = const <String>[],
    this.reads = 0,
    this.listens = 0,
    this.kilobytes = 0,
    this.goneReason,
    this.freedKilobytes = 0,
  });

  final String articleId;
  final String title;

  /// What this article was about, as recorded when it was written.
  ///
  /// A HISTORICAL FIELD, and the only place `topic` survives. It is not
  /// configuration and nothing reads it to decide anything — it is what the row
  /// says about an article written before keywords existed. Rows written from
  /// now on leave it empty and carry [keywords] instead.
  final String topic;

  /// What the writer said the article was about. The shelf searches and
  /// displays these.
  final List<String> keywords;

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
    this.instruction = '',
    this.instructionId,
    this.plannedWords = 0,
    this.plannedBand = LengthBand.medium,
    this.isWriting = false,
  });

  /// Stable across a planned->ready transition. The card keeps its identity so
  /// the transition does not reorder the queue underneath the reader.
  final String articleId;

  final SlotState state;

  /// Non-null exactly when [state] is [SlotState.ready].
  final Article? article;

  /// What the reader asked for, in their own words — or empty, which is the
  /// normal case and means the writer picks the subject.
  ///
  /// Stored as TEXT on the slot rather than as a reference to the saved
  /// instruction, because a planned card has to keep saying what it was asked
  /// for even if the reader later edits or deletes that saved instruction. What
  /// was asked for is a fact about this slot.
  final String instruction;

  /// Which saved instruction it came from, when it came from one. Null for a
  /// hand-typed instruction and for a free pick.
  ///
  /// This exists for ONE reason: so that using an instruction can bump its
  /// `lastUsedDay` and `useCount` without having to match on text. It is not a
  /// foreign key and nothing joins on it.
  final String? instructionId;

  /// How many words this particular article was asked for. Resolved when the
  /// slot was planned — a band reads its length off the plan, a custom request
  /// carries the number the reader typed.
  final int plannedWords;

  /// Where [plannedWords] came from. Kept so the card can say which band this
  /// one is instead of guessing from the number — two bands can share a length,
  /// and a reader who asked for a custom 300 did not ask for `medium`.
  final LengthBand plannedBand;

  /// True while a write is in flight. Distinct from [state]: this is a
  /// transient, not one of the two resting states.
  ///
  /// A PICTURE OF A LOCK, AND NOT THE LOCK. The lock is a field on the shell
  /// (`_writeClaim`), because it has to be claimed and tested in one expression
  /// with no `await` between them and because it has to die with the process.
  /// This flag is what the CARD renders from, and it is deliberately NOT
  /// persisted: `saveQueue` writes `false` and `loadQueue` reads `false`, so a
  /// queue off the disk never claims a write is in flight. Persisting it let a
  /// mid-flight save from any other action brick a card permanently.
  bool isWriting;

  bool get isPlanned => state == SlotState.planned;
  bool get isReady => state == SlotState.ready;

  /// True when the reader asked for nothing in particular and the writer will
  /// choose the subject. The ordinary case, and a legitimate state rather than
  /// missing data — which is why it gets a NAME on the card instead of a blank.
  bool get isFreePick => instruction.trim().isEmpty;

  /// The label a planned card carries in its title position.
  ///
  /// An instruction can be a whole sentence, so it is the reader's own words
  /// here and the card truncates; a free pick gets the neutral word instead of
  /// an empty space, because a card with nothing at the top reads as broken.
  String get subjectLabel => isFreePick ? 'Anything' : instruction.trim();

  /// The line under it, saying where the subject came from. Small, and the only
  /// place the card distinguishes "you asked for this" from "the writer chose".
  String get subjectNote => isFreePick
      ? 'the writer picks the subject'
      : (instructionId == null ? 'your instruction' : 'a saved instruction');

  /// What a planned card says about length. The number is what will be asked
  /// for; the band is where it came from, and saying both is what keeps the
  /// card from claiming a band the reader never chose.
  String get lengthLabel => plannedBand == LengthBand.custom
      ? '~$plannedWords words · your number'
      : '${plannedBand.label} · ~$plannedWords words';

  QueueSlot copyWith({
    SlotState? state,
    Article? article,
    String? instruction,
    String? instructionId,
    int? plannedWords,
    LengthBand? plannedBand,
    bool? isWriting,
  }) =>
      QueueSlot(
        articleId: articleId,
        state: state ?? this.state,
        article: article ?? this.article,
        instruction: instruction ?? this.instruction,
        instructionId: instructionId ?? this.instructionId,
        plannedWords: plannedWords ?? this.plannedWords,
        plannedBand: plannedBand ?? this.plannedBand,
        isWriting: isWriting ?? this.isWriting,
      );

  @override
  String toString() => 'QueueSlot($articleId, ${state.name}'
      '${isWriting ? ', writing' : ''}, subject: $subjectLabel)';
}
/// `once` / `twice` / `4 times`.
///
/// Words for the small numbers, because these lines are read as sentences and
/// `1 times` is the kind of thing that makes a reader stop trusting the rest of
/// the interface.
///
/// ONE definition for the three places a count appears — the queue card, its
/// ⋯ menu, and the article screen's count line. It was a private helper in each
/// of the first two and a static in the third, which is three copies of a
/// sentence this app shows everywhere: a counter that said `2 times` on the card
/// and `twice` in the menu would read as two different facts about one article.
String times(int n) => switch (n) {
      1 => 'once',
      2 => 'twice',
      _ => '$n times',
    };
