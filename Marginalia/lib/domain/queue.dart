// Invariants 1, 2 and 3 — the queue.
//
// `queue.size == 3` is an INVARIANT, not a default. The prototype states it as
// a constant rather than a capacity because the point is that the reader never
// has a morning with nothing ready and never has to plan.
//
// The cost ceiling lives here: if ANY slot holds a plan, nothing is written and
// the app waits for a tap. An unplanned $0.002 call must be impossible while
// the phone is charging and the reader is asleep.

import 'models.dart';

/// How many articles are always waiting. A constant, not a maximum.
const int kQueueSize = 3;

/// The states a cost line can be in. Prices are shown BEFORE the spend, and a
/// "$0.002" beside an action that costs nothing is a lie the reader plans
/// around.
enum CostKind {
  /// Nothing will be written: editing a plan, rerolling, replacing a card.
  free,

  /// One article will be written. About $0.002.
  oneArticle,

  /// One plan rewrite. About $0.002.
  oneRewrite,
}

extension CostKindX on CostKind {
  bool get spendsMoney => this != CostKind.free;

  /// The word shown on the cost row. Free gets JADE, never vermilion:
  /// vermilion is reserved for spending, and free is a good outcome.
  String get label => switch (this) {
        CostKind.free => 'free · nothing is written',
        CostKind.oneArticle => '~\$0.002 · one call · ~25 s',
        CostKind.oneRewrite => '~\$0.002 · one call · ~15 s',
      };
}

/// The result of a queue operation that could have been refused.
class QueueRefusal {
  const QueueRefusal(this.reason);

  final String reason;

  static const notPlanned = QueueRefusal(
      'that one is only planned — write it first');
  static const noSuchSlot = QueueRefusal('that card is no longer there');
}

/// The queue. Every method that could spend money returns whether it did.
///
/// Note what is absent: there is no `markFinished`, no `remove`, no
/// `complete`. Reading is `LedgerEntry.countRead` and nothing else. An article
/// leaves the queue only when the reader says they are done with it, and even
/// then it is ARCHIVED into the ledger, not destroyed.
class Queue {
  Queue(List<QueueSlot> initial)
      : _slots = List<QueueSlot>.of(initial) {
    // A thrown StateError rather than an assert: a broken invariant must be
    // loud in a release build too, and this one is a hard constant.
    if (_slots.length > kQueueSize) {
      throw StateError(
          'the queue holds exactly $kQueueSize slots, never more; got '
          '${_slots.length}');
    }
  }

  final List<QueueSlot> _slots;

  List<QueueSlot> get slots => List<QueueSlot>.unmodifiable(_slots);

  int get length => _slots.length;

  /// Invariant 1. Checked on every mutation rather than only in tests: the
  /// cheapest place to catch a violated invariant is the line that broke it.
  void _assertSize() {
    if (_slots.length > kQueueSize) {
      throw StateError(
          'queue.size == $kQueueSize, got ${_slots.length}');
    }
  }

  int get plannedCount => _slots.where((QueueSlot s) => s.isPlanned).length;

  bool get hasPlannedSlot => plannedCount > 0;

  /// THE COST CEILING, and it is narrower than it first looks.
  ///
  /// DESIGN's words: "if any slot is `planned`, the app writes nothing and waits
  /// for you to tap Write it." That means the gate stops AUTOMATIC writing. It
  /// does NOT stop the reader: the tap is the whole point, every planned card
  /// carries its own Write it button, and an app that refused that tap would be
  /// an app that can never spend a cent — which is not what "a deliberate,
  /// affordable action" means.
  ///
  /// So the two are separate: [mayAutoWrite] guards code that would otherwise
  /// spend without a tap, and [writeSlot] is reachable only by a tap. Keeping
  /// them apart is the whole guarantee: an unplanned $0.002 call cannot happen
  /// while the phone is charging and the reader is asleep, and no tap is ever
  /// refused.
  bool get mayAutoWrite => !hasPlannedSlot;

