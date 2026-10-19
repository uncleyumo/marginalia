// Local storage.
//
// DESIGN's rule about the truth: *Most revisited* and the calendar numbers are
// GROUP BY queries over ONE table of (day, article, reads, listens). A second
// table holding per-article totals would be the "second copy of the truth" the
// prototype refuses to create — the two could disagree, and then the app would
// be showing a number it cannot explain.
//
// So: one log table, one queue table, one plan table, one word table. The
// shelf, the calendar and the revisit list are all queries.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:path_provider/path_provider.dart';
import "dart:io";

import "package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart";

part 'database.g.dart';

/// The queue. Exactly three rows — the CHECK constraint is the database's own
/// statement of invariant 1, so even a bug above this layer cannot leave four.
class QueueRows extends Table {
  IntColumn get id => integer()();
  TextColumn get articleId => text()();
  TextColumn get state => text()(); // 'planned' | 'ready'

  /// What the reader asked for, in their own words. Empty is the ordinary case
  /// and means the writer picks the subject.
  ///
  /// This replaced `topic`. A topic was a label the reader had to choose from a
  /// list they had to maintain; an instruction is a sentence they type when
  /// they want something specific and never otherwise. The text is stored ON
  /// THE SLOT rather than as a reference, so a planned card keeps saying what
  /// it was asked for even if that saved instruction is later edited or
  /// deleted — what was asked for is a fact about this slot.
  TextColumn get instruction => text().withDefault(const Constant(''))();

  /// Which saved instruction it came from, when it came from one.
  ///
  /// For ONE purpose: bumping that instruction's `lastUsedDay` and `useCount`
  /// without matching on text. It is not a foreign key and nothing joins on it.
  TextColumn get instructionId => text().nullable()();

  IntColumn get plannedWords => integer().withDefault(const Constant(300))();

  /// Where [plannedWords] came from: 'short' | 'medium' | 'long' | 'custom'.
  ///
  /// Stored as text rather than an int so the column reads as what it is. The
  /// name of the band and the number of words are two facts — a reader who
  /// typed a custom 300 did not ask for `medium`, and a card that says they did
  /// is a card that made up an answer.
  TextColumn get plannedBand =>
      text().withDefault(const Constant('medium'))();
  BoolColumn get isWriting => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// The archive. One row per article the reader has met.
///
/// `freedKilobytes` is separate from `kilobytes` on purpose: the shelf has to
/// keep saying "1.2 MB freed" AFTER the size itself is zero. Zeroing both
/// together would leave the reader unable to account for what happened.
class LedgerRows extends Table {
  TextColumn get articleId => text()();
  TextColumn get title => text()();

  /// HISTORICAL. What an article was about, as recorded when it was written,
  /// for rows that predate keywords. Nothing reads it to decide anything and
  /// new rows leave it empty — see [keywords].
  TextColumn get topic => text().withDefault(const Constant(''))();

  /// What the writer said the article was about, as a json list. The shelf
  /// searches and displays these.
  ///
  /// Kept on the LEDGER rather than only in `article_rows` because the ledger
  /// row outlives the bytes: a freed article still has to be findable and still
  /// has to say what it was about, and `freeSpace` deliberately cannot reach
  /// this column.
  TextColumn get keywords => text().withDefault(const Constant('[]'))();

  IntColumn get reads => integer().withDefault(const Constant(0))();
  IntColumn get listens => integer().withDefault(const Constant(0))();
  IntColumn get kilobytes => integer().withDefault(const Constant(0))();
  IntColumn get freedKilobytes => integer().withDefault(const Constant(0))();
  TextColumn get goneReason => text().nullable()();

