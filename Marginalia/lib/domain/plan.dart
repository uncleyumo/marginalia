// The reading plan is STRUCTURED DATA, not a paragraph.
//
// It used to be one free-text box, which was honest about how little was known:
// the writer received a blob and guessed. A blob also cannot be SHOWN — you
// cannot point at "the length" or at "what to avoid" and change just that one.
//
// So the plan is an object with named fields, and the free-text box became one
// editor among several ways to change it. Same writer, same endpoint, one call,
// but the thing being edited is now legible. `raw` is kept so nothing is lost: a
// sentence the reader typed that no field captured still reaches the writer
// verbatim.
//
// Seven fields, rendered as seven labelled rows. An empty field is not missing
// data — it means the app decides that one.

/// The named fields, in display order. The order is the display order because
/// the prototype renders them as rows, and DESIGN insists a single field must be
/// pointable-at.
///
/// Two groups, and the split is load-bearing rather than cosmetic:
///
///   · [keywords] answer WHAT to write — the reader, the topics, the style, the
///     words to explain, the things to hold back.
///   · [lengths] answer HOW LONG — one number per band.
///
/// They are one enum because `PlanChange` is a PER-FIELD diff and the AI is
/// allowed to change a length ("Longer articles, around 500 words" has to be
/// able to point at the band it changed). They are two groups because they are
/// two different questions, and the settings screen renders them under two
/// headings. `marked` used to be a field here; it is gone, and the reason is in
/// `difficulty.dart`.
enum PlanField {
  reader('Reader', PlanFieldKind.text),
  style('Style', PlanFieldKind.list),
  gloss('Explain', PlanFieldKind.list),
  avoid('Avoid', PlanFieldKind.list),
  lengthShort('Short', PlanFieldKind.number),
  lengthMedium('Medium', PlanFieldKind.number),
  lengthLong('Long', PlanFieldKind.number);

  const PlanField(this.label, this.kind);

  final String label;
  final PlanFieldKind kind;

  /// How it should read — the four fields that shape the prose without saying
  /// what it is about.
  ///
  /// `topics` used to be the first member of this group. It is gone, and its
  /// absence is deliberate: the plan governs HOW an article reads, and the
  /// SUBJECT is either chosen by the writer (the normal case) or asked for in
  /// the reader's own words on the card. A standing list of permitted subjects
  /// was neither — it was configuration pretending to be content, and it made
  /// every article come from the same small set.
  static const List<PlanField> keywords = <PlanField>[
    reader,
    style,
    gloss,
    avoid,
  ];

  /// How long it runs, one row per band.
  static const List<PlanField> lengths = <PlanField>[
    lengthShort,
    lengthMedium,
    lengthLong,
  ];
}

enum PlanFieldKind { text, list, number }

/// Which of the three lengths an article was asked for, or an exact number the
/// reader typed instead.
///
/// `custom` is a member rather than "a band plus a flag" because it is what the
/// card has to SAY: a card that claims `medium · ~300 words` when the reader
/// typed 275 is a card that made up a number.
enum LengthBand {
  short('Short'),
  medium('Medium'),
  long('Long'),
  custom('Custom');

  const LengthBand(this.label);

  final String label;
}

/// The recommended band lengths, and the defaults the plan starts with.
///
/// Two of the three are the design's own numbers rather than mine: 300 is the
/// prototype's default for an article, and 500 is what its own example prompt
/// asks for ("Longer articles, around 500 words"). 180 is the short end — below
/// roughly that a piece stops being an article and becomes a paragraph.
///
/// They are defaults, not policy. The reader edits all three.
const int kShortWords = 180;
const int kMediumWords = 300;
const int kLongWords = 500;

class ReadingPlan {
  const ReadingPlan({
    this.reader = '',
    this.style = const <String>[],
    this.gloss = const <String>[],
    this.avoid = const <String>[],
    this.shortWords = kShortWords,
    this.mediumWords = kMediumWords,
    this.longWords = kLongWords,
    this.raw = '',
  });

  /// What the reader already knows — this is the VOCABULARY CEILING, and the
  /// single most important field: it is what lets the writer skip explaining
  /// pointers to someone who writes code.
  final String reader;

  /// How it should read.
  final List<String> style;

  /// Which words get the plain-language treatment.
  final List<String> gloss;

  /// The negative space — what to hold back. DESIGN's own note: this is the
  /// only field that can stop a fluent-but-wrong draft.
  final List<String> avoid;

  /// What each band means, in words.
  ///
  /// The reader edits these three and nothing else about length. A per-article
  /// number is still possible, but only when they ask for one — see
  /// [LengthBand.custom].
  final int shortWords;
  final int mediumWords;
  final int longWords;

  /// The reader's own words, sent VERBATIM on top of the fields. Never dropped:
  /// Ask-the-AI edits fields, it does not eat this.
  final String raw;