  /// Refill empty slots with FREE plans. Never writes an article.
  ///
  /// This is the one automatic behaviour in the app, and it costs $0.00: it
  /// installs a plan, not an article. The reader decides later, and deciding
  /// later is free.
  void autoFill(QueueSlot Function() planFactory) {
    if (hasPlannedSlot) return; // a plan is waiting — do not touch it
    while (_slots.length < kQueueSize) {
      _slots.add(planFactory());
    }
    _assertSize();
  }

  /// Write a planned slot. THE ONLY METHOD THAT COSTS MONEY.
  ///
  /// Reachable only from an explicit tap on that card's Write it button, which
  /// is why it does NOT consult [mayAutoWrite]: a reader who taps Write it must
  /// get an article. What it does refuse is a slot that is not planned, so there
  /// is no path that writes something twice.
  ///
  /// Returns the article that was installed, or null on refusal.
  Article? writeSlot(int index, Article article) {
    if (index < 0 || index >= _slots.length) return null;
    if (!_slots[index].isPlanned) return null;

    _slots[index] = _slots[index].copyWith(
      state: SlotState.ready,
      article: article,
      isWriting: false,
    );
    _assertSize();
    return article;
  }

  /// Give a planned slot a different topic and lens. FREE, instant, no input
  /// required.
  ///
  /// This exists because the plan sheet forces a decision and this does not. The
  /// difference between "I must choose" and "show me another and I will decide
  /// later" is the difference between a chore and a queue you keep.
  QueueSlot? reroll(int index, QueueSlot replacement) {
    if (index < 0 || index >= _slots.length) return null;
    final QueueSlot old = _slots[index];
    // keep the identity so the card does not jump
    _slots[index] = QueueSlot(
      articleId: old.articleId,
      state: SlotState.planned,
      article: null,
      topic: replacement.topic,
      focus: replacement.focus,
      plannedWords: replacement.plannedWords,
      plannedMarked: replacement.plannedMarked,
    );
    return _slots[index];
  }

  /// Edit a planned slot's topic and lens in place. FREE.
  void editPlan(int index, {String? topic, String? focus}) {
    if (index < 0 || index >= _slots.length) return;
    final QueueSlot s = _slots[index];
    _slots[index] = s.copyWith(topic: topic ?? s.topic, focus: focus ?? s.focus);
  }

  /// "Done with it": the card leaves the queue and a PLAN takes its place.
  ///
  /// Note it installs a plan, not an article — so the next $0.002 still waits
  /// for a tap. This is what keeps the queue at three without the app spending
  /// anything on its own.
  ///
  /// The article that leaves is ARCHIVED, not destroyed: the caller writes a
  /// ledger row first. An article you cannot find is an article you cannot
  /// re-read, and a fresh article may never have been read at all.
  Article? retireReadySlot(int index, QueueSlot plannedReplacement) {
    if (index < 0 || index >= _slots.length) return null;
    final QueueSlot s = _slots[index];
    if (!s.isReady) return null; // a planned slot has nothing to retire

    final Article? retired = s.article;
    _slots[index] = QueueSlot(
      articleId: s.articleId,
      state: SlotState.planned,
      article: null,
      topic: plannedReplacement.topic.isEmpty
          ? s.topic
          : plannedReplacement.topic,
      focus: plannedReplacement.focus,
      plannedWords: plannedReplacement.plannedWords,
      plannedMarked: plannedReplacement.plannedMarked,
    );
    _assertSize();
    return retired;
  }
}

/// Invariant 4's rule, stated once so there is exactly one way to free space.
///
/// A live queue card cannot be freed: deleting the article the reader is about
/// to open would leave a card pointing at nothing, which is the same class of
/// bug as removing a row something else still depends on.
bool canFreeSpace({
  required bool isLiveInQueue,
  required bool isAlreadyGone,
}) =>
    !isLiveInQueue && !isAlreadyGone;