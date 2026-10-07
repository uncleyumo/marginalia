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

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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
  TextColumn get topic => text().withDefault(const Constant(''))();
  TextColumn get focus => text().withDefault(const Constant(''))();
  IntColumn get plannedWords => integer().withDefault(const Constant(300))();
  IntColumn get plannedMarked => integer().withDefault(const Constant(6))();
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
  TextColumn get topic => text().withDefault(const Constant(''))();
  IntColumn get reads => integer().withDefault(const Constant(0))();
  IntColumn get listens => integer().withDefault(const Constant(0))();
  IntColumn get kilobytes => integer().withDefault(const Constant(0))();
  IntColumn get freedKilobytes => integer().withDefault(const Constant(0))();
  TextColumn get goneReason => text().nullable()();

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
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  TextColumn get starredAtDay => text().nullable()();
  TextColumn get lastMetDay => text().nullable()();

  @override
  Set<Column> get primaryKey => <Column>{lemma};
}

/// The reading plan, as seven named fields plus the reader's own words.
///
/// Stored as a single row because it IS a single object; the point of the
/// structure is that a field can be pointed at, and that is a read-time
/// concern, not a column-per-field concern.
class PlanRows extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get reader => text().withDefault(const Constant(''))();
  TextColumn get topics => text().withDefault(const Constant('[]'))();
  TextColumn get style => text().withDefault(const Constant('[]'))();
  TextColumn get gloss => text().withDefault(const Constant('[]'))();
  TextColumn get avoid => text().withDefault(const Constant('[]'))();
  IntColumn get length => integer().withDefault(const Constant(300))();
  IntColumn get marked => integer().withDefault(const Constant(6))();
  TextColumn get raw => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// Preset chips: the topics and focuses the user keeps or deletes.
class PresetRows extends Table {
  IntColumn get id => integer()();
  TextColumn get kind => text()(); // 'topic' | 'focus'
  TextColumn get label => text()();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => <Column>{id};
}

/// Which surface the reader chose. One row. Not a day/night setting — there is
/// no day/night concept; this is an appearance preference with no time
/// semantics, and it lives in Settings → The small print.
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
    PresetRows,
    SettingsRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // Invariant 1, enforced by the DATABASE rather than by this layer, so a
        // bug above it still cannot leave a fourth slot behind.
        //
        // This has to happen AFTER the tables exist. Doing it in `beforeOpen`
        // issued DDL from inside the migration transaction while drift was still
        // running its CREATE TABLE statements, and the first run died with
        //     SqliteException(5): database is locked
        //     Causing statement: CREATE TABLE IF NOT EXISTS "settings_rows" ...
        // `onCreate` receives the migrator, so the schema is complete and the
        // statement queues behind the same transaction instead of racing it.
        onCreate: (Migrator m) async {
          await m.createAll();

          // Invariant 1 as the DATABASE states it, not as a comment.
          //
          // The WHEN clause counts everything except the row being written:
          //   (SELECT COUNT(*) FROM queue_rows) >= 3 AND NEW.id NOT IN (...)
          // Without that guard the trigger fires on a REPLACE too, and every
          // legitimate "write the three slots back" aborted. The first run died
          // with the app frozen on its wordmark and nothing in the log, because
          // the rejected INSERT happened inside a transaction nobody was
          // awaiting.
          await m.database.customStatement(
            'CREATE TRIGGER IF NOT EXISTS queue_at_most_three '
            'BEFORE INSERT ON queue_rows '
            'WHEN (SELECT COUNT(*) FROM queue_rows) >= 3 '
            '  AND NEW.id NOT IN (SELECT id FROM queue_rows) '
            "BEGIN SELECT RAISE(ABORT, 'queue.size == 3'); END",
          );
        },
      );
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
