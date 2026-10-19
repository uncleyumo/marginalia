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
import 'plan.dart' show LengthBand;

/// How many articles are always waiting. A constant, not a maximum.
const int kQueueSize = 3;

/// THE definition of "learned", stated once.
///
/// An article has done its job when the reader CONFIRMED a read at least once
/// AND heard it all the way through at least once. Two different acts, both
/// required: a listen is not a read, and one read-through of a paragraph is
/// not the same as hearing the whole piece. A card that satisfies this leaves
/// the queue; a card that satisfies only half of it stays.
///
/// It lives in `domain/` rather than in the shell because it is a rule, not a
/// widget decision — and because it was got wrong twice by having two
/// near-copies of it in different call sites.
bool isLearned({required int reads, required int listens}) =>
    reads > 0 && listens > 0;

/// The states a cost line can be in. Prices are shown BEFORE the spend, and a
/// "$0.002" beside an action that costs nothing is a lie the reader plans
/// around.
enum CostKind {
  /// Nothing will be written: editing a plan, rerolling, replacing a card.
  free,

  /// One article will be written, in one call. About $0.002.
  oneArticle,

  /// One article, written by the agent. More calls, because the writer may
  /// look something up first.
  ///
  /// This is a separate value rather than a flag on [oneArticle] because the
  /// two must never be confused: the numbers below are the ONLY thing standing
  /// between the reader and a surprise, and the ceiling in them is the loop's
  /// own hard limit (`kMaxModelCalls`). If that constant moves, this string is
  /// a lie — so it is written to be checkable against it.
  researchedArticle,

  /// One plan rewrite. About $0.002.
  oneRewrite,
}

extension CostKindX on CostKind {
  bool get spendsMoney => this != CostKind.free;

  /// The word shown on the cost row. Free gets JADE, never vermilion:
  /// vermilion is reserved for spending, and free is a good outcome.
  String get label => switch (this) {
        CostKind.free => 'free · nothing is written',
        // Minutes, not seconds. A measured 180-word article takes 72 s from
        // MiMo and a long one takes several times that; the old "~25 s" was
        // written when nothing had been timed.
        CostKind.oneArticle => '~\$0.002 · one call · ~1–3 min',
        // Measured: one research run took 274 s end to end (45 s to read two
        // stories, 230 s to write). The upper bound is the loop's own wall
        // clock, so this range cannot promise more than the code allows.
        CostKind.researchedArticle =>
          '~\$0.002–0.010 · up to 5 calls · ~1–10 min',
        CostKind.oneRewrite => '~\$0.002 · one call · ~30 s',
      };

