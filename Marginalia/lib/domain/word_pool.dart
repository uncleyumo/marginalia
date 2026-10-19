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

import 'stopwords.dart';

/// A word the reader has met, and how much the pool wants to hear it again.
class WordEntry {
  WordEntry({
    required this.lemma,
    this.encounters = 0,
    this.starred = false,
    this.starCount = 0,
    this.starDelivered = 0,
    this.starredAtDay,
    this.lastMetDay,
  }) {
    // A row written before stars had a quota says only `starred = true`.
    // Treat it as ONE showing still owed: the reader gets the repeat they
    // asked for, and the star then leaves the front of the pool instead of
    // following them around forever.
    if (starred && starCount == 0) starCount = 1;
  }

  final String lemma;

  /// How many times it has appeared in an article the reader opened. A count.
  int encounters;

  /// Whether a star campaign is still running. This is the "current star" flag
  /// the Words screen groups by; it is derived from the quota below and is
  /// cleared the moment the last owed showing has been delivered.
  bool starred;

  /// How many times the reader has starred this word, ever. Shown on the card
  /// and in the word sheet. It is also the quota of a NEW campaign: the third
  /// star asks for three showings, as the prototype does.
  int starCount;

  /// How many of the current campaign's showings have already been delivered
  /// in an article the writer landed. A count, not a date: nothing here
  /// schedules anything.
  int starDelivered;

  /// The day it was last starred, as `YYYY-MM-DD`.
  String? starredAtDay;

  /// The day it was last met, as `YYYY-MM-DD`.
  String? lastMetDay;

  /// Showings still owed in the current campaign. ZERO means the word is not
  /// in the "current star" area any more, even though [starCount] keeps the
  /// history of how often the reader asked for it.
  int get starRemaining {
    if (!starred) return 0;
    final int left = starCount - starDelivered;
    return left > 0 ? left : 0;
  }

  /// The reader starred it again.
  ///
  /// A star while a campaign is running simply raises its target: the second
  /// tap on a word that still owes one showing leaves two owed. A star after a
  /// campaign finished starts a new one, and the new campaign's target is the
  /// lifetime count — so the third star asks for three showings, not one more
  /// than the second.
  void addStar(String day) {
    if (starRemaining > 0) {
      starCount++;
    } else {
      starCount++;
      starDelivered = 0;
      starred = true;
    }
    starredAtDay = day;
  }

  /// "Stop asking for this one." The campaign ends now, and the next star
  /// starts from one again rather than inheriting a count the reader cancelled.
  void clearStar() {
    starred = false;
    starCount = 0;
    starDelivered = 0;
    starredAtDay = null;
  }

  /// One landed article was checked for this word. When it appears, the
  /// campaign owes one fewer showing; on the last one the word leaves the
  /// "current star" area.
  ///
  /// ONE ARTICLE COUNTS ONCE, however many times the word occurs in it: the
  /// promise is about how many articles it turns up in.
  bool consumeShowing(String text) {
    if (starRemaining <= 0) return false;
    if (!textUsesWord(text, lemma)) return false;
    starDelivered++;
    if (starRemaining <= 0) starred = false;
    return true;
  }

  /// The base value one encounter is worth.
  static const double encounterValue = 1.0;

  /// What a star is worth, PER SHOWING STILL OWED. Large enough to matter
  /// immediately, per DESIGN: "Star it and its weight rises NOW."
  static const double starValue = 8.0;

  static const int halfLifeDays = 7;

