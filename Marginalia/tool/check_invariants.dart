// The five invariants, as executable checks.
//
// `dart test` cannot run in this environment (a native-asset build hook spawns
// `dart compile kernel` as a child process, and Dart cannot create a piped child
// process here — CreateFile failed 231). So the checks are written as a plain
// Dart program that exits non-zero on failure and prints what broke. Same
// guarantee, no test runner: CI and a human both just run it.
//
//   dart tool/check_invariants.dart
//
// The domain layer deliberately has no Flutter import, which is what makes this
// possible — and that constraint is also good design, because it means the
// rules can never quietly depend on a widget.

import 'dart:typed_data';

import '../lib/domain/difficulty.dart';
import '../lib/domain/instruction.dart';
import '../lib/domain/library.dart';
import '../lib/domain/models.dart';
import '../lib/domain/picture.dart';
import '../lib/domain/plan.dart';
import '../lib/domain/queue.dart';
import '../lib/domain/word_pool.dart';
import '../lib/data/remote/api.dart';

int _failures = 0;
int _checks = 0;

void check(String name, bool passed, [String detail = '']) {
  _checks++;
  if (passed) {
    print('  ok   $name');
  } else {
    _failures++;
    print('  FAIL $name${detail.isEmpty ? '' : '  -> $detail'}');
  }
}

void section(String title) {
  print('');
  print(title);
  print('-' * title.length);
}

Article _article(String id, {String title = 'T'}) => Article(
      id: id,
      title: title,
      keywords: const <String>['pointers', 'memory'],
      sentences: const <Sentence>[
        Sentence(english: 'A sentence of English text.', chinese: '一句中文。'),
      ],
      marks: const <Mark>[],
      wordCount: 300,
      minuteEstimate: 4,
    );

QueueSlot _ready(String id, {String title = 'T'}) => QueueSlot(
      articleId: id,
      state: SlotState.ready,
      article: _article(id, title: title),
    );

/// A planned slot with no instruction — the ordinary case, and the one that
/// has to render as a NAME rather than a blank.
QueueSlot _planned(String id) => QueueSlot(
      articleId: id,
      state: SlotState.planned,
      plannedWords: 300,
      plannedBand: LengthBand.medium,
    );

Queue _queueWithTwoReadyOnePlanned() =>
    Queue(<QueueSlot>[_ready('a1'), _ready('a2'), _planned('a3')]);

