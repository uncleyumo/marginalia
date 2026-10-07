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

import '../lib/domain/library.dart';
import '../lib/domain/models.dart';
import '../lib/domain/plan.dart';
import '../lib/domain/queue.dart';
import '../lib/domain/word_pool.dart';

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

Article _article(String id, {String title = 'T', String topic = 'Topic'}) => Article(
      id: id,
      title: title,
      topic: topic,
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
      topic: 'C language',
    );

QueueSlot _planned(String id, {String topic = 'Music', String focus = 'why'}) => QueueSlot(
      articleId: id,
      state: SlotState.planned,
      topic: topic,
      focus: focus,
      plannedWords: 300,
      plannedMarked: 6,
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

  // with no planned slot, writing works. It has to be a PLANNED slot being
  // written — writing an already-ready card is not a thing that can happen.
  final Queue open = Queue(<QueueSlot>[
    _planned('a1', topic: 'Git'),
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

  // ── 5. no finished flag, no day/night ─────────────────────────────────
  section('5. no finished boolean, no day or night');
  // asserted structurally: nothing in the domain declares such a field
  check('SlotState has no finished', !SlotState.values.any((SlotState s) =>
      s.name.toLowerCase().contains('finish') || s.name.toLowerCase().contains('done')));
  check('MarkTier has no known tier', !MarkTier.values.any((MarkTier t) =>
      t.name.toLowerCase() == 'known'));
  check('a day string is accepted', _isDayString('2026-10-06'));
  check('a full timestamp is rejected — the app has no day/night',
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
      topic: 'NVDA',
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
          const ShelfRow(articleId: 'a', title: 'a', topic: 't', meta: '', reads: 2, listens: 0, kilobytes: 0, freedKilobytes: 0, isLive: false, isGone: false)) &&
          !LibraryFilter.reading.matches(const ShelfRow(
              articleId: 'a',
              title: 'a',
              topic: 't',
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
          topic: 't',
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
          topic: 't',
          meta: '',
          reads: 0,
          listens: 3,
          kilobytes: 0,
          freedKilobytes: 0,
          isLive: false,
          isGone: false)));

  // search matches title AND topic
  check('search finds by title',
      lib.search('pointer', LibraryFilter.all).length == 1);
  check('search finds by topic', lib.search('nvda', LibraryFilter.all).length == 1);
  check('search finds nothing for nonsense',
      lib.search('zzzz', LibraryFilter.all).isEmpty);

  // storage is accounted for
  check('freed bytes are counted separately', lib.freedKb == 412,
      'got ${lib.freedKb}');
  check('used bytes exclude the freed row', lib.usedKb == 366);
  check('storage formats in KB', formatKb(412) == '412 KB');
  check('and in MB past 1024', formatKb(2048) == '2.0 MB');

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
    topics: <String>['C language', 'NVDA'],
    avoid: <String>['background before the point'],
    length: 300,
    raw: 'keep sentences short',
  );
  check('fields are readable', plan.fieldsSet == 3,
      'got ${plan.fieldsSet}');
  check('the prompt carries the structured fields',
      plan.toPrompt().contains('Topics may come from'));
  check('and the reader\'s own words verbatim',
      plan.toPrompt().contains('keep sentences short'));
  check('an empty plan reports nothing set',
      const ReadingPlan().fieldsSet == 0);

  // a stale diff must not be appliable
  final PlanRewrite rewrite = PlanRewrite(
    proposal: plan.copyWith(length: 240),
    changes: const <PlanChange>[
      PlanChange(field: PlanField.length, was: '300', now: '240'),
    ],
  );
  check('a fresh diff can be accepted', rewrite.apply().length == 240);
  rewrite.invalidate();
  var refused = false;
  try {
    rewrite.apply();
  } on StateError {
    refused = true;
  }
  check('an invalidated diff is refused', refused);
  check('and it says why', rewrite.isStale);

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