  /// How many fields the reader has actually set, for the Settings hub row:
  /// "2 of 8 fields set" or "nothing set — picked for you".
  ///
  /// A length counts as set when it differs from the recommendation, which is
  /// the same rule the five keyword fields use (they count when non-empty).
  int get fieldsSet {
    int n = 0;
    if (reader.trim().isNotEmpty) n++;
    if (style.isNotEmpty) n++;
    if (gloss.isNotEmpty) n++;
    if (avoid.isNotEmpty) n++;
    if (shortWords != kShortWords) n++;
    if (mediumWords != kMediumWords) n++;
    if (longWords != kLongWords) n++;
    return n;
  }

  /// How many fields there are to set, for the same row. Derived rather than
  /// written down twice, so adding a field cannot leave the row saying "of 8".
  static int get fieldCount => PlanField.values.length;

  /// What a band means in words.
  ///
  /// `custom` has no band of its own — the caller that chose it is holding an
  /// exact number and must use that instead. Returning the medium length here
  /// rather than throwing keeps this total; the caller is the one that knows.
  int wordsFor(LengthBand band) => switch (band) {
        LengthBand.short => shortWords,
        LengthBand.medium => mediumWords,
        LengthBand.long => longWords,
        LengthBand.custom => mediumWords,
      };

  /// Which band a number of words came from, or [LengthBand.custom] when it
  /// matches none of them. Used to label a card honestly after a reroll.
  LengthBand bandFor(int words) {
    if (words == shortWords) return LengthBand.short;
    if (words == mediumWords) return LengthBand.medium;
    if (words == longWords) return LengthBand.long;
    return LengthBand.custom;
  }

  ReadingPlan copyWith({
    String? reader,
    List<String>? style,
    List<String>? gloss,
    List<String>? avoid,
    int? shortWords,
    int? mediumWords,
    int? longWords,
    String? raw,
  }) =>
      ReadingPlan(
        reader: reader ?? this.reader,
        style: style ?? this.style,
        gloss: gloss ?? this.gloss,
        avoid: avoid ?? this.avoid,
        shortWords: shortWords ?? this.shortWords,
        mediumWords: mediumWords ?? this.mediumWords,
        longWords: longWords ?? this.longWords,
        raw: raw ?? this.raw,
      );

  /// The prompt block the writer receives. Structure first, then the reader's
  /// own words verbatim on top — DESIGN's rule, so nothing typed is ever lost.
  String toPrompt() {
    final StringBuffer b = StringBuffer();
    if (reader.trim().isNotEmpty) {
      b.writeln('The reader is: $reader');
    }
    if (style.isNotEmpty) {
      b.writeln('How it should read: ${style.join('; ')}');
    }
    if (gloss.isNotEmpty) {
      b.writeln('Explain these plainly: ${gloss.join('; ')}');
    }
    if (avoid.isNotEmpty) {
      b.writeln('Hold all of this back: ${avoid.join('; ')}');
    }
    // The three bands, not one number. Which band this particular article uses
    // is the caller's business and is stated separately — a plan that named a
    // single length would be a plan that cannot answer "how long" for the next
    // article, which is exactly what it was being asked.
    //
    // Nothing here mentions how many words to MARK. That is the writer's
    // judgement now; see difficulty.dart for why.
    b.writeln('A short article runs about $shortWords words, a medium one about '
        '$mediumWords, and a long one about $longWords.');
    if (raw.trim().isNotEmpty) {
      b.writeln();
      b.writeln('In the reader\'s own words, verbatim:');
      b.writeln(raw.trim());
    }
    return b.toString();
  }
}

/// One proposed change to the plan, shown as a diff.
///
/// "Your plan changed" is a claim, and a claim you cannot SEE is the same
/// failure this whole project exists to avoid — the same reason a tapped word
/// shows the English gloss before the Chinese. So the proposal is held aside and
/// nothing is written until the reader accepts.
class PlanChange {
  const PlanChange({
    required this.field,
    required this.was,
    required this.now,
  });

  /// Null when the field was previously unset, which reads as "added" rather
  /// than "changed".
  final PlanField? field;

  final String was;
  final String now;

  bool get isAddition => field == null;

  String get fieldLabel => field?.label ?? 'added';
}

/// A rewrite held aside, not applied.
///
/// Invariant of the interaction, not of the data: editing the request again
/// INVALIDATES the diff, because a diff for a request the reader changed is a
/// lie about what they asked.
class PlanRewrite {
  PlanRewrite({required this.proposal, required this.changes});

  final ReadingPlan proposal;
  final List<PlanChange> changes;

  /// True once the reader has touched the request again. The sheet then says
  /// "start again from a clean sheet" and the Apply button disappears.
  bool isStale = false;

  void invalidate() => isStale = true;

  /// Accept it. This is the only path that mutates a plan from an AI rewrite.
  ///
  /// [edited] is the proposal with the reader's own field adjustments on top,
  /// when they made any: the sheet lets them correct a proposed value in place
  /// before accepting, and what lands is what they SAW — not the snapshot the
  /// model sent.
  ReadingPlan apply({ReadingPlan? edited}) {
    if (isStale) {
      throw StateError(
          'a stale diff must not be applied: it describes a request the reader '
          'no longer has');
    }
    return edited ?? proposal;
  }
}