  /// `YYYY-MM-DD`, the day this article was last written or read.
  ///
  /// This column exists for one reader-facing reason: the writer is told what
  /// it has recently produced, so it does not hand back a fourth article about
  /// the same idea in different words. That needs an ORDER, and the ledger had
  /// none — the day log orders reads, but a written-and-not-yet-read article is
  /// exactly the one most likely to be repeated.
  ///
  /// Empty on rows that predate this column. Those sort last, which is right:
  /// they are the oldest thing in the table.
  TextColumn get lastSeenDay => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => <Column>{articleId};
}

/// The only record of what happened. Everything derived comes from here.
class DayLogRows extends Table {
  TextColumn get day => text()(); // YYYY-MM-DD, never a timestamp
  TextColumn get articleId => text()();
  TextColumn get title => text()();
  IntColumn get reads => integer().withDefault(const Constant(0))();
  IntColumn get listens => integer().withDefault(const Constant(0))();
  IntColumn get minutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{day, articleId};
}

/// The word pool. A weight is never stored — it is computed from `encounters`,
/// `starred` and `lastMetDay` when read, so it decays with no scheduler.
class WordRows extends Table {
  TextColumn get lemma => text()();
  IntColumn get encounters => integer().withDefault(const Constant(0))();

  /// Whether a star campaign is still running. Kept as a column as well as the
  /// quota below because it is what the Words screen groups by, and a row from
  /// an older build reaches the app with only this flag set.
  BoolColumn get starred => boolean().withDefault(const Constant(false))();

  /// Lifetime star taps, and showings already delivered in the current
  /// campaign. [starCount] − [starDelivered] is what is still owed.
  IntColumn get starCount => integer().withDefault(const Constant(0))();
  IntColumn get starDelivered => integer().withDefault(const Constant(0))();

  TextColumn get starredAtDay => text().nullable()();
  TextColumn get lastMetDay => text().nullable()();

  @override
  Set<Column> get primaryKey => <Column>{lemma};
}

/// The reading plan, as eight named fields plus the reader's own words.
///
/// Stored as a single row because it IS a single object; the point of the
/// structure is that a field can be pointed at, and that is a read-time
/// concern, not a column-per-field concern.
///
/// Three length columns rather than one, because length became a BAND: a short
/// article is not "300 words minus", it is its own thing the reader sets once.
/// There is deliberately no `marked` column any more — how many words get
/// marked is the writer's judgement, measured afterwards; see `difficulty.dart`.
class PlanRows extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get reader => text().withDefault(const Constant(''))();
  TextColumn get style => text().withDefault(const Constant('[]'))();
  TextColumn get gloss => text().withDefault(const Constant('[]'))();
  TextColumn get avoid => text().withDefault(const Constant('[]'))();
  IntColumn get shortWords => integer().withDefault(const Constant(180))();
  IntColumn get mediumWords => integer().withDefault(const Constant(300))();
  IntColumn get longWords => integer().withDefault(const Constant(500))();
  TextColumn get raw => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// The reader's saved instructions, in their own words.
///
/// This is what replaced the topic presets. It is a real collection rather than
/// a preference, which is why it is a table and not a key in `settings_rows`:
/// rows are added, edited, searched and deleted independently, and one of them
/// is picked per article.
class InstructionRows extends Table {
  TextColumn get id => text()();

  /// Named `instructionText` and not `text`, because `text` is a METHOD on
  /// drift's `Table` — a column of that name does not compile, and the failure
  /// mode is that the whole table silently fails to generate.
  TextColumn get instructionText => text()();

  /// `YYYY-MM-DD`, the same day format the ledger uses — a string rather than a
  /// timestamp so a stored row never shifts when the device timezone does.
  TextColumn get createdDay => text()();

  /// Null until it has actually been used to write something.
  TextColumn get lastUsedDay => text().nullable()();

  IntColumn get useCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// The article BODIES. Everything else about an article is identity and counts;
/// this is the only table that holds the text.
///
/// It exists because a card is identified by its title and its keywords, and
/// both used to vanish on restart: the body lived in memory only, so a card
/// came back reading `0 words · 0 min read` and opened onto nothing. Storing
/// the body is also what finally makes `freeSpace` mean something — until now
/// the ledger's `kilobytes` was a number invented from the word count
/// (`wordCount * 6 ~/ 1024 + 1`) and there were no bytes to free.
///
/// `sentences` and `marks` are json, for the same reason the plan's lists are:
/// an article is a single object, and splitting it across rows would let the
/// marks drift out of step with the text they point into.
class ArticleRows extends Table {
  TextColumn get articleId => text()();
  TextColumn get title => text()();
  TextColumn get keywords => text().withDefault(const Constant('[]'))();
  TextColumn get sentences => text()();
  TextColumn get marks => text()();
  IntColumn get wordCount => integer().withDefault(const Constant(0))();
  IntColumn get minuteEstimate => integer().withDefault(const Constant(0))();

