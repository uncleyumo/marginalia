// The word pool — repetition engineered, not assigned.
//
// This file replaces spaced repetition entirely. Nothing here schedules a word
// for a day, asks whether the reader knows it, or reports a retention rate. A
// word's weight decays; the writer simply draws harder from the heavy end. So
// the app makes sure a word SHOWS UP AGAIN without ever claiming the reader has
// learnt it.
//
// Weights fall by half every [halfLifeDays]. That is a modelling choice, not a
// finding: it is the standard exponential-decay form, chosen because it needs
// no scheduler (no WorkManager, no timer) — the weight is computed from the
// elapsed days whenever it is read. A number that decays on its own is a
// function, not a job.

/// A word the reader has met, and how much the pool wants to hear it again.
class WordEntry {
  WordEntry({
    required this.lemma,
    this.encounters = 0,
    this.starred = false,
    this.starredAtDay,
    this.lastMetDay,
  });

  final String lemma;

  /// How many times it has appeared in an article the reader opened. A count.
  int encounters;

  /// The reader asked to see it again. This raises its weight IMMEDIATELY and
  /// holds it in the pool — it never schedules anything, and never rewrites an
  /// article that already exists.
  bool starred;

  /// The day it was starred, as `YYYY-MM-DD`.
  String? starredAtDay;

  /// The day it was last met, as `YYYY-MM-DD`.
  String? lastMetDay;

  /// The base value one encounter is worth.
  static const double encounterValue = 1.0;

  /// What a star is worth. Large enough to matter immediately, per DESIGN:
  /// "Star it and its weight rises NOW."
  static const double starValue = 8.0;

  static const int halfLifeDays = 7;

  /// Weight as of [today]. Half-life decay, so a word met a month ago with no
  /// star has effectively left the pool.
  double weightAsOf(String today) {
    final double base =
        encounters * encounterValue + (starred ? starValue : 0.0);
    if (base == 0) return 0;

    final int age = daysBetween(lastMetDay, today);
    if (age <= 0) return base;
    // The factor is DECREASING in age: 1.0 today, ~0.5 at one half-life,
    // ~0.25 at two. An earlier version of this multiplied instead of
    // dividing, so a word's weight GREW the longer it went unread — which
    // would have made the pool a record of neglect rather than of need.
    return base * _decay(age);
  }

  /// The decay factor for [ageDays]: 0.5^(age/halfLife).
  static double _decay(int ageDays) {
    final double x = ageDays / halfLifeDays;
    // Split so the integer exponent is exact and only the fraction needs
    // approximating: 0.5^3 = 0.125 exactly, not 0.1250000001.
    final int whole = x.floor();
    final double frac = x - whole;
    double result = 1.0;
    for (int i = 0; i < whole; i++) {
      result *= 0.5;
    }
    return result * _powHalfFraction(frac);
  }

  /// 0.5^frac for frac in [0,1), via exp(-frac * ln2) expanded as a series.
  /// Accurate to well under 1e-9 over that range, which is far tighter than a
  /// word weight ever needs to be.
  static double _powHalfFraction(double frac) {
    const double ln2 = 0.6931471805599453;
    final double x = -frac * ln2;
    double term = 1.0;
    double sum = 1.0;
    for (int i = 1; i < 12; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }

  /// Whether the word still belongs on the "Crucial now" list.
  ///
  /// The threshold is what stops the list becoming a warehouse. A word that has
  /// decayed past it is not deleted — the reader met it, and that is recorded —
  /// it simply stops competing for space in a short list.
  static const double activeThreshold = 0.5;

  bool isActive(String today) => weightAsOf(today) >= activeThreshold;

  void recordEncounter(String day) {
    encounters++;
    lastMetDay = day;
  }

  void setStarred(bool value, String today) {
    starred = value;
    starredAtDay = value ? today : null;
  }
}

/// Days from [from] to [to], both `YYYY-MM-DD`. Returns 0 when either is null
/// or unparseable, so a malformed date degrades to "no decay" rather than to a
/// negative weight.
int daysBetween(String? from, String? to) {
  if (from == null || to == null) return 0;
  final DateTime? a = _parseDay(from);
  final DateTime? b = _parseDay(to);
  if (a == null || b == null) return 0;
  final int d = b.difference(a).inDays;
  return d < 0 ? 0 : d;
}

DateTime? _parseDay(String s) {
  final List<String> parts = s.split('-');
  if (parts.length != 3) return null;
  final int? y = int.tryParse(parts[0]);
  final int? m = int.tryParse(parts[1]);
  final int? d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

/// Today's day string in LOCAL time — the calendar is the reader's, not UTC's.
/// A history row must not shift when the phone crosses a timezone.
String todayDay([DateTime? now]) {
  final DateTime t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// The pool, ordered by how much the reader needs to hear a word again.
class WordPool {
  WordPool(Iterable<WordEntry> entries)
      : _entries = <String, WordEntry>{
          for (final WordEntry e in entries) e.lemma: e,
        };

  final Map<String, WordEntry> _entries;

  int get length => _entries.length;

  WordEntry? operator [](String lemma) => _entries[lemma];

  /// Record a meeting and return the entry. Reading a word in an article counts
  /// as meeting it — that is the whole mechanic, and it costs nothing.
  WordEntry meet(String lemma, String day) {
    final WordEntry e = _entries.putIfAbsent(
        lemma, () => WordEntry(lemma: lemma, lastMetDay: day));
    e.recordEncounter(day);
    return e;
  }

  /// The "Crucial now" list: heaviest first, decayed to today, above the
  /// threshold. Sorting by weight is what makes repetition ENGINEERED — the
  /// words that need another showing drift to the front on their own.
  List<WordEntry> crucial(String today, {int limit = 8}) {
    final List<WordEntry> active = _entries.values
        .where((WordEntry e) => e.isActive(today))
        .toList();
    active.sort((WordEntry a, WordEntry b) {
      final int byWeight =
          b.weightAsOf(today).compareTo(a.weightAsOf(today));
      if (byWeight != 0) return byWeight;
      // A tie is broken so the order never flickers between rebuilds.
      return a.lemma.compareTo(b.lemma);
    });
    return active.take(limit).toList();
  }

  /// Everything met, newest first. NOT filtered by weight: the reader met all
  /// of them, and the list is the record of that.
  List<WordEntry> all() {
    final List<WordEntry> list = _entries.values.toList();
    list.sort((WordEntry a, WordEntry b) => b.encounters.compareTo(a.encounters));
    return list;
  }
}

/// The word's own probability of being picked, normalised across the pool.
///
/// This is a bar on a screen, and DESIGN is explicit about what it is: "how
/// likely the word is picked — not a promise of which day". So it returns a
/// weight, never a date.
double selectionChance(WordEntry word, Iterable<WordEntry> pool, String today) {
  final double total =
      pool.fold(0.0, (double sum, WordEntry e) => sum + e.weightAsOf(today));
  if (total <= 0) return 0;
  return word.weightAsOf(today) / total;
}