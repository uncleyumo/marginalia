// The repository: everything the UI needs, and nothing about how it is stored.
//
// The split matters. `lib/domain/` holds the rules and imports nothing; this
// layer knows about SQLite and the dictionary file; the widgets know about
// neither. DESIGN's "one source of truth" is enforced here, by making every
// derived figure a query rather than a stored column.
//
// Every write that touches counts goes through here, so there is exactly one
// place where "reads is incremented but the article is not removed" can be
// implemented — and therefore exactly one place it can be got wrong.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/library.dart';
import '../domain/models.dart';
import '../domain/plan.dart';

import '../domain/queue.dart';
import '../domain/word_pool.dart';
import 'database.dart' as drift;
import 'database.dart' hide DayLogRow;

/// Storage and derivation in one place.
class LibraryRepository {
  LibraryRepository(this.db);

  final AppDatabase db;

  // ── queue ─────────────────────────────────────────────────────────────

  /// Load the queue. If it is short (a first run, or a row lost to a crash),
  /// top it up with FREE plans — never with articles, because writing costs
  /// money and only a tap may do that.
  Future<Queue> loadQueue({required QueueSlot Function() planFactory}) async {
    final List<QueueRow> rows = await db.select(db.queueRows).get();

    // The ledger carries the human-facing facts — the real title, the word count,
    // the minutes. The queue row only knows an identity, and putting that identity
    // on screen produced a card titled "a-sample-pointers" with "0 words · 0 min
    // read" under it, which is the database talking to the reader.
    final List<LedgerRow> ledger = await db.select(db.ledgerRows).get();
    final Map<String, LedgerRow> byId = <String, LedgerRow>{
      for (final LedgerRow l in ledger) l.articleId: l,
    };

    final List<QueueSlot> slots = <QueueSlot>[];

    for (final QueueRow r in rows) {
      final String state = r.state;
      Article? article;
      if (state == 'ready') {
        // The article body lives in a file; this layer only needs the identity
        // and the counters, which the ledger already holds.
        final LedgerRow? meta = byId[r.articleId];
        article = Article(
          id: r.articleId,
          title: meta?.title ?? r.articleId,
          topic: meta?.topic.isNotEmpty == true ? meta!.topic : r.topic,
          sentences: const <Sentence>[],
          marks: const <Mark>[],
          // Word count and minutes come from the article body, which
          // main.dart resolves. Storing them here would mean a schema change
          // and a second copy of a fact that already exists.
          wordCount: 0,
          minuteEstimate: 0,
        );
      }
      slots.add(QueueSlot(
        articleId: r.articleId,
        state: state == 'ready' ? SlotState.ready : SlotState.planned,
        article: article,
        topic: r.topic,
        focus: r.focus,
        plannedWords: r.plannedWords,
        plannedMarked: r.plannedMarked,
        isWriting: r.isWriting,
      ));
    }

    final Queue queue = Queue(slots);
    if (queue.length < 3) {
      queue.autoFill(planFactory);
      await _persistSlots(queue);
    }
    return queue;
  }

  /// Write the in-memory queue back. A single transaction, so a crash mid-way
  /// cannot leave two rows for one slot.
  Future<void> saveQueue(Queue queue) => _persistSlots(queue);

