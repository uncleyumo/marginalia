// The order a listening run moves in.
//
// This exists because the queue is not the listening order. The queue holds
// exactly three cards and says nothing about which comes next; the run needs an
// order that survives the queue being rewritten underneath it. An earlier
// version picked the next article from the three live slots alone, so a run
// stopped dead the moment it had heard all three — which is the whole run, and
// it took three articles to get there.
//
// So the sequence is built from EVERYTHING the phone can still speak — the live
// queue plus the shelf — and it is a RING rather than a list, because the reader
// asked for a run that does not stop.
//
// What is deliberately absent: any notion of "finished". Reading or hearing an
// article is not a state the sequence knows about (invariant 5). An article that
// has been read ten times is still in the ring; it is just further away.

import 'library.dart' show ShelfRow;

/// How the next article is chosen.
///
/// Two of these are DIRECTIONS and three are CHOICES, and the difference
/// matters: a direction moves one step from where the run currently is, so it
/// cannot repeat an article until it has been all the way round the ring. A
/// choice re-asks the question every time, so it can.
enum ListenOrder {
  /// Onward to what has waited longest. With 1 (newest) .. 5 (oldest) and the
  /// run on 3, this plays 2.
  ///
  /// The DEFAULT, and the direction a reader means by "keep going": the newest
  /// thing in the queue is the one they have not met, and a queue is a queue
  /// because what arrives should be what plays.
  onward,

  /// Backward to what arrived most recently. On 3, this plays 4.
  ///
  /// Useful when the newest card was skipped past — a rerolled plan, an article
  /// that was not what the reader wanted that morning.
  backward,

  /// Whatever has been met most. A review run.
  mostStudied,

  /// Whatever has been met least. Fresh first.
  leastStudied,

  /// A shuffle that avoids anything already met today when anything else
  /// exists, because the repeat is the one that gets skipped.
  random,
  ;

  /// The stored name. Settings persists this string, so the values are part of
  /// the app's data and must not be renamed casually.
  String get key => name;

  /// Read a stored name back, including the ones this enum replaced.
  ///
  /// `newest` and `oldest` were the two directions before they were named for
  /// what they do. `newest` sorted by descending id, which is "the card that
  /// arrived most recently" — that is [ListenOrder.backward]. `oldest` sorted
  /// ascending, which is [ListenOrder.onward]. Mapping them keeps a reader's
  /// saved preference meaning the same thing, which is the only reason to
  /// bother: an unrecognised value falling back to the default would silently
  /// reverse somebody's commute.
  static ListenOrder fromKey(String? raw) {
    switch (raw) {
      case 'newest':
        return ListenOrder.backward;
      case 'oldest':
        return ListenOrder.onward;
    }
    return ListenOrder.values.firstWhere(
      (ListenOrder o) => o.name == raw,
      orElse: () => ListenOrder.onward,
    );
  }
}

extension ListenOrderLabels on ListenOrder {
  /// The one line Settings shows. A sentence of justification here is a
  /// sentence the reader has to read past to change the setting.
  String get label => switch (this) {
        ListenOrder.onward => 'Onward',
        ListenOrder.backward => 'Backward',
        ListenOrder.mostStudied => 'Most studied',
        ListenOrder.leastStudied => 'Least studied',
        ListenOrder.random => 'Random',
      };

  /// What the choice means, in as few words as carry it.
  String get hint => switch (this) {
        ListenOrder.onward => 'to what has waited longest',
        ListenOrder.backward => 'to what arrived last',
        ListenOrder.mostStudied => 'met most first',
        ListenOrder.leastStudied => 'met least first',
        ListenOrder.random => 'a shuffle, not today’s',
      };
}

/// One entry in a run.
class SequenceEntry {
  const SequenceEntry({
    required this.articleId,
    required this.title,
    required this.lastSeenDay,
    required this.attention,
  });

  final String articleId;

  /// Carried so a debug line and a toast can name what is playing without a
  /// second lookup.
  final String title;

