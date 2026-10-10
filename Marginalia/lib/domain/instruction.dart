// An instruction: the reader's own words about what to write this time.
//
// This replaces `topic`, and the difference is the whole point. A topic was a
// single NOUN the app had to be told in advance and then reused forever — a
// list of permitted subjects that had to be maintained, and that quietly made
// every article come from the same small set. "NVDA" is not a request; it is a
// label, and a queue of three labels is a queue that stops surprising anyone.
//
// An instruction is a SENTENCE the reader writes when they want something
// specific: "explain how a limit order fills, for someone who has never traded",
// "a short story about a night shift at a lighthouse". It is not maintained —
// it is written once, kept because it worked, and reused if it is wanted again.
//
// Two rules that matter:
//
//  · **It is optional, and its absence is the default.** No instruction means
//    the writer chooses, and that is the normal case. The app never nags for
//    one and never treats an empty slot as missing data.
//
//  · **The text is stored exactly as typed.** It is the reader's own writing
//    and it goes into the prompt verbatim. Nothing here rewrites, shortens or
//    normalises it.

/// One saved instruction.
///
/// [createdDay] and [lastUsedDay] are `YYYY-MM-DD` strings, the same day format
/// the ledger uses — a string rather than a DateTime so a stored row never
/// shifts when the device timezone does. `lastUsedDay` is null until the
/// instruction is actually used to write something, which is why it is
/// nullable and `createdDay` is not.
class Instruction {
  const Instruction({
    required this.id,
    required this.text,
    required this.createdDay,
    this.lastUsedDay,
    this.useCount = 0,
  });

  final String id;

  /// The reader's own words, verbatim.
  final String text;

  final String createdDay;

  /// Null until it has been used. Not the same as [createdDay] — an instruction
  /// written in March and never used is a different fact from one used
  /// yesterday, and the sort has to be able to tell them apart.
  final String? lastUsedDay;

  /// How many times it has been used to write an article. Shown so a reader can
  /// see which of their instructions actually earn their place.
  final int useCount;

  /// The day this instruction sorts by: when it was last used, or when it was
  /// written if it never has been.
  ///
  /// One expression rather than two, because the ordering rule ("most recently
  /// relevant first") has to be the same one the SQL uses — see
  /// `LibraryRepository.instructions`.
  String get sortDay => lastUsedDay ?? createdDay;

  /// What a picker chip shows. Long instructions are truncated for the chip and
  /// shown in full on the row that edits them.
  String chipLabel({int max = 48}) {
    final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max - 1)}…';
  }

  Instruction copyWith({
    String? text,
    String? lastUsedDay,
    int? useCount,
  }) =>
      Instruction(
        id: id,
        text: text ?? this.text,
        createdDay: createdDay,
        lastUsedDay: lastUsedDay ?? this.lastUsedDay,
        useCount: useCount ?? this.useCount,
      );

  @override
  String toString() => 'Instruction($id, used ${useCount}×, "$text")';
}