  /// Install a bundled sample into a slot.
  ///
  /// This is the one path that turns a plan into an article WITHOUT a tap and
  /// WITHOUT spending money, and both facts matter. It is not a writer call: the
  /// article already exists on the phone, so nothing was generated and nothing
  /// was paid. It runs once, on first launch, so the app never opens empty.
  Future<void> installSample({
    required int index,
    required String articleId,
    required String title,
    required String topic,
    required int kilobytes,
  }) async {
    if (index < 0 || index >= 3) return;
    final QueueRow? row = await (db.select(db.queueRows)
          ..where(($QueueRowsTable t) => t.id.equals(index)))
        .getSingleOrNull();
    if (row == null) return;

    await (db.update(db.queueRows)..where(($QueueRowsTable t) => t.id.equals(index)))
        .write(QueueRowsCompanion(
      articleId: Value(articleId),
      state: Value('ready'),
      topic: Value(topic),
      isWriting: const Value(false),
    ));

    // record the size so the storage bar is honest about what is on the phone
    final LedgerRow? existing = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.ledgerRows).insert(
            LedgerRowsCompanion.insert(
              articleId: articleId,
              title: title,
              topic: Value(topic),
              kilobytes: Value(kilobytes),
            ),
          );
    } else if (existing.kilobytes == 0) {
      await (db.update(db.ledgerRows)
            ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
          .write(LedgerRowsCompanion(kilobytes: Value(kilobytes)));
    }
  }

  /// Which slots have never held an article. Used to decide where a sample goes,
  /// so an existing reading history is never overwritten.
  Future<List<int>> emptySlotIndices() async {
    final List<QueueRow> rows = await db.select(db.queueRows).get();
    return <int>[
      for (final QueueRow r in rows)
        if (r.state != 'ready') r.id,
    ];
  }

  /// Whether a sample has already been installed. Keyed by article id, so
  /// adding a second sample does not re-install the first.
  Future<bool> sampleInstalled(String articleId) async {
    final String? v = await setting('sample:$articleId');
    return v == '1';
  }

  Future<void> markSampleInstalled(String articleId) =>
      setSetting('sample:$articleId', '1');

  Future<void> _persistSlots(Queue queue) async {
    await db.transaction(() async {
      for (int i = 0; i < queue.slots.length; i++) {
        final QueueSlot s = queue.slots[i];
        // insertOnConflictUpdate, NOT insert.
        //
        // The queue trigger refuses an INSERT once three rows exist, and a
        // plain `insert` of an existing id is still an INSERT as far as SQLite
        // is concerned. Writing the three slots back after installing a sample
        // therefore aborted inside the transaction, and because nothing awaited
        // that future the boot simply stopped: the app sat on its wordmark with
        // no error anywhere. REPLACE does not fire a BEFORE INSERT trigger the
        // same way, and the row count never changes either.
        await db.into(db.queueRows).insertOnConflictUpdate(
              QueueRowsCompanion.insert(
                id: Value(i),
                articleId: s.articleId,
                state: s.state.name,
                topic: Value(s.topic),
                focus: Value(s.focus),
                plannedWords: Value(s.plannedWords),
                plannedMarked: Value(s.plannedMarked),
                isWriting: Value(s.isWriting),
                position: i,
              ),
            );
      }
    });
  }

  // ── counts: the two writes that must never touch anything else ───────

  /// Count one full read.
  ///
  /// Invariant 3: the article STAYS. There is no delete here, and no path from
  /// this method to one. Invariant 4: only the two counters move.
  Future<void> countRead({
    required String articleId,
    required String title,
    required String topic,
    required String day,
    required int minutes,
  }) async {
    await db.transaction(() async {
      // the ledger row: the article's own totals
      final LedgerRow? existing = await (db.select(db.ledgerRows)
            ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
          .getSingleOrNull();

      if (existing == null) {
        await db.into(db.ledgerRows).insert(
              LedgerRowsCompanion.insert(
                articleId: articleId,
                title: title,
                topic: Value(topic),
                reads: const Value(1),
              ),
            );
      } else {
        await (db.update(db.ledgerRows)
              ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
            .write(LedgerRowsCompanion(reads: Value(existing.reads + 1)));
      }

      // the day row: the ONLY record of what happened, from which the calendar
      // and *Most revisited* are both derived
      final drift.DayLogRow? dayRow = await (db.select(db.dayLogRows)
            ..where(($DayLogRowsTable t) =>
                t.day.equals(day) & t.articleId.equals(articleId)))
          .getSingleOrNull();

      if (dayRow == null) {
        await db.into(db.dayLogRows).insert(
              DayLogRowsCompanion.insert(
                day: day,
                articleId: articleId,
                title: title,
                reads: const Value(1),
                minutes: Value(minutes),
              ),
            );
      } else {
        await (db.update(db.dayLogRows)
              ..where(($DayLogRowsTable t) =>
                  t.day.equals(day) & t.articleId.equals(articleId)))
            .write(DayLogRowsCompanion(
              reads: Value(dayRow.reads + 1),
              minutes: Value(dayRow.minutes + minutes),
            ));
      }
    });
  }

  /// Count one listen. Deliberately does NOT touch `reads`: hearing an article
  /// is not reading it, and a record that claims otherwise is a lie the reader
  /// cannot detect but will believe.
  Future<void> countListen({
    required String articleId,
    required String title,
    required String day,
  }) async {
    await db.transaction(() async {
      final LedgerRow? existing = await (db.select(db.ledgerRows)
            ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
          .getSingleOrNull();
      if (existing == null) {
        await db.into(db.ledgerRows).insert(
              LedgerRowsCompanion.insert(
                articleId: articleId,
                title: title,
                listens: const Value(1),
              ),
            );
      } else {
        await (db.update(db.ledgerRows)
              ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
            .write(LedgerRowsCompanion(listens: Value(existing.listens + 1)));
      }

      final drift.DayLogRow? dayRow = await (db.select(db.dayLogRows)
            ..where(($DayLogRowsTable t) =>
                t.day.equals(day) & t.articleId.equals(articleId)))
          .getSingleOrNull();
      if (dayRow == null) {
        await db.into(db.dayLogRows).insert(
              DayLogRowsCompanion.insert(
                day: day,
                articleId: articleId,
                title: title,
                listens: const Value(1),
              ),
            );
      } else {
        await (db.update(db.dayLogRows)
              ..where(($DayLogRowsTable t) =>
                  t.day.equals(day) & t.articleId.equals(articleId)))
            .write(DayLogRowsCompanion(listens: Value(dayRow.listens + 1)));
      }
    });
  }

  /// Put a freshly written article in the ledger.
  ///
  /// Distinct from `countRead`: writing is NOT reading, so this creates the row
  /// with a zero read count and the article's real size. The queue write and the
  /// ledger write happen together in `_write`, because a card that says `ready`
  /// while the shelf has never heard of the article is a card pointing at nothing.
  Future<void> recordLedger({
    required String articleId,
    required String title,
    required String topic,
    required int kilobytes,
  }) async {
    final LedgerRow? existing = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    if (existing != null) {
      if (existing.kilobytes == 0) {
        await (db.update(db.ledgerRows)
              ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
            .write(LedgerRowsCompanion(kilobytes: Value(kilobytes)));
      }
      return;
    }
    await db.into(db.ledgerRows).insert(
          LedgerRowsCompanion.insert(
            articleId: articleId,
            title: title,
            topic: Value(topic),
            kilobytes: Value(kilobytes),
          ),
        );
  }

  /// Release an article's bytes. Invariant 4 lives here and nowhere else.
  ///
  /// `freedKilobytes` accumulates and `kilobytes` goes to zero, because the
  /// shelf must be able to keep saying "1.2 MB freed" after the size is gone.
  /// The two counters are not in scope here — they are not even parameters of
  /// this method, so there is no line that could reset them.
  Future<void> freeSpace({
    required String articleId,
    required int kilobytes,
    String reason = 'freedByUser',
  }) async {
    final LedgerRow? row = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.goneReason != null) return; // already freed; do not double-count

    await (db.update(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .write(LedgerRowsCompanion(
      kilobytes: const Value(0),
      freedKilobytes: Value(row.freedKilobytes + kilobytes),
      goneReason: Value(reason),
    ));
  }

  // ── derived reads ─────────────────────────────────────────────────────

  Future<Library> library(Queue queue) async {
    final List<LedgerRow> rows = await db.select(db.ledgerRows).get();
    return Library(
      ledger: rows.map(_toEntry).toList(),
      queue: queue,
    );
  }

  static LedgerEntry _toEntry(LedgerRow r) => LedgerEntry(
        articleId: r.articleId,
        title: r.title,
        topic: r.topic,
        reads: r.reads,
        listens: r.listens,
        kilobytes: r.kilobytes,
        freedKilobytes: r.freedKilobytes,
        goneReason: _reason(r.goneReason),
      );

  static GoneReason? _reason(String? raw) {
    if (raw == null) return null;
    if (raw == 'freedForSpace') return GoneReason.freedForSpace;
    return GoneReason.freedByUser;
  }

  /// *Most revisited*: a GROUP BY over the day rows, not a stored total.
  ///
  /// Reading one thing five times is a different act from reading five things
  /// once, and a design that could only store the second could not answer the
  /// question the reader actually has. So this is a query, every time, over the
  /// same rows the calendar reads.
  Future<List<({String title, int reads, int listens})>> mostRevisited({
    int limit = 4,
  }) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT title AS title, SUM(reads) AS reads, SUM(listens) AS listens '
          'FROM day_log_rows GROUP BY title '
          'HAVING (SUM(reads) + SUM(listens)) > 0 '
          'ORDER BY (SUM(reads) + SUM(listens)) DESC, title ASC LIMIT ?',
          variables: <Variable<Object>>[Variable<int>(limit)],
        )
        .get();
    return rows
        .map((QueryRow r) => (
              title: r.read<String>('title'),
              reads: r.read<int>('reads'),
              listens: r.read<int>('listens'),
            ))
        .toList();
  }

  /// One day's totals, for the calendar cell. The same rows, another query.
  Future<({int reads, int listens})> dayTotals(String day) async {
    final QueryRow row = await db
        .customSelect(
          'SELECT COALESCE(SUM(reads),0) AS reads, '
          'COALESCE(SUM(listens),0) AS listens '
          'FROM day_log_rows WHERE day = ?',
          variables: <Variable<Object>>[Variable<String>(day)],
        )
        .getSingle();
    return (
      reads: row.read<int>('reads'),
      listens: row.read<int>('listens'),
    );
  }

  /// Which articles were touched on one day. The SAME rows the calendar and the
  /// revisit list read, so a day's detail sheet cannot disagree with its cell.
  Future<List<({String title, int reads, int listens})>> dayArticles(
    String day,
  ) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT title AS title, SUM(reads) AS reads, SUM(listens) AS listens '
          'FROM day_log_rows WHERE day = ? '
          'GROUP BY title ORDER BY (SUM(reads) + SUM(listens)) DESC, title ASC',
          variables: <Variable<Object>>[Variable<String>(day)],
        )
        .get();
    return rows
        .map((QueryRow r) => (
              title: r.read<String>('title'),
              reads: r.read<int>('reads'),
              listens: r.read<int>('listens'),
            ))
        .toList();
  }

  /// Minutes read on one day. A stored SUM rather than a recount, because
  /// re-deriving it would need the articles and a freed article has none.
  Future<int> dayMinutes(String day) async {
    final QueryRow row = await db
        .customSelect(
          'SELECT COALESCE(SUM(minutes),0) AS minutes '
          'FROM day_log_rows WHERE day = ?',
          variables: <Variable<Object>>[Variable<String>(day)],
        )
        .getSingle();
    return row.read<int>('minutes');
  }

  /// Every day that has any activity. Future days are simply absent, which is
  /// what keeps them blank on the calendar — there is no "planned" state here
  /// and no day/night distinction to leak in.
  Future<Set<String>> activeDays() async {
    final List<QueryRow> rows =
        await db.customSelect('SELECT DISTINCT day AS day FROM day_log_rows').get();
    return rows.map((QueryRow r) => r.read<String>('day')).toSet();
  }

  // ── words ─────────────────────────────────────────────────────────────

  Future<WordPool> loadWords() async {
    final List<WordRow> rows = await db.select(db.wordRows).get();
    return WordPool(rows
        .map((WordRow r) => WordEntry(
              lemma: r.lemma,
              encounters: r.encounters,
              starred: r.starred,
              starredAtDay: r.starredAtDay,
              lastMetDay: r.lastMetDay,
            ))
        .toList());
  }

  /// Record a meeting. Reading a word in an article counts as meeting it — that
  /// IS the mechanic, and it costs nothing.
  Future<void> meetWord(String lemma, String day) async {
    final WordRow? existing = await (db.select(db.wordRows)
          ..where(($WordRowsTable t) => t.lemma.equals(lemma)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.wordRows).insert(
            WordRowsCompanion.insert(
              lemma: lemma,
              encounters: const Value(1),
              lastMetDay: Value(day),
            ),
          );
      return;
    }
    await (db.update(db.wordRows)
          ..where(($WordRowsTable t) => t.lemma.equals(lemma)))
        .write(WordRowsCompanion(
      encounters: Value(existing.encounters + 1),
      lastMetDay: Value(day),
    ));
  }

  /// Star it. The weight rises immediately and no article is ever rewritten —
  /// DESIGN is explicit: starring must not trigger generation, because that
  /// would spend money the reader did not agree to spend.
  Future<void> setStarred(String lemma, bool starred, String day) async {
    await (db.update(db.wordRows)
          ..where(($WordRowsTable t) => t.lemma.equals(lemma)))
        .write(WordRowsCompanion(
      starred: Value(starred),
      starredAtDay: Value(starred ? day : null),
    ));
  }

  // ── plan and presets ──────────────────────────────────────────────────

  Future<List<String>> presets(String kind) async {
    final List<PresetRow> rows = await (db.select(db.presetRows)
          ..where(($PresetRowsTable t) => t.kind.equals(kind))
          ..orderBy(<OrderClauseGenerator<$PresetRowsTable>>[
            ($PresetRowsTable t) => OrderingTerm.asc(t.position),
          ]))
        .get();
    return rows.map((PresetRow r) => r.label).toList();
  }

  Future<void> setPresets(String kind, List<String> labels) async {
    await db.transaction(() async {
      await (db.delete(db.presetRows)
            ..where(($PresetRowsTable t) => t.kind.equals(kind)))
          .go();
      for (int i = 0; i < labels.length; i++) {
        await db.into(db.presetRows).insert(
              PresetRowsCompanion.insert(
                id: Value(i),
                kind: kind,
                label: labels[i],
                position: i,
              ),
            );
      }
    });
  }

  // ── the reading plan ────────────────────────────────────────────────
  //
  // The plan is seven named fields plus the reader's own words. It is stored as
  // ONE row with json text for the list fields, because a plan is a single
  // object: splitting it across tables would let `topics` and `avoid` drift out
  // of step with each other, and a plan whose `avoid` list is half-migrated is a
  // plan that has quietly stopped protecting the reader.

  Future<ReadingPlan> loadPlan() async {
    final PlanRow? row = await (db.select(db.planRows)
          ..where(($PlanRowsTable t) => t.id.equals(1)))
        .getSingleOrNull();
    if (row == null) return const ReadingPlan();
    return ReadingPlan(
      reader: row.reader,
      topics: _decodeList(row.topics),
      style: _decodeList(row.style),
      gloss: _decodeList(row.gloss),
      avoid: _decodeList(row.avoid),
      length: row.length,
      marked: row.marked,
      raw: row.raw,
    );
  }

  Future<void> savePlan(ReadingPlan plan) async {
    await db.into(db.planRows).insertOnConflictUpdate(
          PlanRowsCompanion.insert(
            id: const Value(1),
            reader: Value(plan.reader),
            topics: Value(encodeList(plan.topics)),
            style: Value(encodeList(plan.style)),
            gloss: Value(encodeList(plan.gloss)),
            avoid: Value(encodeList(plan.avoid)),
            length: Value(plan.length),
            marked: Value(plan.marked),
            raw: Value(plan.raw),
          ),
        );
  }

  // ── settings ──────────────────────────────────────────────────────────

  Future<String?> setting(String key) async {
    final SettingsRow? row = await (db.select(db.settingsRows)
          ..where(($SettingsRowsTable t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await db.into(db.settingsRows).insertOnConflictUpdate(
          SettingsRowsCompanion.insert(key: key, value: value),
        );
  }

  /// The plan's list fields are stored as json text. A real table would let the
  /// two drift apart, and a plan whose `avoid` list is half-migrated is a plan
  /// that silently stops protecting the reader.
  static List<String> _decodeList(String raw) {
    try {
      final Object? v = jsonDecode(raw);
      if (v is List) return v.map((Object? e) => '$e').toList();
    } catch (_) {
      // fall through to empty
    }
    return const <String>[];
  }

  static String encodeList(List<String> v) => jsonEncode(v);
}