  /// Real bytes on disk: the length of the three json columns plus the audio
  /// files cached for this article. Replaces the invented figure.
  IntColumn get bytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => <Column>{articleId};
}

/// DEAD. Superseded by [InstructionRows].
///
/// `setPresets` was never called from anywhere — the topic and focus chips were
/// read-only and fell back to hardcoded lists when this table was empty. The
/// table is kept rather than dropped because `DROP TABLE` cannot be undone and
/// an unused table costs nothing. Nothing writes to it and nothing should.
class PresetRows extends Table {
  IntColumn get id => integer()();
  TextColumn get kind => text()(); // 'topic' | 'focus'
  TextColumn get label => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// Which surface the reader chose. One row. `ui:palette`, `ui:appearance`,
/// `ui:readingFace`, `ui:readSize`.
///
/// A surface is not a time of day: the app has no schedule that switches
/// anything, and "follow the system" means exactly that and nothing more. The
/// reader picks a look; nothing picks it for them.
class SettingsRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => <Column>{key};
}

@DriftDatabase(
  tables: <Type>[
    QueueRows,
    LedgerRows,
    DayLogRows,
    WordRows,
    PlanRows,
    InstructionRows,
    ArticleRows,
    PresetRows,
    SettingsRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _installQueueTrigger(m);
        },

        // 1 → 2: length became three bands, and `marked` stopped being a
        // setting. Both tables are REBUILT rather than dropped: SQLite cannot
        // drop a column, and `TableMigration` recreates the table and copies
        // the rows across, so a reader who had a plan keeps it.
        //
        // `plan_rows.length` is migrated into `mediumWords`, because 300 was
        // the single length every old plan carried and 300 is what the medium
        // band defaults to. The other two bands take their defaults.
        onUpgrade: (Migrator m, int from, int to) async {
          // READ EVERYTHING THE MIGRATION NEEDS, BEFORE IT CHANGES ANYTHING.
          //
          // This is not tidiness, it is the one ordering constraint in the whole
          // chain, and getting it wrong is silent: `TableMigration` recreates a
          // table from its CURRENT Dart definition, so the moment `plan_rows` is
          // rebuilt the `topics` column is gone, and the moment `queue_rows` is
          // rebuilt the `topic` column is gone. Both are columns this code still
          // has to read.
          //
          // It is worse than a one-branch problem: a v1 reader upgrading to v3
          // runs BOTH branches, and the `from < 2` branch rebuilds both tables
          // first. Reading inside `from < 3` therefore fails for exactly the
          // readers who have the most to lose. Hoisting the reads above every
          // branch is what makes the order irrelevant.
          //
          // Both helpers swallow their own errors — a fresh database has
          // neither column, and that is not a failure, it is a database with
          // nothing to convert.
          final List<String> oldPlanTopics = await _readOldTopics();
          final List<String> oldQueueTopics = await _readOldQueueTopics();

          if (from < 2) {
            await m.alterTable(
              TableMigration(
                planRows,
                newColumns: <GeneratedColumn<Object>>[
                  planRows.shortWords,
                  planRows.mediumWords,
                  planRows.longWords,
                ],
                columnTransformer: <GeneratedColumn<Object>, Expression<Object>>{
                  // The column is gone from the Dart definition, so it has to be
                  // named as raw SQL — and QUOTED, because bare `length` is a
                  // SQLite scalar function and the INSERT..SELECT would try to
                  // call it with no arguments.
                  planRows.mediumWords: const CustomExpression<int>('"length"'),
                },
              ),
            );

            await m.alterTable(
              TableMigration(
                queueRows,
                newColumns: <GeneratedColumn<Object>>[queueRows.plannedBand],
              ),
            );

            // THE TRAP. `TableMigration` recreates `queue_rows` — create the new
            // table, copy, drop the old one, rename — and dropping a table drops
            // the triggers on it. Without this line invariant 1 silently stops
            // existing for every reader who upgrades, and a fourth slot becomes
            // insertable by any bug above this layer.
            await _installQueueTrigger(m);
          }

          // 2 → 3: `topic` became `instruction`, and article bodies started
          // being stored.
          //
          // The old `topics` list is CONVERTED, not discarded. It is data the
          // reader typed, and its intent — "write about this" — is exactly what
          // an instruction is for. Dropping it would silently delete something
          // they wrote; turning it into a saved instruction costs one INSERT
          // and loses nothing.
          if (from < 3) {
            // EVERY STEP BELOW IS GUARDED, AND THAT IS NOT DEFENSIVE PADDING.
            //
            // This migration was written unguarded, and the upgrade-install test
            // found out why that is wrong: the instruction INSERT further down
            // failed at PREPARE time (it selected a column an earlier step had
            // already dropped), the upgrade aborted — and SQLite had already
            // committed the DDL. The reader was left with `user_version = 2` and
            // a half-v3 schema, which the old code could not re-enter: the next
            // launch died on `table instruction_rows already exists`.
            //
            // So each step asks what is actually there. A migration that can
            // only run on a database in exactly one shape is a migration that
            // bricks the phone when anything interrupts it.
            if (!await _hasTable('instruction_rows')) {
              await m.createTable(instructionRows);
            }
            if (!await _hasTable('article_rows')) {
              await m.createTable(articleRows);
            }

            if (await _hasColumn('plan_rows', 'topics')) {
              await m.alterTable(
                TableMigration(
                  planRows,
                  columnTransformer:
                      <GeneratedColumn<Object>, Expression<Object>>{},
                ),
              );
            }

            if (await _hasColumn('queue_rows', 'topic')) {
              await m.alterTable(
                TableMigration(
                  queueRows,
                  newColumns: <GeneratedColumn<Object>>[
                    queueRows.instruction,
                    queueRows.instructionId,
                  ],
                  columnTransformer:
                      <GeneratedColumn<Object>, Expression<Object>>{
                    // The old topic becomes the new instruction, and it gains
                    // the words the saved instruction gains, so the card and
                    // the picker agree: a topic was always a shorthand for
                    // "write about this", and the new model says so out loud.
                    //
                    // `Free pick` was the placeholder for "no topic" and must
                    // NOT survive as an instruction — it would be a saved
                    // instruction telling the writer to write about free picks.
                    queueRows.instruction: const CustomExpression<String>(
                        'CASE WHEN "topic" = \'Free pick\' OR "topic" = \'\' '
                        'THEN \'\' ELSE \'Write about \' || "topic" END'),
                  },
                ),
              );
            }

            if (!await _hasColumn('ledger_rows', 'keywords')) {
              await m.alterTable(
                TableMigration(
                  ledgerRows,
                  newColumns: <GeneratedColumn<Object>>[
                    ledgerRows.keywords,
                    ledgerRows.lastSeenDay,
                  ],
                ),
              );
            }

            // The queue's own topics become instructions too, for the same
            // reason: a card that said "C language" was a card the reader had
            // already decided something about.
            // This used to be an `INSERT ... SELECT ... FROM queue_rows`, which
            // is the shape that produced the ordering bug above: by the time it
            // ran, `queue_rows` had been rebuilt and no longer had a `topic`
            // column to select from. It failed at PREPARE time, so the whole
            // upgrade aborted and the app came up with an empty queue.
            //
            // The two lists are merged first, because they overlap: a reader
            // whose plan said `C language` and whose card said `C language` had
            // one idea, not two, and the upgrade-install test caught this
            // producing two identical saved instructions.
            final Set<String> convert = <String>{
              ...oldQueueTopics,
              ...oldPlanTopics,
            };
            for (final String t in convert) {
              final String text = 'Write about $t';
              // `WHERE NOT EXISTS` rather than `INSERT OR IGNORE`: the primary
              // key is the id, so OR IGNORE would happily insert the same TEXT
              // twice under two ids. This also makes the step safe to re-run,
              // which is what the whole guarded block above is for.
              await m.database.customStatement(
                'INSERT INTO instruction_rows '
                '(id, instruction_text, created_day, last_used_day, use_count) '
                'SELECT ?, ?, ?, NULL, 0 '
                'WHERE NOT EXISTS ('
                '  SELECT 1 FROM instruction_rows WHERE instruction_text = ?)',
                <Object?>[
                  'ins-${t.hashCode.abs()}',
                  text,
                  _today(),
                  text,
                ],
              );
            }

            // Point the migrated cards at the instruction they came from.
            //
            // Without this a card reads `Write about NVDA` while the picker
            // shows `Write about NVDA` as unselected, and picking it would look
            // like a change when nothing would change. The join is on the text
            // because that is the only thing the two rows share — the id was
            // invented on the line above.
            await m.database.customStatement(
              'UPDATE queue_rows SET instruction_id = ('
              '  SELECT i.id FROM instruction_rows i '
              '  WHERE i.instruction_text = queue_rows.instruction) '
              'WHERE instruction <> \'\' AND instruction_id IS NULL',
            );

            // Same trap as above, and it is now the SECOND time `queue_rows`
            // has been rebuilt in this migration chain. The trigger has to be
            // reinstalled after the last rebuild, not the first.
            await _installQueueTrigger(m);
          }

          // 3 → 4: a star became a FINITE promise.
          //
          // Before this, `starred` was a boolean and a starred word carried a
          // weight that decayed over weeks: the reader could cancel it, but it
          // never left "Crucial now" on its own and every prompt kept carrying
          // it. A star now owes a number of showings (the lifetime star count),
          // and the word leaves the front of the pool when the last one lands.
          //
          // An existing starred row becomes ONE owed showing, not zero: the
          // reader asked for a repeat and has not had it under the new rule
          // yet. The guarded column check makes this safe to re-enter after an
          // interrupted upgrade.
          if (from < 4) {
            if (!await _hasColumn('word_rows', 'star_count')) {
              await m.addColumn(wordRows, wordRows.starCount);
            }
            if (!await _hasColumn('word_rows', 'star_delivered')) {
              await m.addColumn(wordRows, wordRows.starDelivered);
            }
            await m.database.customStatement(
              'UPDATE word_rows SET star_count = 1, star_delivered = 0 '
              'WHERE starred = 1 AND star_count = 0',
            );
          }
        },
      );