  /// Weight as of [today]. Half-life decay, so a word met a month ago with no
  /// star has effectively left the pool.
  double weightAsOf(String today) {
    final int owed = starRemaining;
    final double base = encounters * encounterValue +
        (owed > 0 ? starValue * owed : 0.0);
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
}

/// Whether [text] uses [lemma], allowing the ordinary inflections a writer
/// would reach for when told to use a word: plurals, past tense, -ing, adverbs,
/// and the e-drop / y-to-ies / doubled-consonant spellings.
///
/// This is deliberately a word-level check and not a substring one: `art`
/// must not be satisfied by `article`, or a star could be consumed by an
/// article that never used the word.
bool textUsesWord(String text, String lemma) {
  final String word = lemma.trim().toLowerCase();
  if (word.isEmpty) return false;
  for (final RegExpMatch m
      in RegExp(r"[a-z]+(?:'[a-z]+)?").allMatches(text.toLowerCase())) {
    if (_inflectedFrom(m.group(0)!, word)) return true;
  }
  return false;
}

bool _inflectedFrom(String token, String lemma) {
  if (token == lemma) return true;
  const List<String> suffixes = <String>[
    's', 'es', 'ed', 'd', 'ing', 'ly', 'er', 'est', 'ness',
  ];
  for (final String s in suffixes) {
    if (token == '$lemma$s') return true;
  }
  if (lemma.endsWith('e')) {
    final String stem = lemma.substring(0, lemma.length - 1);
    if (token == '${stem}ing' ||
        token == '${stem}ed' ||
        token == '${stem}er' ||
        token == '${stem}est') {
      return true;
    }
  }
  if (lemma.endsWith('y') && lemma.length > 1) {
    final String stem = lemma.substring(0, lemma.length - 1);
    if (token == '${stem}ies' ||
        token == '${stem}ied' ||
        token == '${stem}ier' ||
        token == '${stem}iest' ||
        token == '${stem}ily') {
      return true;
    }
  }
  // run → running, stop → stopped: a short vowel between two consonants
  // doubles the last one. `help` must not claim `helpped`, so all three
  // letters matter.
  if (lemma.length >= 3) {
    const String vowels = 'aeiou';
    final String last = lemma[lemma.length - 1];
    final String middle = lemma[lemma.length - 2];
    final String first = lemma[lemma.length - 3];
    if (!vowels.contains(last) &&
        vowels.contains(middle) &&
        !vowels.contains(first)) {
      final String stem = '$lemma$last';
      if (token == '${stem}ing' ||
          token == '${stem}ed' ||
          token == '${stem}er' ||
          token == '${stem}est') {
        return true;
      }
    }
  }
  return false;
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
  /// Function words are dropped on the way in.
  ///
  /// Older builds recorded every tap, including `the`, `and` and `has`, so a
  /// pool loaded from an existing database already contains them. Filtering
  /// here — rather than only at the write site — means the review list is
  /// clean on the first launch after this change, without deleting rows the
  /// reader may have starred or met deliberately.
  WordPool(Iterable<WordEntry> entries)
      : _entries = <String, WordEntry>{
          for (final WordEntry e in entries)
            if (!isStopword(e.lemma)) e.lemma: e,
        };

  final Map<String, WordEntry> _entries;

  int get length => _entries.length;

  WordEntry? operator [](String lemma) => _entries[lemma];

  /// Record a meeting and return the entry. Reading a word in an article counts
  /// as meeting it — that is the whole mechanic, and it costs nothing.
  WordEntry meet(String lemma, String day) {
    // A stopword is answered but not kept: the reader can still look it up,
    // and nothing about that lookup belongs in the review list. The throwaway
    // entry exists only so callers that read the returned value still work.
    if (isStopword(lemma)) {
      return WordEntry(lemma: lemma, lastMetDay: day)..recordEncounter(day);
    }
    final WordEntry e = _entries.putIfAbsent(
        lemma, () => WordEntry(lemma: lemma, lastMetDay: day));
    e.recordEncounter(day);
    return e;
  }

  /// The "Crucial now" list: heaviest first, decayed to today, above the
  /// threshold. Sorting by weight is what makes repetition ENGINEERED — the
  /// words that need another showing drift to the front on their own.
  ///
  /// Words with a star quota still owed sort ABOVE everything else: the reader
  /// explicitly asked for those, and a general decayed weight must not push
  /// them off a list that is capped at [limit].
  List<WordEntry> crucial(String today, {int limit = 8}) {
    final List<WordEntry> active =
        _entries.values.where((WordEntry e) => e.isActive(today)).toList();
    active.sort((WordEntry a, WordEntry b) {
      final int byStar = b.starRemaining.compareTo(a.starRemaining);
      if (byStar != 0) return byStar;
      final int byWeight = b.weightAsOf(today).compareTo(a.weightAsOf(today));
      if (byWeight != 0) return byWeight;
      // A tie is broken so the order never flickers between rebuilds.
      return a.lemma.compareTo(b.lemma);
    });
    return active.take(limit).toList();
  }

  /// The words whose star quota still owes showings, most urgent first.
  ///
  /// This is the list the writer is told to USE, as opposed to the "recently
  /// met" list it may draw on. Keeping them separate is what makes a star a
  /// promise rather than a probability.
  List<WordEntry> starredDue(String today, {int limit = 8}) {
    final List<WordEntry> due = _entries.values
        .where((WordEntry e) => e.starRemaining > 0)
        .toList();
    due.sort((WordEntry a, WordEntry b) {
      final int byRemaining = b.starRemaining.compareTo(a.starRemaining);
      if (byRemaining != 0) return byRemaining;
      final int byWeight = b.weightAsOf(today).compareTo(a.weightAsOf(today));
      if (byWeight != 0) return byWeight;
      return a.lemma.compareTo(b.lemma);
    });
    return due.take(limit).toList();
  }

  /// Everything met, newest first. NOT filtered by weight: the reader met all
  /// of them, and the list is the record of that.
  List<WordEntry> all() {
    final List<WordEntry> list = _entries.values.toList();
    list.sort(
        (WordEntry a, WordEntry b) => b.encounters.compareTo(a.encounters));
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
