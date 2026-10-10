// How hard a written article is — FOR THE TEXT, not for the reader.
//
// This file exists because of a decision about where a judgement belongs. The
// plan used to carry a `marked` number: the reader set "6", the prompt said "at
// most 6 words marked", and the parser truncated at 6. That is backwards. Asking
// a writer for a fixed number of marked words makes it pad the list with words
// that did not need marking, and a list of marks that is wrong is worse than a
// short one — the reader's attention is the thing being spent.
//
// So the model decides how many words to mark, and the app does the arithmetic
// afterwards. The number the reader sees is a fact about the article, computed
// from what the writer actually marked.

/// The three bands the app states.
///
/// Three, because the evidence supports roughly two useful lines (see below) and
/// a fourth band would be a distinction the research does not make.
enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const Difficulty(this.label);

  /// Shown verbatim. English, like everything else on screen.
  final String label;
}

/// The lines between the bands, as a share of the running words.
///
/// From the lexical-coverage literature, where "coverage" is the share of
/// RUNNING WORDS (tokens) the reader knows:
///
///  · **98% (1 unknown in 50)** — the comfortable line for unassisted reading.
///    Hu & Nation (2000), *Reading in a Foreign Language* 13(1) 403–430;
///    Nation (2006), *Canadian Modern Language Review* 63(1) 59–82, which
///    states it outright as "98% (1 unknown word in 50)"; Laufer &
///    Ravenhorst-Kalovski (2010) call this the "optimal" threshold.
///
///  · **95% (1 unknown in 20)** — the floor. Laufer (1989) found 95% to be the
///    point at which readers of academic text reached adequate comprehension;
///    below it the same literature calls the material frustrating.
///
/// Two things this scale is NOT, both of which the app says out loud in
/// Settings → The small print:
///
///  · **It is not a threshold in the strong sense.** Schmitt, Jiang & Grabe
///    (2011), *Modern Language Journal* 95(1) 26–43, tested 661 readers and
///    found a LINEAR relationship with "no indication of a vocabulary
///    'threshold'". Webb, Pellicer-Sánchez & Wang (2025) failed to replicate
///    the threshold effect and found coverage explained only ~11% of the
///    variance. The lines below are conventions, not cliffs.
///
///  · **It says nothing about one particular reader.** In Schmitt's own data,
///    some readers scored 7/30 at 100% coverage. Background knowledge moved
///    scores more than coverage did.
///
/// And a third, specific to this app: the words the writer marked are the words
/// a writer THOUGHT would be hard, not the words this reader actually does not
/// know. Every band is an estimate of the text, and it is labelled as one.
const double kEasyMax = 0.02; // 98% coverage — 1 unknown word in 50
const double kMediumMax = 0.05; // 95% coverage — 1 unknown word in 20

/// Which band an article falls in, or null when there is nothing to measure.
///
/// Both counts are in RUNNING WORDS, not distinct ones — that is the unit the
/// research uses, and it is also the honest one: a reader who does not know
/// `pointers` does not know it any better the third time it appears.
///
/// Null rather than a default when [totalTokens] is zero. A stub article read
/// back from the database has no body in memory, and "no answer" is the truth
/// there; calling it Easy would be inventing a reading.
Difficulty? difficultyOf({
  required int unknownTokens,
  required int totalTokens,
}) {
  if (totalTokens <= 0) return null;
  if (unknownTokens <= 0) return Difficulty.easy;
  final double ratio = unknownTokens / totalTokens;
  if (ratio <= kEasyMax) return Difficulty.easy;
  if (ratio <= kMediumMax) return Difficulty.medium;
  return Difficulty.hard;
}

/// What counts as a word, for both halves of the ratio.
///
/// Deliberately the same expression `ArticleWriter._count` uses to compute an
/// article's length. If the two disagreed, the band would be a ratio between
/// two different units — a percentage of something that is not the thing it
/// claims to be a percentage of.
final RegExp _word = RegExp(r"[A-Za-z][A-Za-z'\-]*");

/// Running words in one piece of text.
int countTokens(String text) => _word.allMatches(text).length;

/// How many of those running words the reader will not know.
///
/// [forms] holds BOTH the word as printed and its dictionary form, because a
/// reader who does not know `pointer` does not know `pointers` either, and the
/// writer marks whichever of the two the sentence happened to use. Counting
/// positions rather than matches is what keeps a word that appears three times
/// from being counted once.
int countUnknownTokens(String text, Set<String> forms) {
  if (forms.isEmpty) return 0;
  int n = 0;
  for (final RegExpMatch m in _word.allMatches(text)) {
    if (forms.contains(m[0]!.toLowerCase())) n++;
  }
  return n;
}

/// A ceiling on how many marks are kept, and NOT a setting.
///
/// The reader does not choose this and it is not in Settings. It exists so that
/// a pathological answer — a model that underlines half the page — cannot blow
/// up the parser or the render, and that is all it is for.
///
/// It is deliberately far above the Hard line: Hard begins at 1 mark per 20
/// words (5%), and this permits 1 per 4 (25%), five times as much. So it can
/// never silently change a band. An article dense enough to be truncated here
/// was already unreadable, and one that merely reads as Hard passes through
/// untouched and is reported as Hard.
int markCapFor(int wordCount) => (wordCount ~/ 4).clamp(20, 600);
