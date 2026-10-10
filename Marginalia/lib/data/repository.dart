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

import '../domain/instruction.dart';
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
  ///
  /// A ready slot is hydrated from `article_rows`, so the card comes back with
  /// its REAL body: its word count, its reading time, its difficulty and its
  /// keywords. It used to come back as a stub with `wordCount: 0`, which put
  /// `0 words · 0 min read` on the card and opened onto an empty screen — the
  /// database talking to the reader.
  Future<Queue> loadQueue({required QueueSlot Function() planFactory}) async {
    final List<QueueRow> rows = await db.select(db.queueRows).get();
    final List<ArticleRow> bodies = await db.select(db.articleRows).get();
    final Map<String, ArticleRow> bodyById = <String, ArticleRow>{
      for (final ArticleRow a in bodies) a.articleId: a,
    };

    // The ledger is the fallback for a body that is not there: an article whose
    // bytes were freed, or one written before bodies were stored. It carries
    // the human-facing facts — the real title, and now the keywords.
    final List<LedgerRow> ledger = await db.select(db.ledgerRows).get();
    final Map<String, LedgerRow> byId = <String, LedgerRow>{
      for (final LedgerRow l in ledger) l.articleId: l,
    };

    final List<QueueSlot> slots = <QueueSlot>[];

    for (final QueueRow r in rows) {
      final String state = r.state;
      Article? article;
      if (state == 'ready') {
        article = _articleOf(r.articleId, bodyById, byId);
      }
      slots.add(QueueSlot(
        articleId: r.articleId,
        state: state == 'ready' ? SlotState.ready : SlotState.planned,
        article: article,
        instruction: r.instruction,
        instructionId: r.instructionId,
        plannedWords: r.plannedWords,
        plannedBand: _bandOf(r.plannedBand),
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
    required int kilobytes,
    List<String> keywords = const <String>[],
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
      // A slot holding an article has no outstanding request. Clearing the
      // instruction here is what stops a ready card from claiming the reader
      // asked for something that has already been written.
      instruction: const Value(''),
      instructionId: const Value(null),
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
              keywords: Value(encodeList(keywords)),
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

  /// Read a stored band name back, falling back to `medium`.
  ///
  /// A row written by an older build has no band at all, and the column default
  /// only applies to rows SQLite itself creates — a value that came back empty
  /// or unrecognised must land on a real band rather than on `null`. Medium is
  /// the honest fallback: it is the band whose length every old plan carried.
  static LengthBand _bandOf(String raw) => LengthBand.values.firstWhere(
        (LengthBand b) => b.name == raw,
        orElse: () => LengthBand.medium,
      );

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
                instruction: Value(s.instruction),
                instructionId: Value(s.instructionId),
                plannedWords: Value(s.plannedWords),
                plannedBand: Value(s.plannedBand.name),
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

  /// How many times an article has been read: today, and in all.
  ///
  /// TWO NUMBERS FROM TWO TABLES, and both are needed:
  ///
  ///  · `today` is the one the reader just changed with a tap, so it is what
  ///    proves the tap landed. Without it the button is a dead control — press
  ///    it and nothing on the screen moves, which reads as "that did not work"
  ///    and invites a second press, and a third.
  ///  · `total` is the article's whole history, which is what makes the line
  ///    say something true on a day the reader has not counted it yet. Without
  ///    it, coming back tomorrow looks exactly like never having read it.
  ///
  /// Read from `day_log_rows` and `ledger_rows` rather than kept in memory,
  /// because the whole point is that the number survives leaving the screen.
  Future<(int today, int total)> readCounts({
    required String articleId,
    required String day,
  }) async {
    final LedgerRow? meta = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    final drift.DayLogRow? todayRow = await (db.select(db.dayLogRows)
          ..where(($DayLogRowsTable t) =>
              t.day.equals(day) & t.articleId.equals(articleId)))
        .getSingleOrNull();
    return (todayRow?.reads ?? 0, meta?.reads ?? 0);
  }

  /// How many times this article has been heard, whole history.
  ///
  /// Sits beside [readCounts] rather than inside it: reads and listens are two
  /// counters on purpose, and a caller that wants both can ask for both. A
  /// missing row is zero listens, which is the truth and not an error.
  Future<int> ledgerListens(String articleId) async {
    final LedgerRow? meta = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    return meta?.listens ?? 0;
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
    required int kilobytes,
    required String day,
    List<String> keywords = const <String>[],
  }) async {
    final LedgerRow? existing = await (db.select(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    if (existing != null) {
      // The row is already there, so this is a RE-write of an article the
      // ledger has met. Two things may still need filling in: the size, if the
      // bytes were freed and the article has been written again, and the
      // keywords, if the row predates them.
      await (db.update(db.ledgerRows)
            ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
          .write(LedgerRowsCompanion(
        kilobytes: existing.kilobytes == 0 ? Value(kilobytes) : const Value.absent(),
        keywords: existing.keywords == '[]' && keywords.isNotEmpty
            ? Value(encodeList(keywords))
            : const Value.absent(),
        // Re-writing an old article makes it recent again, which is the point:
        // the writer should not immediately produce a near-copy of it.
        lastSeenDay: Value(day),
      ));
      return;
    }
    await db.into(db.ledgerRows).insert(
          LedgerRowsCompanion.insert(
            articleId: articleId,
            title: title,
            keywords: Value(encodeList(keywords)),
            kilobytes: Value(kilobytes),
            lastSeenDay: Value(day),
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

    // The bytes actually go. This is the line that was missing: `kilobytes` was
    // set to zero and the body stayed on disk forever, because there was no
    // body table to delete from.
    //
    // Note what is NOT in scope: `reads` and `listens` are not parameters of
    // this method and no line in it can reach them. That is invariant 4, and it
    // is enforced by the signature rather than by care.
    await deleteArticle(articleId);

    await (db.update(db.ledgerRows)
          ..where(($LedgerRowsTable t) => t.articleId.equals(articleId)))
        .write(LedgerRowsCompanion(
      kilobytes: const Value(0),
      freedKilobytes: Value(row.freedKilobytes + kilobytes),
      goneReason: Value(reason),
    ));
  }

  // ── instructions ──────────────────────────────────────────────────────
  //
  // The reader's own words about what to write. A real collection, not a
  // preference: rows are added, edited, searched and deleted independently, and
  // one is picked per article. It replaced the topic presets, which were
  // read-only in practice — nothing ever called `setPresets`.

  /// Saved instructions, most recently relevant first.
  ///
  /// "Most recently relevant" is `lastUsedDay` when there is one and
  /// `createdDay` when there is not — one expression, so an instruction written
  /// in March and never used sorts below one used yesterday rather than above
  /// it. `limit` is how the picker asks for its ten; the manager passes none.
  Future<List<Instruction>> instructions({int? limit}) async {
    final List<InstructionRow> rows = await (db.select(db.instructionRows)
          ..orderBy(<OrderClauseGenerator<$InstructionRowsTable>>[
            ($InstructionRowsTable t) => OrderingTerm(
                  expression: coalesce(<Expression<Object>>[
                    t.lastUsedDay,
                    t.createdDay,
                  ]),
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit ?? -1))
        .get();
    return <Instruction>[
      for (final InstructionRow r in rows)
        Instruction(
          id: r.id,
          text: r.instructionText,
          createdDay: r.createdDay,
          lastUsedDay: r.lastUsedDay,
          useCount: r.useCount,
        ),
    ];
  }

  /// The titles of the last few articles, newest first.
  ///
  /// This is what stops the writer producing its fourth piece about the same
  /// idea in different words. It reads the LEDGER rather than the queue,
  /// because the point is to avoid what has already been read — including
  /// articles that have since been deleted from the queue, which are exactly
  /// the ones the writer would otherwise cheerfully repeat.
  ///
  /// Twelve is a guess with a reason: at three articles a day that is four
  /// days of memory, which is long enough to break a run of similar pieces and
  /// short enough that the list stays under a tenth of the prompt.
  Future<List<String>> recentTitles({int limit = 12}) async {
    final List<LedgerRow> rows = await (db.select(db.ledgerRows)
          ..orderBy(<OrderClauseGenerator<$LedgerRowsTable>>[
            ($LedgerRowsTable t) => OrderingTerm(
                  expression: t.lastSeenDay,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
    return <String>[for (final LedgerRow r in rows) r.title];
  }

  /// Add or update one. The id is the caller's, so an edit keeps its identity
  /// and a new one is a new row.
  Future<void> upsertInstruction(Instruction i) async {
    await db.into(db.instructionRows).insertOnConflictUpdate(
          InstructionRowsCompanion.insert(
            id: i.id,
            instructionText: i.text,
            createdDay: i.createdDay,
            lastUsedDay: Value(i.lastUsedDay),
            useCount: Value(i.useCount),
          ),
        );
  }

  Future<void> deleteInstruction(String id) async {
    await (db.delete(db.instructionRows)
          ..where(($InstructionRowsTable t) => t.id.equals(id)))
        .go();
  }

  /// Mark an instruction as used, now.
  ///
  /// Separate from [upsertInstruction] because it is the one write that happens
  /// as a SIDE EFFECT of writing an article, and it must never be able to fail
  /// the article: the count is a nicety, the article is the thing that was paid
  /// for.
  Future<void> touchInstruction(String id, String day) async {
    final InstructionRow? row = await (db.select(db.instructionRows)
          ..where(($InstructionRowsTable t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return; // deleted since it was picked; nothing to record
    await (db.update(db.instructionRows)
          ..where(($InstructionRowsTable t) => t.id.equals(id)))
        .write(InstructionRowsCompanion(
      lastUsedDay: Value(day),
      useCount: Value(row.useCount + 1),
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
        keywords: _decodeList(r.keywords),
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

  // ── article bodies ────────────────────────────────────────────────────
  //
  // Everything above this line is identity and counts. This is the only place
  // the TEXT is stored, and storing it is what makes a card survive a restart:
  // a card is identified by its title and its keywords, and before this the
  // body lived in memory only, so the card came back reading `0 words` and
  // opened onto nothing.
  //
  // It is also what finally makes `freeSpace` mean something. Until now the
  // ledger's `kilobytes` was invented from the word count, and there were no
  // bytes to free.

  /// The stored body for one article, or null if it was never stored or its
  /// bytes have been freed.
  Future<Article?> loadArticle(String articleId) async {
    final ArticleRow? row = await (db.select(db.articleRows)
          ..where(($ArticleRowsTable t) => t.articleId.equals(articleId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _articleFromRow(row);
  }

  /// Store a body and its real size.
  ///
  /// Returns the size in BYTES, measured rather than estimated — the caller
  /// puts it on the ledger, so the storage bar and the shelf agree with each
  /// other instead of one of them guessing.
  Future<int> saveArticle(Article a) async {
    final String sentences = jsonEncode(<String, Object?>{
      // Wrapped rather than given a column of its own: `titleCn` is display
      // only, it is optional on every older row, and a schema migration plus a
      // codegen pass is a lot of machinery for one caption. A bare LIST is
      // still accepted on read, so rows written before this stays readable.
      if (a.titleCn.isNotEmpty) 'titleCn': a.titleCn,
      'items': <Object?>[
        for (final Sentence s in a.sentences)
          <String, Object?>{
            'en': s.english,
            'cn': s.chinese,
            if (s.audioPath != null) 'audio': s.audioPath,
          },
      ],
    });
    final String marks = jsonEncode(<Object?>[
      for (final Mark m in a.marks)
        <String, Object?>{
          'surface': m.surface,
          'lemma': m.lemma,
          'sentence': m.sentenceIndex,
          'tier': m.tier.name,
        },
    ]);
    final String keywords = encodeList(a.keywords);

    // The real number, measured rather than guessed. UTF-8 bytes, because that
    // is what the file will actually cost on disk.
    final int bytes = utf8.encode(sentences).length +
        utf8.encode(marks).length +
        utf8.encode(keywords).length;

    await db.into(db.articleRows).insertOnConflictUpdate(
          ArticleRowsCompanion.insert(
            articleId: a.id,
            title: a.title,
            keywords: Value(keywords),
            sentences: sentences,
            marks: marks,
            wordCount: Value(a.wordCount),
            minuteEstimate: Value(a.minuteEstimate),
            bytes: Value(bytes),
          ),
        );
    return bytes;
  }

  /// Drop a body. Called ONLY from `freeSpace`, and it deliberately cannot
  /// reach a counter — see the note on that method.
  Future<void> deleteArticle(String articleId) async {
    await (db.delete(db.articleRows)
          ..where(($ArticleRowsTable t) => t.articleId.equals(articleId)))
        .go();
  }

  /// Hydrate a slot's article from the body table, falling back to the ledger.
  ///
  /// The fallback is not a nicety: a freed article has no body and a card for
  /// it must still say what it was called and what it was about, and an article
  /// written before bodies were stored has a ledger row and nothing else.
  Article _articleOf(
    String articleId,
    Map<String, ArticleRow> bodies,
    Map<String, LedgerRow> ledger,
  ) {
    final ArticleRow? body = bodies[articleId];
    if (body != null) return _articleFromRow(body);
    final LedgerRow? meta = ledger[articleId];
    return Article(
      id: articleId,
      title: meta?.title ?? articleId,
      keywords: meta == null ? const <String>[] : _decodeList(meta.keywords),
      sentences: const <Sentence>[],
      marks: const <Mark>[],
      wordCount: 0,
      minuteEstimate: 0,
    );
  }

  static Article _articleFromRow(ArticleRow row) {
    final List<Sentence> sentences = <Sentence>[];
    final Object? rawS = jsonDecode(row.sentences);
    // Two shapes on disk: a bare LIST (rows written before `titleCn`), or a
    // MAP carrying the Chinese title and the list under `items`. Both are
    // normal; the list is not a fallback for corrupt data, it is the old file.
    String titleCn = '';
    Object? items = rawS;
    if (rawS is Map) {
      items = rawS['items'];
      final Object? t = rawS['titleCn'];
      if (t is String) titleCn = t;
    }
    if (items is List) {
      for (final Object? s in items) {
        if (s is! Map) continue;
        final Object? en = s['en'];
        if (en is! String || en.isEmpty) continue;
        final Object? cn = s['cn'];
        final Object? audio = s['audio'];
        sentences.add(Sentence(
          english: en,
          chinese: cn is String ? cn : '',
          audioPath: audio is String && audio.isNotEmpty ? audio : null,
        ));
      }
    }

    final List<Mark> marks = <Mark>[];
    final Object? rawM = jsonDecode(row.marks);
    if (rawM is List) {
      for (final Object? m in rawM) {
        if (m is! Map) continue;
        final Object? surface = m['surface'];
        final Object? lemma = m['lemma'];
        if (surface is! String || lemma is! String) continue;
        final Object? at = m['sentence'];
        marks.add(Mark(
          surface: surface,
          lemma: lemma,
          sentenceIndex: at is int ? at : 0,
          tier: m['tier'] == 'unfamiliar'
              ? MarkTier.unfamiliar
              : MarkTier.difficult,
        ));
      }
    }

    return Article(
      id: row.articleId,
      title: row.title,
      titleCn: titleCn,
      keywords: _decodeList(row.keywords),
      sentences: sentences,
      marks: marks,
      wordCount: row.wordCount,
      minuteEstimate: row.minuteEstimate,
    );
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
      style: _decodeList(row.style),
      gloss: _decodeList(row.gloss),
      avoid: _decodeList(row.avoid),
      shortWords: row.shortWords,
      mediumWords: row.mediumWords,
      longWords: row.longWords,
      raw: row.raw,
    );
  }

  Future<void> savePlan(ReadingPlan plan) async {
    await db.into(db.planRows).insertOnConflictUpdate(
          PlanRowsCompanion.insert(
            id: const Value(1),
            reader: Value(plan.reader),
            style: Value(encodeList(plan.style)),
            gloss: Value(encodeList(plan.gloss)),
            avoid: Value(encodeList(plan.avoid)),
            shortWords: Value(plan.shortWords),
            mediumWords: Value(plan.mediumWords),
            longWords: Value(plan.longWords),
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