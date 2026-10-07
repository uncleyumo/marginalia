// The Library is DERIVED, never stored.
//
// There is no library table. The shelf is the ledger UNION the live queue, keyed
// by title — the prototype's `shelf()`. Two earlier mistakes are corrected here:
// the first deleted an article the moment the reader said they were done with
// it, keeping only a number, which satisfied a counter and lost the thing
// itself; the second treated deletion as all-or-nothing. Neither was necessary.
//
// A DELETED article also stays on this list, struck through, still counted.
// "I read it five times" is history, and history does not require the file to
// still be there. Hiding the row would hide the FACT that the file is gone,
// leaving the reader to meet a remembered article with no explanation.

import 'models.dart';
import 'queue.dart';

/// The storage budget the shelf's bar is measured against. An article is a few
/// KB of text plus a few hundred KB of audio, and audio is ~95% of it; ~12 MB
/// of audio is roughly 35 articles. Showing the number turns "free this one"
/// into a decision instead of a guess.
const int kStorageBudgetKb = 12000;

/// One row on the shelf.
class ShelfRow {
  const ShelfRow({
    required this.articleId,
    required this.title,
    required this.topic,
    required this.meta,
    required this.reads,
    required this.listens,
    required this.kilobytes,
    required this.freedKilobytes,
    required this.isLive,
    required this.isGone,
  });

  /// The ledger's key. Freeing space writes to this row, so a screen that only
  /// carries the title cannot address it.
  final String articleId;

  final String title;
  final String topic;

  /// The quiet line under the title: length and time. Deliberately does NOT
  /// repeat the topic — a topic badge beside a title that already says it is
  /// noise, and DESIGN's shelf rule is one title line, one meta line, numbers
  /// in a fixed column, state on the spine.
  final String meta;

  final int reads;
  final int listens;

  /// Bytes on the phone right now. Zero for a freed row.
  final int kilobytes;

  /// KB this row has reclaimed. Zero while the article still exists. Carried
  /// separately because the shelf must keep saying "1.2 MB freed" AFTER the
  /// size itself is gone — zeroing both together would leave the reader unable
  /// to account for what happened.
  final int freedKilobytes;

  /// Still in the queue, so it can be opened.
  final bool isLive;

  /// Bytes freed. The row remains, still counted.
  final bool isGone;

  /// Attention: what the reader actually came back for. Never a verdict.
  int get attention => reads + listens;
}

/// The filters. Each is a QUESTION worth asking, not a state to manage.
enum LibraryFilter {
  all('All'),
  reading('Worth reading again'),
  unread('Never read'),
  heard('Heard but not read'),
  gone('Deleted');

  const LibraryFilter(this.label);

  final String label;

  bool matches(ShelfRow r) => switch (this) {
        LibraryFilter.all => true,
        // came back more than once
        LibraryFilter.reading => r.reads >= 2,
        LibraryFilter.unread => r.reads == 0 && !r.isGone,
        // heard on the commute, never opened
        LibraryFilter.heard => r.reads == 0 && r.listens > 0,
        LibraryFilter.gone => r.isGone,
      };
}

/// Builds the shelf. The single source of the list.
class Library {
  Library({
    required Iterable<LedgerEntry> ledger,
    required Queue queue,
  })  : _ledger = {for (final LedgerEntry e in ledger) e.title: e},
        _queue = queue;

  final Map<String, LedgerEntry> _ledger;
  final Queue _queue;

  /// shelf() = LEDGER ∪ live QUEUE, keyed by title.
  ///
  /// A queued article merges into an existing ledger row rather than replacing
  /// it, so the counts do not restart when an article re-enters the queue.
  List<ShelfRow> shelf() {
    final Map<String, ShelfRow> seen = <String, ShelfRow>{};

    for (final LedgerEntry e in _ledger.values) {
      seen[e.title] = ShelfRow(
        articleId: e.articleId,
        title: e.title,
        topic: e.topic,
        meta: '',
        reads: e.reads,
        listens: e.listens,
        kilobytes: e.kilobytes,
        freedKilobytes: e.freedKilobytes,
        isLive: false,
        isGone: e.isGone,
      );
    }

    for (final QueueSlot slot in _queue.slots) {
      final Article? a = slot.article;
      if (a == null) continue; // planned: there is nothing to shelve yet
      final ShelfRow existing = seen[a.title] ??
          ShelfRow(
            articleId: a.id,
            title: a.title,
            topic: a.topic,
            meta: '',
            reads: 0,
            listens: 0,
            kilobytes: 0,
            freedKilobytes: 0,
            isLive: false,
            isGone: false,
          );
      seen[a.title] = ShelfRow(
        articleId: existing.articleId.isEmpty ? a.id : existing.articleId,
        title: a.title,
        topic: existing.topic.isEmpty ? a.topic : existing.topic,
        meta: '${a.wordCount} words · ${a.minuteEstimate} min',
        // a live article's bytes come from the ledger if it has one
        reads: existing.reads,
        listens: existing.listens,
        kilobytes: existing.kilobytes,
        freedKilobytes: existing.freedKilobytes,
        isLive: true,
        isGone: existing.isGone,
      );
    }

    final List<ShelfRow> rows = seen.values.toList();
    // gone last, then by attention, then alphabetically for a stable order.
    //
    // Not "live first": the prototype's comparator is gone, then reads+listens,
    // then title, and matching it exactly matters more than my own preference.
    // A freed article therefore keeps its place by attention among the rest and
    // sinks to the bottom of the list — the reader did not delete it because it
    // stopped mattering, and the order should not imply that it did.
    rows.sort((ShelfRow a, ShelfRow b) {
      final int byGone = (a.isGone ? 1 : 0).compareTo(b.isGone ? 1 : 0);
      if (byGone != 0) return byGone;
      final int byAttention = b.attention.compareTo(a.attention);
      if (byAttention != 0) return byAttention;
      return a.title.compareTo(b.title);
    });
    return rows;
  }