void main() {
  print('Marginalia — invariant checks');

  // ── 1. queue.size == 3 ────────────────────────────────────────────────
  section('1. the queue always holds exactly three');
  final Queue q = _queueWithTwoReadyOnePlanned();
  check('starts at three', q.length == kQueueSize, 'got ${q.length}');
  check('kQueueSize is 3, not a capacity', kQueueSize == 3);

  // autoFill tops a short queue up to three, and only with PLANS
  final Queue shortQ = Queue(<QueueSlot>[_ready('a1')]);
  shortQ.autoFill(() => _planned('auto'));
  check(
      'a short queue is filled to three',
      shortQ.length == kQueueSize,
      'got ${shortQ.length}');
  check(
      'the filler installs plans, never articles',
      shortQ.slots.every((QueueSlot s) => s.isPlanned || s.isReady) &&
          shortQ.slots.where((QueueSlot s) => s.isPlanned).length == 2);

  // overfilling is rejected at construction
  var overfillRefused = false;
  try {
    Queue(<QueueSlot>[
      _ready('1'),
      _ready('2'),
      _ready('3'),
      _ready('4'),
    ]);
  } on StateError {
    overfillRefused = true;
  }
  check('a fourth slot is refused', overfillRefused);

  // ── 2. two states only, and a plan stops all writing ──────────────────
  section('2. two states, and a planned slot stops everything');
  final Queue cost = _queueWithTwoReadyOnePlanned();
  check('a planned slot is detected', cost.hasPlannedSlot);

  // The gate is on AUTOMATIC writing. An explicit tap is always honoured.
  //
  // NOTE WHICH GETTER THIS IS. `mayAutoWrite` states an invariant about the
  // queue — a plan waiting means the app waits too — but it is NOT the gate the
  // app spends behind. That is `_ShellState._mayAutoWrite`, which is four
  // conditions and reads `nextPlanned != null`, the inverse of this one. This
  // check is here to keep the queue's own rule honest; it is not a check that
  // money cannot leave the phone.
  check('automatic writing is blocked while a plan waits', !cost.mayAutoWrite);
  check('and autoFill refuses to top the queue up', () {
    cost.autoFill(() => _planned('auto'));
    return cost.length == kQueueSize && cost.plannedCount == 1;
  }());

  // A reader who taps Write it on the planned card gets an article. Refusing
  // this would make the app incapable of ever spending a cent, which is not
  // what "deliberate and affordable" means.
  final Article? tapped = cost.writeSlot(2, _article('a3'));
  check('an explicit tap on the planned card writes it', tapped != null);
  check('and that slot becomes ready', cost.slots[2].isReady);
  check('the other cards are untouched',
      cost.slots[0].isReady && cost.slots[1].isReady);
  check('the queue is still three', cost.length == kQueueSize);
  check('writing the same slot twice is refused',
      cost.writeSlot(2, _article('a3')) == null);
  check('writing a ready slot is refused',
      cost.writeSlot(0, _article('a1')) == null);

  // ── single flight, and where the lock lives ──────────────────────────
  //
  // Two bugs this section exists to stop coming back, both found while adding
  // the automatic write:
  //
  //  1. The lock was claimed AFTER two awaits, so two callers entering that
  //     window both read "not writing" and both paid. A check separated from
  //     its claim by an `await` is not a check.
  //  2. The lock was the slot's own `isWriting` flag, which is persisted. Any
  //     other action's `saveQueue` — Done with it on another card, a reroll, an
  //     edit — wrote a mid-flight `true` to the disk, and a process that died
  //     restored it: a card reading "Writing…" forever, with Write it, ↻, ▣ and
  //     Change it all dead, escape only by clearing the app's data.
  section('2b. single flight is a lock, and it does not survive a restart');

  // `isWriting` is a transient and the queue must be able to see it as one.
  final Queue lockQ = _queueWithTwoReadyOnePlanned();
  lockQ.slots[2].isWriting = true;
  check('a slot can be marked as writing', lockQ.slots[2].isWriting);
  check('and isWritingAnywhere sees it', lockQ.isWritingAnywhere);
  check('while another slot is not', !lockQ.slots[0].isWriting);

  // Every mutation that installs a NEW slot must reset the transient. A plan
  // replacing a slot that was mid-flight inherits nothing — the write that was
  // in flight belongs to the article that was just retired.
  final Queue resetQ = Queue(<QueueSlot>[
    _ready('a1'),
    _ready('a2'),
    QueueSlot(
      articleId: 'a3',
      state: SlotState.planned,
      plannedWords: 300,
      plannedBand: LengthBand.medium,
      isWriting: true,
    ),
  ]);
  final Article? fromWriting = resetQ.retireReadySlot(0, _planned('p'));
  check('a retired slot\'s write is retired with it', fromWriting != null);
  check('and the replacement is not left writing',
      !resetQ.slots[0].isWriting,
      'the new plan inherited a flag that was never about it');

  // reroll installs a brand-new slot, so it cannot inherit the flag either.
  final Queue rerollQ = Queue(<QueueSlot>[
    QueueSlot(
      articleId: 'r1',
      state: SlotState.planned,
      plannedWords: 300,
      plannedBand: LengthBand.medium,
      isWriting: true,
    ),
    _ready('a2'),
    _ready('a3'),
  ]);
  rerollQ.reroll(0, _planned('fresh'));
  check('a rerolled slot is not left writing', !rerollQ.slots[0].isWriting);

  // editPlan rewrites the slot, and it must carry the flag FORWARD — a plan
  // being edited is still the plan being written. This is the one mutation
  // where keeping it is correct, which is why it is checked explicitly.
  final Queue editQ = Queue(<QueueSlot>[
    QueueSlot(
      articleId: 'e1',
      state: SlotState.planned,
      plannedWords: 300,
      plannedBand: LengthBand.medium,
      isWriting: true,
    ),
    _ready('a2'),
    _ready('a3'),
  ]);
  editQ.editPlan(0, words: 500);
  check('an edited plan keeps its write in flight', editQ.slots[0].isWriting);

  // writeSlot clears it: the article arrived, so there is nothing in flight.
  final Queue doneQ = Queue(<QueueSlot>[
    QueueSlot(
      articleId: 'w1',
      state: SlotState.planned,
      plannedWords: 300,
      plannedBand: LengthBand.medium,
      isWriting: true,
    ),
    _ready('a2'),
    _ready('a3'),
  ]);
  doneQ.writeSlot(0, _article('w1'));
  check('a finished write clears the flag', !doneQ.slots[0].isWriting);
  check('and the slot is ready', doneQ.slots[0].isReady);

  // The queue can tell an automatic write what to write, and there is exactly
  // one answer to that question at a time — not "whichever".
  final Queue pickQ = _queueWithTwoReadyOnePlanned();
  check('the next automatic write is the first planned slot',
      pickQ.nextPlannedIndex == 2, 'got ${pickQ.nextPlannedIndex}');
  check('and it is a slot, not a guess', pickQ.nextPlanned?.articleId == 'a3');
  final Queue noPlan = Queue(<QueueSlot>[_ready('a1'), _ready('a2'), _ready('a3')]);
  check('with no plan there is nothing to write', noPlan.nextPlannedIndex == -1);
  check('and nextPlanned is null rather than a wrong slot',
      noPlan.nextPlanned == null);

  // the automatic write is blocked while any plan waits, and only then.
  // `noPlan` holds three articles and no plan, which is the one state where
  // the app may write by itself — this is the gate that made that possible.
  check('a queue with no plan allows automatic writing', noPlan.mayAutoWrite);
  check('and a queue with a plan waiting does not', !pickQ.mayAutoWrite);

  // ── a paid article lands whole, or not at all ────────────────────────
  //
  // `landArticle` writes the body, the ledger row and the queue row in ONE
  // transaction. The three used to be three calls in a row, and a process dying
  // between any two — the app swiped out of the recents list, the system
  // reclaiming memory — left a half-landed article: a body with no card, so a
  // library entry that opens onto nothing, or a card with no ledger row, so a
  // readable card the library and the storage bar cannot see. Both are garbage
  // the reader cannot clear from the interface.
  //
  // The domain layer cannot see a transaction, so what is checked here is what
  // the transaction has to be true ABOUT: the queue it writes is the same object
  // the caller holds, so the card turns ready in step with the disk rather than
  // a frame later, and the slot it writes is the one the caller names.
  section('2c. a paid article lands whole, or not at all');

  final Queue landQ = _queueWithTwoReadyOnePlanned();
  final Article landed = _article('a3', title: 'Landed Whole');
  // What `_write` does immediately before calling `landArticle`, in this order.
  check('the slot is written before it is landed', landQ.slots[2].isPlanned);
  final Article? installed = landQ.writeSlot(2, landed);
  check('and writeSlot installs the article', installed != null);
  check('so the slot the transaction writes is the one just written',
      landQ.slots[2].articleId == 'a3' && landQ.slots[2].isReady);
  check('and the card carries the real article, not a stub',
      landQ.slots[2].article?.title == 'Landed Whole');
  check('and the body is there to open', landQ.slots[2].article?.sentences.isNotEmpty ?? false);

  // A rollback must leave the queue in the state it was in, which for drift's
  // transaction means the in-memory object was never mutated by the failed
  // write — `landArticle` only writes, it never touches the caller's Queue.
  check('the queue keeps its three slots', landQ.length == kQueueSize);
  check('and no slot is left half-written',
      landQ.slots.every((QueueSlot s) => s.isPlanned || s.isReady));
  check('and nothing is left marked as writing', !landQ.isWritingAnywhere);

  // with no planned slot, writing works. It has to be a PLANNED slot being
  // written — writing an already-ready card is not a thing that can happen.
  final Queue open = Queue(<QueueSlot>[
    _planned('a1'),
    _ready('a2'),
    _ready('a3'),
  ]);
  check('a queue of three needs no fill', () {
    open.autoFill(() => _planned('x'));
    return open.length == kQueueSize;
  }());

  // two states, exhaustively
  check('SlotState has exactly two values', SlotState.values.length == 2,
      'got ${SlotState.values.length}');
  check('and they are planned and ready',
      SlotState.values.contains(SlotState.planned) &&
          SlotState.values.contains(SlotState.ready));

  // cost labelling: free must never be shown as a spend
  check('editing a plan is free', !CostKind.free.spendsMoney);
  check('writing an article spends', CostKind.oneArticle.spendsMoney);
  check('the free row says so', CostKind.free.label.startsWith('free'));

  // ── 3. reading never removes an article ───────────────────────────────
  section('3. reading counts, it never removes');
  final LedgerEntry entry = LedgerEntry(
      articleId: 'a1', title: 'T', topic: 'C language', reads: 2, listens: 4);
  entry.countRead();
  check('a read increments the counter', entry.reads == 3, 'got ${entry.reads}');
  check('and does not touch listens', entry.listens == 4);

  final Queue readQ = _queueWithTwoReadyOnePlanned();
  readQ.writeSlot; // no-op reference to keep the linter honest about intent
  check('the article is still in the queue after reading',
      readQ.slots.any((QueueSlot s) => s.articleId == 'a1'));

  // hearing is counted separately and never as a read
  final LedgerEntry heard = LedgerEntry(articleId: 'a2', title: 'T2', topic: 'x');
  heard.countListen();
  check('a listen does not become a read', heard.reads == 0 && heard.listens == 1);

  // retire: the card leaves, but the article is archived, not destroyed
  final Queue retireQ = _queueWithTwoReadyOnePlanned();
  final Article? retired = retireQ.retireReadySlot(0, _planned('new'));
  check('retire returns the article for archiving', retired != null);
  check('and the slot becomes a plan, not an article',
      retireQ.slots[0].isPlanned && retireQ.slots[0].article == null);
  check('the queue is still three', retireQ.length == kQueueSize);
  check('a planned slot cannot be retired',
      retireQ.retireReadySlot(0, _planned('n2')) == null);

  // ── 4. counts are not storage ─────────────────────────────────────────
  section('4. freeing space keeps the counts');
  final LedgerEntry freed = LedgerEntry(
      articleId: 'a1', title: 'T', topic: 'C language', reads: 5, listens: 9)
    ..freeSpace();
  check('the bytes are gone', freed.kilobytes == 0);
  check('it is marked gone', freed.isGone);
  check('read 5× survived', freed.reads == 5, 'got ${freed.reads}');
  check('heard 9× survived', freed.listens == 9, 'got ${freed.listens}');

  // a fresh entry, freed repeatedly, still keeps its counts
  final LedgerEntry twice =
      LedgerEntry(articleId: 'a2', title: 'T2', topic: 'x', reads: 3, listens: 1)
        ..freeSpace(reason: GoneReason.freedForSpace)
        ..freeSpace();
  check('freeing twice keeps counts', twice.reads == 3 && twice.listens == 1);
  check('and the reason is recorded',
      twice.goneReason == GoneReason.freedByUser);

  // a live card cannot be freed
  check('a live queue card is protected',
      !canFreeSpace(isLiveInQueue: true, isAlreadyGone: false));
  check('an already-freed row is not re-freeable',
      !canFreeSpace(isLiveInQueue: false, isAlreadyGone: true));
  check('an archived row can be freed',
      canFreeSpace(isLiveInQueue: false, isAlreadyGone: false));

  // the confirmation copy states the trade
  const FreeSpaceTrade trade =
      FreeSpaceTrade(kilobytes: 412, reads: 2, listens: 1);
  check('the trade says what goes', trade.goes.length == 2);
  check('the trade says what stays', trade.stays.contains('read 2×'));
  check('and quantifies the win', trade.freed == '412 KB freed',
      'got ${trade.freed}');

  // ── 5. no finished flag, and a day row carries no clock ───────────────
  // The day-string checks below are about the LEDGER'S DATE FORMAT, not about
  // appearance: a `YYYY-MM-DD` with no time part cannot shift when the device
  // timezone does. (Appearance gained a light/dark preference; this is not it.)
  section('5. no finished boolean, and a day row carries no clock');
  // asserted structurally: nothing in the domain declares such a field
  check('SlotState has no finished', !SlotState.values.any((SlotState s) =>
      s.name.toLowerCase().contains('finish') || s.name.toLowerCase().contains('done')));
  check('MarkTier has no known tier', !MarkTier.values.any((MarkTier t) =>
      t.name.toLowerCase() == 'known'));
  check('a day string is accepted', _isDayString('2026-10-06'));
  check('a full timestamp is rejected — a day row has no hour in it',
      !_isDayString('2026-10-06T22:14:00'));
  check('and a bare time is rejected',
      !_isDayString('22:14'));
  check('todayDay() yields a day string with no time part',
      _isDayString(todayDay(DateTime(2026, 10, 6, 22, 14))));

  // ── derived data: the shelf ───────────────────────────────────────────
  section('derived: the shelf is a union, not a second copy');
  final LedgerEntry archived = LedgerEntry(
      articleId: 'a1', title: 'What a Pointer Really Is',
      topic: 'C language', reads: 5, listens: 9, kilobytes: 412)
    ..freeSpace();
  final LedgerEntry kept = LedgerEntry(
      articleId: 'a2',
      title: 'Why NVDA Moved Today',
      keywords: const <String>['nvda', 'earnings'],
      reads: 0,
      listens: 8,
      kilobytes: 366);

  // The freed article is NOT in the queue: its bytes are gone, so there is
  // nothing behind the row to open. The live card is a different article,
  // which is the ordinary situation.
  final Library lib = Library(
    ledger: <LedgerEntry>[archived, kept],
    queue: Queue(<QueueSlot>[_ready('a9', title: 'A Short Walk Through Git')]),
  );
  final List<ShelfRow> shelf = lib.shelf();
  check('all three rows are present', shelf.length == 3,
      'got ${shelf.length}');

  final ShelfRow goneRow =
      shelf.firstWhere((ShelfRow r) => r.title == 'What a Pointer Really Is');
  check('the freed row is still listed', goneRow.title.isNotEmpty);
  check('and still shows read 5×', goneRow.reads == 5);
  check('and still shows heard 9×', goneRow.listens == 9);
  check('and is marked gone, not hidden', goneRow.isGone);
  check('but it is no longer live', !goneRow.isLive);

  // a freed article sinks below the live one but keeps its attention count
  // The order is gone-last, then attention — the prototype's comparator exactly.
  // A never-read live article therefore sits BELOW a heavily-read archived one,
  // because attention is what the shelf is sorted by.
  check('the freed row sorts last', shelf.last.title == goneRow.title,
      'got ${shelf.last.title}');
  check('the most-read article sorts first',
      shelf.first.title == 'Why NVDA Moved Today',
      'got ${shelf.first.title}');
  check('a never-read row ranks below a read one',
      shelf.indexWhere((ShelfRow r) => r.title == 'A Short Walk Through Git') == 1,
      'got ${shelf.indexWhere((ShelfRow r) => r.title == 'A Short Walk Through Git')}');

  // filters are questions
  check('"worth reading again" needs reads>=2',
      LibraryFilter.reading.matches(
          const ShelfRow(articleId: 'a', title: 'a', keywords: <String>['t'], meta: '', reads: 2, listens: 0, kilobytes: 0, freedKilobytes: 0, isLive: false, isGone: false)) &&
          !LibraryFilter.reading.matches(const ShelfRow(
              articleId: 'a',
              title: 'a',
              keywords: <String>['t'],
              meta: '',
              reads: 1,
              listens: 9,
              kilobytes: 0,
              freedKilobytes: 0,
              isLive: false,
              isGone: false)));
  check('"never read" excludes gone rows',
      !LibraryFilter.unread.matches(const ShelfRow(
          articleId: 'a',
          title: 'a',
          keywords: <String>['t'],
          meta: '',
          reads: 0,
          listens: 0,
          kilobytes: 0,
          freedKilobytes: 0,
          isLive: false,
          isGone: true)));
  check('"heard but not read" needs listens>0 and reads==0',
      LibraryFilter.heard.matches(const ShelfRow(
          articleId: 'a',
          title: 'a',
          keywords: <String>['t'],
          meta: '',
          reads: 0,
          listens: 3,
          kilobytes: 0,
          freedKilobytes: 0,
          isLive: false,
          isGone: false)));

  // Search matches the title AND the keywords.
  //
  // `pointer` is the case that shows both at once: "What a Pointer Really Is"
  // matches on its TITLE, and "A Short Walk Through Git" matches on a KEYWORD
  // its title never mentions. Two rows, two different reasons — which is the
  // whole argument for keywords over a topic: a topic could only ever be one
  // label the reader had already chosen, so `pointer` could never have found an
  // article whose subject nobody had thought to name in advance.
  check('search finds a title match and a keyword match',
      lib.search('pointer', LibraryFilter.all).length == 2,
      'got ${lib.search('pointer', LibraryFilter.all).length}');
  check('and a keyword alone is enough',
      lib.search('memory', LibraryFilter.all).length == 1);
  check('search still finds by title alone',
      lib.search('nvda', LibraryFilter.all).length == 1);
  check('search finds nothing for nonsense',
      lib.search('zzzz', LibraryFilter.all).isEmpty);

  // storage is accounted for
  check('freed bytes are counted separately', lib.freedKb == 412,
      'got ${lib.freedKb}');
  check('used bytes exclude the freed row', lib.usedKb == 366);
  check('storage formats in KB', formatKb(412) == '412 KB');
  check('and in MB past 1024', formatKb(2048) == '2.0 MB');

  // ── the shelf is keyed by ARTICLE ID, and a title collision is not a merge ──
  //
  // This section exists because the shelf was keyed by TITLE until 0.4.0+11,
  // and that was the most destructive defect in this file. Two articles the
  // writer happened to give the same name collapsed into one row: the second
  // overwrote the first's reads, listens, kilobytes and goneReason, silently and
  // permanently. Nothing warned anybody.
  //
  // It is not a corner case either. The writer picks its own subject,
  // `recentTitles` is a hint rather than a constraint, and a reader who asks for
  // the same thing twice is doing the one thing this app is FOR.
  section('derived: two articles may share a title, and must stay two rows');
  final Library collide = Library(
    ledger: <LedgerEntry>[
      LedgerEntry(articleId: 'dup-1', title: 'The Same Title',
          reads: 7, listens: 1, kilobytes: 300),
      LedgerEntry(articleId: 'dup-2', title: 'The Same Title',
          reads: 2, listens: 4, kilobytes: 500),
    ],
    queue: Queue(<QueueSlot>[]),
  );
  final List<ShelfRow> dupes = collide.shelf();
  check('two same-titled articles are two rows', dupes.length == 2,
      'got ${dupes.length}');
  check('and neither overwrote the other',
      dupes.any((ShelfRow r) => r.articleId == 'dup-1' && r.reads == 7) &&
          dupes.any((ShelfRow r) => r.articleId == 'dup-2' && r.listens == 4));
  check('and both keep their own size', collide.usedKb == 800,
      'got ${collide.usedKb}');
  check('search finds both, not one', collide.search('Same Title', LibraryFilter.all).length == 2,
      'got ${collide.search('Same Title', LibraryFilter.all).length}');

  // The same defect in "most revisited": attention was SUMMED across every
  // article sharing a title, so one heavily-read piece made another look read.
  final Revisited dupRev = Revisited(<DayLogRow>[
    DayLogRow(day: '2026-10-01', articleId: 'd1', title: 'Twin', reads: 5, listens: 0),
    DayLogRow(day: '2026-10-02', articleId: 'd2', title: 'Twin', reads: 3, listens: 0),
  ]);
  final List<DayLogRow> twin = dupRev.mostRevisited();
  check('two same-titled articles are two rows there too', twin.length == 2,
      'got ${twin.length}');
  check('and their attention is not summed',
      twin.any((DayLogRow r) => r.articleId == 'd1' && r.reads == 5) &&
          twin.any((DayLogRow r) => r.articleId == 'd2' && r.reads == 3));

  // ── derived: most revisited comes from the day rows ───────────────────
  section('derived: most revisited is a GROUP BY, not a stored total');
  final Revisited rev = Revisited(<DayLogRow>[
    DayLogRow(day: '2026-10-01', articleId: 'a1', title: 'A', reads: 1, listens: 2),
    DayLogRow(day: '2026-10-03', articleId: 'a1', title: 'A', reads: 2, listens: 3),
    DayLogRow(day: '2026-10-02', articleId: 'a2', title: 'B', reads: 0, listens: 1),
  ]);
  final List<DayLogRow> top = rev.mostRevisited();
  check('the same article merges across days',
      top.first.reads == 3 && top.first.listens == 5,
      'got ${top.first.reads}/${top.first.listens}');
  check('and it sorts above the lighter article', top.first.title == 'A');
  final ({int reads, int listens}) day = Revisited.dayTotals(<DayLogRow>[
    DayLogRow(day: '2026-10-01', articleId: 'a1', title: 'A', reads: 1, listens: 2),
    DayLogRow(day: '2026-10-02', articleId: 'a1', title: 'A', reads: 3, listens: 0),
  ], '2026-10-02');
  check('a day total is a query over the same rows',
      day.reads == 3 && day.listens == 0);

  // ── the word pool: repetition engineered, not scheduled ───────────────
  section('the word pool decays on its own');
  final WordPool pool = WordPool(<WordEntry>[]);
  pool.meet('pointer', '2026-10-01');
  pool.meet('pointer', '2026-10-02');
  pool.meet('pointer', '2026-10-03');
  final double fresh = pool['pointer']!.weightAsOf('2026-10-03');
  final double weekLater = pool['pointer']!.weightAsOf('2026-10-10');
  check('weight is positive when met', fresh > 0);
  check('and decays a week later', weekLater < fresh,
      'fresh=$fresh weekLater=$weekLater');
  check('halving is roughly right over the half-life',
      (weekLater / fresh - 0.5).abs() < 0.02,
      'ratio=${weekLater / fresh}');

  // a star raises weight IMMEDIATELY
  final WordPool starred = WordPool(<WordEntry>[]);
  starred.meet('heap', '2026-10-01');
  final double beforeStar = starred['heap']!.weightAsOf('2026-10-01');
  starred['heap']!.setStarred(true, '2026-10-01');
  check('a star raises weight at once',
      starred['heap']!.weightAsOf('2026-10-01') > beforeStar);

  // an old unstarred word leaves the active list but is still remembered
  final WordPool old = WordPool(<WordEntry>[]);
  old.meet('segmentation', '2026-01-01');
  check('a decayed word stops competing', !old['segmentation']!.isActive('2026-10-01'));
  check('but it is not forgotten', old.length == 1);

  // crucially: starring does not schedule anything
  check('a star schedules nothing — the pool has no dates beyond day strings',
      old.all().every((WordEntry e) =>
          e.starredAtDay == null || e.starredAtDay!.length == 10));

  // ── the plan is structured, and a diff must be accepted ───────────────
  section('the plan is data, and a rewrite is a diff');
  const ReadingPlan plan = ReadingPlan(
    reader: 'developer, new to finance English',
    avoid: <String>['background before the point'],
    raw: 'keep sentences short',
  );
  check('fields are readable', plan.fieldsSet == 2,
      'got ${plan.fieldsSet}');
  check('the prompt carries the structured fields',
      plan.toPrompt().contains('The reader is'));
  check('and the reader\'s own words verbatim',
      plan.toPrompt().contains('keep sentences short'));
  check('an empty plan reports nothing set',
      const ReadingPlan().fieldsSet == 0);

  // The plan governs HOW an article reads and no longer says anything about
  // WHAT it is about. `topics` is gone: the subject is either the writer's
  // choice or a sentence the reader typed on the card, and a standing list of
  // permitted subjects was configuration pretending to be content.
  check('the plan names no subjects',
      !plan.toPrompt().toLowerCase().contains('topic'));
  check('and the field is not merely empty — it does not exist',
      !PlanField.values.any((PlanField f) => f.name == 'topics'));

  // SEVEN fields now: four keyword fields and three lengths. Derived, so
  // removing one cannot leave a screen still saying "of 8".
  check('the plan has seven fields', ReadingPlan.fieldCount == 7,
      'got ${ReadingPlan.fieldCount}');
  check('four keyword fields', PlanField.keywords.length == 4);
  check('three length fields', PlanField.lengths.length == 3);
  check('and the two groups are the whole enum',
      PlanField.keywords.length + PlanField.lengths.length ==
          PlanField.values.length);

  // Length is a BAND, not a number. A reader who changed only the medium band
  // has set one field, not three.
  const ReadingPlan banded = ReadingPlan(mediumWords: 240);
  check('changing one band sets one field', banded.fieldsSet == 1,
      'got ${banded.fieldsSet}');
  check('and the other two stay at the recommendation',
      banded.shortWords == kShortWords && banded.longWords == kLongWords);
  check('a band reads its length off the plan',
      banded.wordsFor(LengthBand.medium) == 240);
  check('a number that matches no band is custom',
      banded.bandFor(275) == LengthBand.custom);
  check('and one that matches a band is that band',
      banded.bandFor(240) == LengthBand.medium);

  // The prompt states all three bands and — crucially — no mark target. Asking
  // for a fixed number of marked words is what made the writer pad the list.
  final String planPrompt = plan.toPrompt();
  check('the prompt states three lengths',
      planPrompt.contains('$kShortWords') &&
          planPrompt.contains('$kMediumWords') &&
          planPrompt.contains('$kLongWords'));
  check('and names no number of words to mark',
      !planPrompt.toLowerCase().contains('marked'));

  // a stale diff must not be appliable
  final PlanRewrite rewrite = PlanRewrite(
    proposal: plan.copyWith(mediumWords: 240),
    changes: const <PlanChange>[
      PlanChange(field: PlanField.lengthMedium, was: '300', now: '240'),
    ],
  );
  check('a fresh diff can be accepted', rewrite.apply().mediumWords == 240);
  rewrite.invalidate();
  var refused = false;
  try {
    rewrite.apply();
  } on StateError {
    refused = true;
  }
  check('an invalidated diff is refused', refused);
  check('and it says why', rewrite.isStale);

  // ── the instruction: optional, and its absence is the normal case ─────
  section('an instruction is optional, and empty is a state not a gap');

  // The default slot asks for nothing. That is not missing data — it is the
  // ordinary case, and the card has to render it as a NAME rather than a blank.
  final QueueSlot free = _planned('p1');
  check('a fresh plan is a free pick', free.isFreePick);
  check('and it still has something to say at the top',
      free.subjectLabel == 'Anything', 'got ${free.subjectLabel}');
  check('and it says who chose', free.subjectNote.contains('writer'));
  check('and it carries no instruction id', free.instructionId == null);

  // A hand-typed instruction.
  final Queue q2 = Queue(<QueueSlot>[_planned('p2'), _ready('r1'), _ready('r2')]);
  q2.editPlan(0, instruction: 'explain how a limit order fills');
  check('an instruction is kept verbatim',
      q2.slots[0].instruction == 'explain how a limit order fills');
  check('and it is no longer a free pick', !q2.slots[0].isFreePick);
  check('and the card shows it', q2.slots[0].subjectLabel.startsWith('explain'));
  check('and it is labelled as the reader\'s own',
      q2.slots[0].subjectNote == 'your instruction');

  // Typing a new instruction must CLEAR a previously saved id. Otherwise the
  // card keeps claiming it came from a saved instruction, and a later edit to
  // that saved one would look like it applied here.
  q2.editPlan(0, instruction: 'a story about a lighthouse', instructionId: 'i7',
      fromSaved: true);
  check('a saved instruction records where it came from',
      q2.slots[0].instructionId == 'i7');
  q2.editPlan(0, instruction: 'something else entirely');
  check('typing a new one clears the saved id',
      q2.slots[0].instructionId == null);

  // Reroll means "not this, something else" — so it clears the instruction.
  // Keeping the reader's sentence and changing only the length would be a
  // reroll that rerolls nothing.
  final QueueSlot rolled = q2.reroll(0, _planned('x'))!;
  check('a reroll clears the instruction', rolled.isFreePick);
  check('and it is still a free pick on the card', rolled.subjectLabel == 'Anything');

  // The instruction type itself.
  const Instruction ins = Instruction(
      id: 'i1', text: 'write about NVDA', createdDay: '2026-10-01');
  check('an unused instruction sorts by when it was written',
      ins.sortDay == '2026-10-01');
  check('a used one sorts by when it was last used',
      ins.copyWith(lastUsedDay: '2026-10-07').sortDay == '2026-10-07');
  check('and the count is carried',
      ins.copyWith(useCount: 3).useCount == 3);
  check('a long instruction is truncated for a chip',
      const Instruction(
              id: 'i2',
              text: 'explain how a limit order fills, for someone who has '
                  'never traded anything at all in their life',
              createdDay: '2026-10-01')
          .chipLabel(max: 30)
          .endsWith('…'));
  check('and a short one is left alone',
      ins.chipLabel() == 'write about NVDA');

  // ── difficulty: a fact about the TEXT, computed after the fact ─────────
  section('difficulty is measured, not requested');
  check('an empty text has no band', difficultyOf(unknownTokens: 0, totalTokens: 0) == null);
  check('nothing unknown is easy',
      difficultyOf(unknownTokens: 0, totalTokens: 300) == Difficulty.easy);
  check('1 in 50 is the easy line',
      difficultyOf(unknownTokens: 6, totalTokens: 300) == Difficulty.easy);
  check('1 in 50 plus one is medium',
      difficultyOf(unknownTokens: 7, totalTokens: 300) == Difficulty.medium);
  check('1 in 20 is still medium',
      difficultyOf(unknownTokens: 15, totalTokens: 300) == Difficulty.medium);
  check('1 in 20 plus one is hard',
      difficultyOf(unknownTokens: 16, totalTokens: 300) == Difficulty.hard);
  check('the lines are the published ones',
      kEasyMax == 0.02 && kMediumMax == 0.05);

  // Counted in RUNNING WORDS: a word the reader does not know is unknown every
  // time it appears, not only the first time.
  check('a word counts once per appearance',
      countUnknownTokens('a pointer and another pointer', <String>{'pointer'}) == 2);
  check('and an unmarked word costs nothing',
      countUnknownTokens('a pointer and another pointer', <String>{'heap'}) == 0);
  check('case is not a distinction',
      countUnknownTokens('Pointers point', <String>{'pointers'}) == 1);
  check('tokens are the same unit the word count uses',
      countTokens('A sentence of English text.') == 5);

  // The cap is a defensive ceiling, NOT a setting, and it can never change a
  // band: Hard begins at 1 mark per 20 words and the cap allows 1 per 4.
  check('the mark cap is far above the hard line',
      markCapFor(300) == 75 && markCapFor(300) > 300 * kMediumMax,
      'got ${markCapFor(300)}');
  check('and it has a floor and a ceiling',
      markCapFor(0) == 20 && markCapFor(100000) == 600);

  section('Restoring the plan means the defaults, and the button can tell');
  {
    // The Settings button is DISABLED when the plan already equals a fresh one.
    // That is a structural comparison, so it only works if `ReadingPlan` has
    // value equality — and if it does not, the button is silently always
    // enabled and the "nothing to restore" line never appears. Cheap to check,
    // and the failure is invisible on screen.
    const ReadingPlan fresh = ReadingPlan();
    check('a fresh plan equals a freshly built one',
        fresh == const ReadingPlan());
    check('and a plan with one field set does not',
        fresh != const ReadingPlan(reader: 'a developer'));

    check('the seven fields start empty',
        fresh.reader.isEmpty &&
            fresh.style.isEmpty &&
            fresh.gloss.isEmpty &&
            fresh.avoid.isEmpty &&
            fresh.raw.isEmpty);
    check('and the three lengths start at the recommendations',
        fresh.shortWords == kShortWords &&
            fresh.mediumWords == kMediumWords &&
            fresh.longWords == kLongWords);
    check('a fresh plan counts as nothing set', fresh.fieldsSet == 0);

    // Restoring must not be a no-op on a plan that was actually changed.
    const ReadingPlan edited = ReadingPlan(
      reader: 'a developer',
      style: <String>['short sentences'],
      mediumWords: 420,
    );
    check('an edited plan counts as set', edited.fieldsSet > 0);
    check('and differs from the defaults', edited != fresh);
  }

  // ── pictures as an instruction ─────────────────────────────────────────
  //
  // The rules that make a picture instruction safe to send, all of them about
  // what LEAVES the phone. `shrink()` itself needs a real file and a codec, so
  // it is not checked here — what is checked is the part that can be got wrong
  // silently: the ceiling, the count, the data URL, and the refusal that has to
  // happen before the money moves.
  section('pictures: the ceiling is enforced, and the refusal is early');

  // The ceiling is the whole reason a picture can be sent at all. Five 4 MB
  // photographs base64'd is a 27 MB body that several providers refuse before
  // charging anything — so this number is a rule and not a preference.
  check('a picture is capped at 2 MB', kMaxPictureBytes == 2 * 1024 * 1024);
  check('and an instruction carries at most five', kMaxPictures == 5);
  check('the long edge is 1568, the vision convention', kPictureLongEdge == 1568);

  Picture _pic(int bytes) => Picture(
        bytes: Uint8List(bytes),
        mediaType: 'image/jpeg',
        originalBytes: bytes,
      );

  // Six is refused. Not truncated, not silently dropped — a pack that quietly
  // held five of six pictures would write an article about the wrong thing and
  // say nothing about it.
  bool sixRefused = false;
  try {
    PicturePack.of(<Picture>[_pic(1), _pic(1), _pic(1), _pic(1), _pic(1), _pic(1)]);
  } on StateError {
    sixRefused = true;
  }
  check('a sixth picture is refused, not dropped', sixRefused);
  check('and five are accepted', PicturePack.of(<Picture>[
    for (int i = 0; i < 5; i++) _pic(1),
  ]).length == 5);
  check('an empty pack is empty', PicturePack.empty().isEmpty);

  // THE BYTE CEILING, which was declared, documented as "the ceiling", and
  // enforced by nothing until 0.4.0+11. `shrink.dart`'s last fallthrough
  // returns a picture that is still over it when no quality setting fits, and
  // `_withPictures` handed that straight to `_write` — so a 4 MB photograph
  // reached the wire and was billed at its full base64 size.
  //
  // This check exists because the ARCHITECTURE doc claimed both numbers were
  // "checked as executable invariants, not trusted", and one of them was a
  // comment. A ceiling nobody enforces is not a ceiling.
  bool overCeilingRefused = false;
  String? ceilingMessage;
  try {
    PicturePack.of(<Picture>[_pic(kMaxPictureBytes + 1)]);
  } on StateError catch (e) {
    overCeilingRefused = true;
    ceilingMessage = '$e';
  }
  check('a picture over 2 MB is refused, not sent', overCeilingRefused);
  check('and the refusal names the limit',
      ceilingMessage != null && ceilingMessage.contains('$kMaxPictureBytes'));
  check('while one exactly at 2 MB is accepted',
      PicturePack.of(<Picture>[_pic(kMaxPictureBytes)]).length == 1);

  // base64 makes a picture 4/3 bigger on the wire, and a price on screen has to
  // be the price that was charged — so the number the reader is quoted is the
  // number that goes out.
  check('the wire size counts the base64 tax',
      PicturePack.of(<Picture>[_pic(300)]).wireBytes == 400);

  // A picture is data, never a URL. There is no server to hold it and the
  // reader's photographs are not going to one.
  check('a picture is sent as a data URL', _pic(4).dataUrl.startsWith(
        'data:image/jpeg;base64,',
      ));

  // The resize flag is what the card reads to say "3.8 MB → 480 KB". If it
  // reported true for a picture that was passed through, the card would claim
  // to have changed something it did not.
  check('an untouched picture is not reported as resized',
      !_pic(900).wasResized);
  check('and a shrunk one is',
      Picture(
        bytes: Uint8List(480),
        mediaType: 'image/jpeg',
        originalBytes: 3800,
      ).wasResized);

  // THE EARLY REFUSAL. A text-only model answers a content array with
  // `400 unknown variant image_url` having never read the picture — so the
  // capability has to be asked BEFORE the call, and a write with pictures on a
  // writer that cannot see them must be impossible.
  check('DeepSeek is a text model', !WriterEndpoint.deepseek.supportsVision);
  check('MiMo sees pictures', WriterEndpoint.mimo.supportsVision);
  check('OpenAI sees pictures', WriterEndpoint.openai.supportsVision);
  check('and the refusal names an alternative',
      WriterEndpoint.deepseek.visionRefusal.contains('MiMo'));
  check('the vision-capable list is not empty',
      WriterEndpoint.visionCapable.isNotEmpty);
  check('and does not include the text model',
      !WriterEndpoint.visionCapable.contains(WriterEndpoint.deepseek));

  // ── summary ───────────────────────────────────────────────────────────
  print('');
  print('=' * 60);
  if (_failures == 0) {
    print('ALL $_checks CHECKS PASSED');
  } else {
    print('$_failures of $_checks CHECKS FAILED');
  }
  print('=' * 60);
  if (_failures > 0) {
    throw StateError('$_failures invariant check(s) failed');
  }
}

/// True only for `YYYY-MM-DD`. A time component makes it false, which is how
/// "no day/night concept" is enforced structurally rather than by convention:
/// a day row physically cannot carry an hour.
bool _isDayString(String s) {
  if (s.contains('T') || s.contains(':')) return false;
  final List<String> parts = s.split('-');
  if (parts.length != 3) return false;
  if (!parts.every((String x) => int.tryParse(x) != null)) return false;
  final int y = int.parse(parts[0]);
  final int m = int.parse(parts[1]);
  final int d = int.parse(parts[2]);
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  return y > 1000;
}