  /// `YYYY-MM-DD`, the day this article was last written or read. Empty on rows
  /// that predate the column, which sort as the oldest thing there is.
  final String lastSeenDay;

  /// reads + listens. "How much have I met this."
  final int attention;

  /// Newest first: the day descending, then the id descending so two articles
  /// written the same day keep a stable order rather than trading places on
  /// every rebuild.
  static int byNewest(SequenceEntry a, SequenceEntry b) {
    final int byDay = b.lastSeenDay.compareTo(a.lastSeenDay);
    if (byDay != 0) return byDay;
    return b.articleId.compareTo(a.articleId);
  }

  /// Oldest first: the same key, reversed.
  static int byOldest(SequenceEntry a, SequenceEntry b) => byNewest(b, a);

  /// Most met first. Title breaks a tie so the order is not arbitrary, and it
  /// breaks it the SAME WAY in both directions — see [byLeastStudied].
  static int byMostStudied(SequenceEntry a, SequenceEntry b) {
    final int byAttention = b.attention.compareTo(a.attention);
    if (byAttention != 0) return byAttention;
    return a.title.compareTo(b.title);
  }

  /// Least met first.
  ///
  /// Only the ATTENTION is inverted. Reversing the whole comparator — the
  /// obvious `byMostStudied(b, a)` — also reverses the title tiebreak, so two
  /// articles met the same number of times swap places between the two orders
  /// for no reason a reader could name. A tie is a tie; keep it stable and let
  /// the direction apply to the number, which is the thing being ordered.
  static int byLeastStudied(SequenceEntry a, SequenceEntry b) {
    final int byAttention = a.attention.compareTo(b.attention);
    if (byAttention != 0) return byAttention;
    return a.title.compareTo(b.title);
  }
}

/// The ring.
///
/// Built from the shelf, so it sees every article the phone can speak — not
/// only the three cards currently waiting. Rebuilt when the queue changes,
/// which is the only thing that can add or remove an entry.
class ListenSequence {
  ListenSequence(Iterable<SequenceEntry> entries, {this.current = ''})
      : _entries = List<SequenceEntry>.of(entries);

  final List<SequenceEntry> _entries;

  /// The article the run is on. Empty before anything has played, which is the
  /// state the ring starts in and not an error.
  final String current;

  List<SequenceEntry> get entries => List<SequenceEntry>.unmodifiable(_entries);

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  bool get isNotEmpty => _entries.isNotEmpty;

  /// Where the run is, as an index. -1 when it is on nothing.
  int get _currentIndex {
    if (current.isEmpty) return -1;
    return _entries.indexWhere((SequenceEntry e) => e.articleId == current);
  }

  /// Reorder by [order]. Keeps the current article's identity, so a rebuild in
  /// the middle of an article does not lose the place.
  void apply(ListenOrder order) {
    switch (order) {
      case ListenOrder.onward:
        _entries.sort(SequenceEntry.byOldest);
      case ListenOrder.backward:
        _entries.sort(SequenceEntry.byNewest);
      case ListenOrder.mostStudied:
        _entries.sort(SequenceEntry.byMostStudied);
      case ListenOrder.leastStudied:
        _entries.sort(SequenceEntry.byLeastStudied);
      case ListenOrder.random:
      // No sort: `next` draws from the ring each time. Sorting here would make
      // "random" deterministic, which is a different feature.
        break;
    }
  }