  /// What the button on a card says. Shorter than [label] because it sits on a
  /// button, and it names the CEILING rather than a range — a button that says
  /// "0.002–0.010" is asking the reader to do arithmetic at the moment of
  /// deciding.
  String get buttonLabel => switch (this) {
        CostKind.free => 'free',
        CostKind.oneArticle => 'Write it · ~\$0.002',
        CostKind.researchedArticle => 'Write it · up to 5 calls',
        CostKind.oneRewrite => 'Rewrite · ~\$0.002',
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
/// `complete`. Reading and listening are counts, and [isLearned] states the one
/// rule that turns those counts into "this card has done its job". A card can
/// also leave because the reader said `Done with it`. In both cases the article
/// is ARCHIVED into the ledger, not destroyed.
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

  bool get isEmpty => _slots.isEmpty;

  bool get isNotEmpty => _slots.isNotEmpty;

  /// Invariant 1. Checked on every mutation rather than only in tests: the
  /// cheapest place to catch a violated invariant is the line that broke it.
  void _assertSize() {
    if (_slots.length > kQueueSize) {
      throw StateError(
          'queue.size == $kQueueSize, got ${_slots.length}');
    }
  }

  int get plannedCount => _slots.where((QueueSlot s) => s.isPlanned).length;

  int get readyCount => _slots.where((QueueSlot s) => s.isReady).length;

  bool get hasPlannedSlot => plannedCount > 0;

  /// Whether ANY slot has a write in flight.
  ///
  /// SINGLE FLIGHT, and it is a property of the QUEUE rather than of a slot.
  /// The per-slot `isWriting` guard stops a second tap on the SAME card, which
  /// was enough when every write began with a tap on that card. It stops being
  /// enough the moment a write can begin somewhere else: two writes in the air
  /// is two charges for two articles, and the reader agreed to one.
  ///
  /// Everything that starts a write asks this first. A manual write says so out
  /// loud, because the reader is standing there and a silent refusal reads as a
  /// dead button.
  bool get isWritingAnywhere => _slots.any((QueueSlot s) => s.isWriting);

  /// The first planned slot, or null. What an automatic write picks.
  ///
  /// FIRST, and not "the least recently used" or anything cleverer: the queue is
  /// not ordered, and a rule a reader can predict ("the top one that is not
  /// written yet") is worth more than a rule that picks slightly better. The
  /// reader can always reroll or edit a card to change what gets written next.
  QueueSlot? get nextPlanned {
    for (final QueueSlot s in _slots) {
      if (s.isPlanned) return s;
    }
    return null;
  }

  /// The index of the first planned slot, or -1. [nextPlanned]'s address.
  int get nextPlannedIndex {
    for (int i = 0; i < _slots.length; i++) {
      if (_slots[i].isPlanned) return i;
    }
    return -1;
  }

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

  /// Give a planned slot a different draw: a new random length, and the
  /// subject handed back to the writer. FREE, instant, no input required.
  ///
  /// This exists because the plan sheet forces a decision and this does not. The
  /// difference between "I must choose" and "show me another and I will decide
  /// later" is the difference between a chore and a queue you keep.
  ///
  /// Note what it CLEARS: the instruction. A reroll means "not this, something
  /// else", and keeping the reader's sentence while changing only the length
  /// would be a reroll that rerolls nothing. A reader who wants the same
  /// instruction with a different length is editing the card, not rerolling it.
  QueueSlot? reroll(int index, QueueSlot replacement) {
    if (index < 0 || index >= _slots.length) return null;
    // A reroll is a different plan, so it takes the replacement's fresh id.
    // Keeping the old one could keep a BUNDLED SAMPLE's id on a planned slot,
    // and the next write would then land under that id and be shadowed by the
    // sample every time the queue was drawn. See `retireReadySlot`.
    _slots[index] = QueueSlot(
      articleId: replacement.articleId,
      state: SlotState.planned,
      article: null,
      plannedWords: replacement.plannedWords,
      plannedBand: replacement.plannedBand,
    );
    return _slots[index];
  }

  /// Edit a planned slot's instruction and length in place. FREE.
  ///
  /// Length takes two arguments because they are two facts: [words] is the
  /// number that will be asked for, [band] is where it came from. Passing a
  /// number without saying which band it came from would leave the card
  /// guessing, and a card that guesses calls a reader's custom 300 "medium".
  ///
  /// [instructionId] is passed as `null` when the reader typed something new,
  /// which is why it cannot use the usual `?? this.` default — see below.
  void editPlan(
    int index, {
    String? instruction,
    String? instructionId,
    bool fromSaved = false,
    int? words,
    LengthBand? band,
  }) {
    if (index < 0 || index >= _slots.length) return;
    final QueueSlot s = _slots[index];
    _slots[index] = QueueSlot(
      articleId: s.articleId,
      state: s.state,
      article: s.article,
      instruction: instruction ?? s.instruction,
      // A hand-typed instruction must CLEAR the saved id, or the card would
      // keep claiming it came from a saved one and a later edit to that saved
      // instruction would look like it applied here. `copyWith` cannot express
      // "set to null", so this is a constructor call rather than a copyWith.
      instructionId: fromSaved ? instructionId : null,
      plannedWords: words ?? s.plannedWords,
      plannedBand: band ?? s.plannedBand,
      isWriting: s.isWriting,
    );
  }

  /// Give a planned slot a new identity.
  ///
  /// Identity is minted, not reused: a slot whose id names a bundled sample
  /// must not receive a paid write under that id, because every later lookup
  /// prefers the bundle and the written article becomes unopenable. Edits
  /// (`editPlan`) keep the id on purpose — this is the one call that replaces
  /// it, and it refuses to touch a slot that is not planned.
  void reidentify(int index, String articleId) {
    if (index < 0 || index >= _slots.length) return;
    final QueueSlot s = _slots[index];
    if (!s.isPlanned) return;
    _slots[index] = QueueSlot(
      articleId: articleId,
      state: s.state,
      article: s.article,
      instruction: s.instruction,
      instructionId: s.instructionId,
      plannedWords: s.plannedWords,
      plannedBand: s.plannedBand,
      isWriting: s.isWriting,
    );
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
    // The replacement keeps ITS OWN id, not the retired article's.
    //
    // Reusing the old id made two different articles one identity: the
    // retired body stayed reachable under the id the new write was about to
    // take, and any lookup that preferred the older body showed the wrong
    // article — a bundled sample in particular shadowed every later write
    // into its slot. Identity is cheap to mint and fatal to share.
    _slots[index] = QueueSlot(
      articleId: plannedReplacement.articleId,
      state: SlotState.planned,
      article: null,
      // The replacement's instruction, whatever it is. A ready slot has no
      // instruction of its own to fall back to — that field describes what is
      // about to be written, and this article has already been written.
      instruction: plannedReplacement.instruction,
      instructionId: plannedReplacement.instructionId,
      plannedWords: plannedReplacement.plannedWords,
      plannedBand: plannedReplacement.plannedBand,
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