  /// The plan's old `topics` list, read before the column is dropped.
  ///
  /// Raw SQL and a try/catch, because this column does not exist in the Dart
  /// schema any more — referring to `planRows.topics` would not compile, and a
  /// fresh v2 database always has it, so the only failure mode is a database
  /// that never got that far.
  Future<List<String>> _readOldTopics() async {
    try {
      final QueryRow row = await customSelect(
        'SELECT "topics" FROM plan_rows WHERE id = 1',
      ).getSingle();
      final Object? raw = row.data['topics'];
      if (raw is! String || raw.isEmpty) return const <String>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return <String>[
        for (final Object? t in decoded)
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ];
    } catch (e) {
      debugPrint('migration: no readable topics column ($e)');
      return const <String>[];
    }
  }

  /// Does the schema actually contain this table?
  ///
  /// Asked of `sqlite_master` rather than of the generated Dart, because the
  /// whole point is to find out what the FILE has, which is not necessarily
  /// what the code now says it should have.
  Future<bool> _hasTable(String name) async {
    final QueryRow row = await customSelect(
      "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable<Object>>[Variable<String>(name)],
    ).getSingle();
    return (row.data['n'] as int? ?? 0) > 0;
  }

  /// Does this table actually have this column? Same reason as [_hasTable].
  Future<bool> _hasColumn(String table, String column) async {
    try {
      final List<QueryRow> rows =
          await customSelect('PRAGMA table_info($table)').get();
      return rows.any((QueryRow r) => r.data['name'] == column);
    } catch (e) {
      debugPrint('migration: could not read the shape of $table ($e)');
      return false;
    }
  }