  /// Search matches title AND topic — the reader types "pointer" or "NVDA" or
  /// "music" and the shelf narrows as they type.
  List<ShelfRow> search(String query, LibraryFilter filter) {
    final String q = query.trim().toLowerCase();
    return shelf()
        .where((ShelfRow r) => filter.matches(r))
        .where((ShelfRow r) =>
            q.isEmpty || r.title.toLowerCase().contains(q) ||
            r.topic.toLowerCase().contains(q))
        .toList();
  }

  /// Bytes actually on the phone for articles that still exist.
  int get usedKb =>
      shelf().where((ShelfRow r) => !r.isGone).fold(0, (int s, ShelfRow r) => s + r.kilobytes);

  int get freedKb => shelf()
      .where((ShelfRow r) => r.isGone)
      .fold(0, (int s, ShelfRow r) => s + r.freedKilobytes);

  int get goneCount => shelf().where((ShelfRow r) => r.isGone).length;

  double get budgetUsed =>
      kStorageBudgetKb == 0 ? 0 : usedKb / kStorageBudgetKb;
}

/// *Most revisited*: which articles the reader kept coming back to.
///
/// Derived from the SAME day rows as the calendar, by GROUP BY on the article.
/// Reading one thing five times is a different act from reading five things
/// once, and a design that could only store the second one could not answer the
/// question the reader actually has.
class Revisited {
  Revisited(Iterable<DayLogRow> rows) : _rows = List<DayLogRow>.of(rows);

  final List<DayLogRow> _rows;

  List<DayLogRow> mostRevisited({int limit = 4}) {
    final Map<String, DayLogRow> merged = <String, DayLogRow>{};
    for (final DayLogRow r in _rows) {
      final DayLogRow m = merged[r.title] ??
          DayLogRow(day: r.day, articleId: r.articleId, title: r.title);
      m.reads += r.reads;
      m.listens += r.listens;
      merged[r.title] = m;
    }
    final List<DayLogRow> list = merged.values.toList()
      ..removeWhere((DayLogRow r) => r.reads + r.listens == 0)
      ..sort((DayLogRow a, DayLogRow b) {
        final int byAttention =
            (b.reads + b.listens).compareTo(a.reads + a.listens);
        if (byAttention != 0) return byAttention;
        return a.title.compareTo(b.title);
      });
    return list.take(limit).toList();
  }

  /// Total touches on one day, for the calendar cell's number.
  static ({int reads, int listens}) dayTotals(List<DayLogRow> rows, String day) {
    int reads = 0;
    int listens = 0;
    for (final DayLogRow r in rows) {
      if (r.day != day) continue;
      reads += r.reads;
      listens += r.listens;
    }
    return (reads: reads, listens: listens);
  }
}

/// Bytes, formatted the way the shelf states them: `2.2 MB of 11.7 MB`.
String formatKb(int kb) {
  if (kb >= 1024) {
    final String v = (kb / 1024).toStringAsFixed(1);
    return '$v MB';
  }
  return '$kb KB';
}

/// The confirmation copy for freeing space, split into what GOES and what STAYS.
///
/// "Delete" alone would be a lie of omission, because the app has promised
/// repeatedly that nothing is ever deleted and now has a button that says
/// delete. So the trade is shown in two colour-coded columns BEFORE it happens.
class FreeSpaceTrade {
  const FreeSpaceTrade({
    required this.kilobytes,
    required this.reads,
    required this.listens,
  });

  final int kilobytes;
  final int reads;
  final int listens;

  List<String> get goes => <String>['the text', 'the audio'];

  String get freed => '${formatKb(kilobytes)} freed';

  List<String> get stays =>
      <String>['read $reads×', 'heard $listens×'];

  String get staysNote => 'it stays on this list, marked as deleted';

  /// One sentence in the reader's own numbers.
  String get why => 'You read it $reads×. That happened, and it is still '
      'counted in your history and in Most revisited after this. Only the file '
      'goes. If you want it back, it is one Write it again.';
}