  /// The next article, or null when the ring is empty.
  ///
  /// THREE KINDS OF ANSWER, and they are genuinely different:
  ///
  ///  · a DIRECTION steps one place from where the run is, and wraps. It cannot
  ///    repeat an article until it has been all the way round the ring.
  ///  · a STUDY order picks the best article that is not the one playing. It
  ///    re-asks every time, so it CAN repeat one before the ring is exhausted.
  ///  · RANDOM draws, skipping today's when anything else exists.
  ///
  /// [today] is only consulted by [ListenOrder.random].
  String? next(ListenOrder order, String today) {
    if (_entries.isEmpty) return null;
    if (_entries.length == 1) {
      // One article in the ring: playing it again is the only thing a run can
      // do, and the alternative is stopping — which is what this class exists
      // to prevent.
      return _entries.first.articleId;
    }

    apply(order);

    final int at = _currentIndex;
    if (at < 0) {
      // Nothing playing yet. The top of the order is the honest start: for
      // `onward` that is the article that has waited longest, for `mostStudied`
      // the one met most, and so on.
      return _entries.first.articleId;
    }

    switch (order) {
      case ListenOrder.random:
        return _drawAvoidingToday(at, today);
      case ListenOrder.mostStudied:
      case ListenOrder.leastStudied:
        // The sort put the BEST article at index 0. If the current one is it,
        // the runner-up is index 1 — and stepping to index 0 would replay the
        // article the reader is already listening to, which is not what "most
        // studied" means.
        return _entries[at == 0 ? 1 : 0].articleId;
      case ListenOrder.onward:
      case ListenOrder.backward:
        // A direction steps one place, and wraps at both ends.
        //
        // [apply] sorts so that the direction of TRAVEL points at index 0:
        // `onward` puts the oldest article first, `backward` puts the newest
        // first. So the next article is always the neighbour toward the FRONT,
        // and wrapping past index 0 lands on the end of the list — which is the
        // far side of the ring, exactly where a run should continue.
        //
        // One expression for both directions, because the sort already encoded
        // which way "forward" means. Getting this backwards makes `onward` play
        // the NEWER article, which is `backward`'s job, and the two orders swap
        // places silently — which is why the invariant checks pin the 3 → 2 and
        // 3 → 4 cases rather than trusting this comment.
        return _entries[(at - 1 + _entries.length) % _entries.length].articleId;
    }
  }

  /// A draw that skips today's when anything else exists.
  ///
  /// The repeat is the one to skip, and only when there is something to skip
  /// TO — a ring where everything has been met today should still play, rather
  /// than stopping and calling that a rule.
  ///
  /// The draw is seeded from the ring's own size and the current index rather
  /// than from a clock, so the same state gives the same answer and a rebuild
  /// does not reshuffle underneath a listener.
  String _drawAvoidingToday(int at, String today) {
    final List<int> fresh = <int>[
      for (int i = 0; i < _entries.length; i++)
        if (i != at && _entries[i].lastSeenDay != today) i,
    ];
    final List<int> pool =
        fresh.isNotEmpty ? fresh : <int>[for (int i = 0; i < _entries.length; i++) if (i != at) i];
    if (pool.isEmpty) return _entries[at].articleId;
    final int seed = (_entries.length * 31 + at * 17 + today.length) % pool.length;
    return _entries[pool[seed]].articleId;
  }

  /// A copy on a different article. The ring is rebuilt rather than mutated
  /// when the queue changes, because the set of speakable articles is what
  /// changed — patching one field would leave the order stale.
  ListenSequence on(String articleId) => ListenSequence(_entries, current: articleId);
}

/// Build the ring from the shelf.
///
/// The shelf is the right source and not the queue: it is ledger ∪ live queue
/// (`Library.shelf()`), it already excludes freed articles' bytes while keeping
/// their rows, and it is keyed by articleId — the one key every other query in
/// the app uses. A ring built from the three live slots is the bug this file
/// exists to fix.
///
/// A row with no body is still in the ring. It has been paid for, its counts
/// stand, and the only thing wrong with it is that the bytes were freed — which
/// the reader can undo with one tap. Dropping it from the run would drop the
/// article the reader is most likely to want back.
ListenSequence listenSequenceOf(Iterable<ShelfRow> shelf) {
  return ListenSequence(<SequenceEntry>[
    for (final ShelfRow r in shelf)
      SequenceEntry(
        articleId: r.articleId,
        title: r.title,
        lastSeenDay: r.lastSeenDay,
        attention: r.attention,
      ),
  ]);
}