  /// The three card topics, read before `queue_rows` is rebuilt.
  ///
  /// `Free pick` is filtered out here rather than at the INSERT: it was the
  /// placeholder for "no topic", and a saved instruction reading "Write about
  /// Free pick" is worse than no instruction at all.
  Future<List<String>> _readOldQueueTopics() async {
    try {
      final List<QueryRow> rows = await customSelect(
        'SELECT "topic" FROM queue_rows',
      ).get();
      return <String>[
        for (final QueryRow r in rows)
          if (r.data['topic'] is String &&
              (r.data['topic'] as String).trim().isNotEmpty &&
              (r.data['topic'] as String).trim() != 'Free pick')
            (r.data['topic'] as String).trim(),
      ];
    } catch (e) {
      debugPrint('migration: no readable queue topic column ($e)');
      return const <String>[];
    }
  }

  /// Invariant 1, enforced by the DATABASE rather than by this layer, so a bug
  /// above it still cannot leave a fourth slot behind.
  ///
  /// This has to happen AFTER the tables exist. Doing it in `beforeOpen` issued
  /// DDL from inside the migration transaction while drift was still running its
  /// CREATE TABLE statements, and the first run died with
  ///     SqliteException(5): database is locked
  ///     Causing statement: CREATE TABLE IF NOT EXISTS "settings_rows" ...
  /// `onCreate` receives the migrator, so the schema is complete and the
  /// statement queues behind the same transaction instead of racing it.
  ///
  /// Called from `onCreate` and from the end of EVERY `onUpgrade` branch that
  /// rebuilds `queue_rows`. One function, because the copies would drift apart
  /// and only one of them is exercised on a fresh install.
  Future<void> _installQueueTrigger(Migrator m) {
    // The WHEN clause counts everything except the row being written:
    //   (SELECT COUNT(*) FROM queue_rows) >= 3 AND NEW.id NOT IN (...)
    // Without that guard the trigger fires on a REPLACE too, and every
    // legitimate "write the three slots back" aborted. The first run died
    // with the app frozen on its wordmark and nothing in the log, because
    // the rejected INSERT happened inside a transaction nobody was awaiting.
    return m.database.customStatement(
      'CREATE TRIGGER IF NOT EXISTS queue_at_most_three '
      'BEFORE INSERT ON queue_rows '
      'WHEN (SELECT COUNT(*) FROM queue_rows) >= 3 '
      '  AND NEW.id NOT IN (SELECT id FROM queue_rows) '
      "BEGIN SELECT RAISE(ABORT, 'queue.size == 3'); END",
    );
  }
}

QueryExecutor _open() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationSupportDirectory();
    // Same reason as the dictionary: on a fresh install this directory does not
    // exist, and sqlite cannot create a file inside a directory that is not
    // there.
    if (!dir.existsSync()) await dir.create(recursive: true);
    return NativeDatabase(
      File(p.join(dir.path, 'no-stop.db')),
      // Single isolate, ON PURPOSE.
      //
      // `createInBackground` runs queries on a separate isolate and routes every
      // statement over a port. With a transaction that is fine in isolation, but
      // a first-run boot opens the schema, reads the queue, writes the refilled
      // slots and installs a sample in quick succession, and two of those
      // interleaved statements made SQLite reject the write lock:
      //     SqliteException(5): database is locked
      //     Causing statement: BEGIN IMMEDIATE
      // Six statements on the main isolate cost nothing next to 39 MB of
      // dictionary json, and correctness here is not worth trading for.
      //
      // WAL still matters and is set on the connection, before any migration:
      // it is what lets the reading screen and the word tap be in the file at
      // once. It must NOT be a PRAGMA in beforeOpen — rewriting the header needs
      // an exclusive lock while drift is mid-migration, which is the original
      // first-run crash.
      setup: (sqlite.Database db) {
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('PRAGMA foreign_keys=ON');
      },
    );
  });
}

/// Called once before the first query. sqlite3_flutter_libs ships the native
/// library; without this the first query throws on a fresh install.
Future<void> ensureSqliteReady() => applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

/// `YYYY-MM-DD` in local time, for the migration's `created_day`.
///
/// Duplicated from `word_pool.dart` on purpose: this file is the storage layer
/// and importing the domain would point the dependency the wrong way. It is
/// four lines, and the alternative — a migration that depends on a domain type
/// being unchanged forever — is worse.
String _today() {
  final DateTime n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}
