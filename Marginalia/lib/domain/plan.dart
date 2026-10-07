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

/// The seven named fields, in display order. The order is the display order
/// because the prototype renders them as rows, and DESIGN insists a single
/// field must be pointable-at.
enum PlanField {
  reader('Reader', PlanFieldKind.text),
  topics('Topics', PlanFieldKind.list),
  style('Style', PlanFieldKind.list),
  gloss('Explain', PlanFieldKind.list),
  avoid('Avoid', PlanFieldKind.list),
  length('Length', PlanFieldKind.number),
  marked('Marked', PlanFieldKind.number);

  const PlanField(this.label, this.kind);

  final String label;
  final PlanFieldKind kind;
}

enum PlanFieldKind { text, list, number }

class ReadingPlan {
  const ReadingPlan({
    this.reader = '',
    this.topics = const <String>[],
    this.style = const <String>[],
    this.gloss = const <String>[],
    this.avoid = const <String>[],
    this.length = 300,
    this.marked = 6,
    this.raw = '',
  });

  /// What the reader already knows — this is the VOCABULARY CEILING, and the
  /// single most important field: it is what lets the writer skip explaining
  /// pointers to someone who writes code.
  final String reader;

  /// Where articles may come from.
  final List<String> topics;

  /// How it should read.
  final List<String> style;

  /// Which words get the plain-language treatment.
  final List<String> gloss;

  /// The negative space — what to hold back. DESIGN's own note: this is the
  /// only field that can stop a fluent-but-wrong draft.
  final List<String> avoid;

  /// Words per article. The budget that decides what actually gets written.
  final int length;

  /// Words marked at most.
  final int marked;

  /// The reader's own words, sent VERBATIM on top of the fields. Never dropped:
  /// Ask-the-AI edits fields, it does not eat this.
  final String raw;

  bool get hasContent =>
      topics.isNotEmpty ||
      style.isNotEmpty ||
      avoid.isNotEmpty ||
      raw.trim().isNotEmpty;

  /// How many fields the reader has actually set, for the Settings hub row:
  /// "2 of 7 fields set" or "nothing set — picked for you".
  int get fieldsSet {
    int n = 0;
    if (reader.trim().isNotEmpty) n++;
    if (topics.isNotEmpty) n++;
    if (style.isNotEmpty) n++;
    if (gloss.isNotEmpty) n++;
    if (avoid.isNotEmpty) n++;
    if (length != 300) n++;
    if (marked != 6) n++;
    return n;
  }

  ReadingPlan copyWith({
    String? reader,
    List<String>? topics,
    List<String>? style,
    List<String>? gloss,
    List<String>? avoid,
    int? length,
    int? marked,
    String? raw,
  }) =>
      ReadingPlan(
        reader: reader ?? this.reader,
        topics: topics ?? this.topics,
        style: style ?? this.style,
        gloss: gloss ?? this.gloss,
        avoid: avoid ?? this.avoid,
        length: length ?? this.length,
        marked: marked ?? this.marked,
        raw: raw ?? this.raw,
      );

  /// The prompt block the writer receives. Structure first, then the reader's
  /// own words verbatim on top — DESIGN's rule, so nothing typed is ever lost.
  String toPrompt() {
    final StringBuffer b = StringBuffer();
    if (reader.trim().isNotEmpty) {
      b.writeln('The reader is: $reader');
    }
    if (topics.isNotEmpty) {
      b.writeln('Topics may come from: ${topics.join(', ')}');
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
    b.writeln('About $length words, with at most $marked words marked.');
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
  ReadingPlan apply() {
    if (isStale) {
      throw StateError(
          'a stale diff must not be applied: it describes a request the reader '
          'no longer has');
    }
    return proposal;
  }
}

/// A free plan. Costs nothing: no call, no key, no time.
///
/// Two fields is the whole UI, plus one line of cost. If a screen has to be
/// explained before it can be used, the screen is wrong.
QueuePlanData planData({String topic = '', String focus = '', int words = 300, int marked = 6}) =>
    QueuePlanData(topic: topic, focus: focus, words: words, marked: marked);

class QueuePlanData {
  const QueuePlanData({
    required this.topic,
    required this.focus,
    required this.words,
    required this.marked,
  });

  final String topic;
  final String focus;
  final int words;
  final int marked;
}