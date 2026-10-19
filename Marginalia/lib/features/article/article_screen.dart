// The reading screen.
//
// This is the product. Everything else is bookkeeping.
//
// Three decisions shape the whole file:
//
// 1. TAPPING A WORD IS THE INTERACTION. Not long-press, not a selection menu, not
//    a mode you have to discover. You tap the word and the gloss appears. The
//    reason is stated in the prototype and it is the right reason: "the reader
//    asked for it and was answered" beats "the reader performed an action and
//    hoped".
//
// 2. NO BAR ON THE PROGRESS. There is no percentage, no "3 of 5", no estimate
//    time remaining. The article ends when it ends, and nothing about the
//    interface suggests the reader is behind.
//
// 3. NO PER-LINE BUTTONS. The previous version put a 译 button and a ♪ button
//    under EVERY sentence, which is roughly a dozen pairs of buttons between the
//    reader and the end of the first paragraph. The prototype's promise — every
//    word and every sentence has sound and a way to reach its meaning — is kept,
//    but it is kept by ONE mechanism each instead of a pair per line:
//
//      · tap a word        → the word sheet: English, then the translation one
//                            tap further, and "Say it" for the pronunciation
//      · long-press a line → hear that one sentence, with the line marked
//      · the two toolbar buttons → show or hide EVERY translation at once, and
//                            set the reading size
//
//    One row of controls, at the top, where a control belongs. The page below it
//    is text and nothing else.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart';
import '../../domain/models.dart';

/// The reading sizes the toolbar offers. Three, because three is enough to
/// notice and few enough to choose without thinking.
enum ReadSize {
  small(16.0, 'Small'),
  medium(17.5, 'Medium'),
  large(19.5, 'Large');

  const ReadSize(this.px, this.label);

  final double px;
  final String label;

  ReadSize get smaller =>
      index == 0 ? this : ReadSize.values[index - 1];

  ReadSize get larger => index == ReadSize.values.length - 1
      ? this
      : ReadSize.values[index + 1];
}

/// What the sentence renderer needs to know about a word.
class WordHit {
  const WordHit({required this.surface, required this.sentenceIndex});

  final String surface;
  final int sentenceIndex;
}

/// The article. Tappable words, a global translation toggle, and a re-armed
/// "count this read" at the end.
class ArticleScreen extends StatefulWidget {
  const ArticleScreen({
    super.key,
    required this.article,
    required this.onWordTap,
    required this.onCountRead,
    required this.speakingIndex,
    required this.onSpeakSentence,
    this.readsToday = 0,
    this.readsInAll = 0,
    this.counting = false,
    this.fromLibrary = false,
    this.ledgerMeta,
    required this.onBack,
    this.readSize = ReadSize.medium,
    this.onReadSize,
  });

  final Article article;

  /// Every tap routes here, so the dictionary, the star and the history write
  /// all hang off one call site rather than being scattered through the render.
  final void Function(String surface, int sentenceIndex) onWordTap;

  /// Invariant 3: this counts, and the article STAYS. There is no removal
  /// anywhere on this screen, and there is deliberately no "done" affordance.
  final VoidCallback onCountRead;

  /// How many times this article has been read today, and in all. Both are
  /// read from the database when the screen opens, so coming back tomorrow does
  /// not look the same as never having been here.
  ///
  /// [readsToday] is what makes the button a live control rather than a dead
  /// one: the reader presses it and a number on the screen changes, which is
  /// the only thing that tells them the press landed.
  final int readsToday;
  final int readsInAll;

  /// A count is being written. The button spins and refuses a second press —
  /// the same contract as `Write it` on a card, and for the same reason: a
  /// control that looks identical before and after a tap gets tapped again.
  final bool counting;

  /// Already counted today. The button re-arms either way: reading twice is
  /// normal, and an article the reader returns to is the whole point.
  bool get counted => readsToday > 0;

  /// Opened from the shelf rather than the queue, so the header says so and the
  /// counts are the archived ones.
  final bool fromLibrary;

  /// The archived counts, when [fromLibrary] is true.
  final String? ledgerMeta;

  /// Where the header's back label goes. The label is not decoration: it says
  /// "‹ Library" or "‹ Queue", so it had better be the thing that does it.
  final VoidCallback onBack;

  /// The sentence currently being spoken, or -1. The line marks itself so the
  /// reader can hear where they are without a progress bar.
  final int speakingIndex;
  final void Function(int sentenceIndex) onSpeakSentence;

  final ReadSize readSize;
  final ValueChanged<ReadSize>? onReadSize;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  /// Whether EVERY sentence shows its translation. One switch for the whole
  /// article, rather than a button per line.
  bool _showAllChinese = false;

  /// The lines the reader has opened individually, by sentence index. Set when a
  /// line is long-pressed for sound, which also marks it while it speaks.
  final Set<int> _opened = <int>{};

  /// The size the article is set at. The parent owns it when it hands down an
  /// `onReadSize`; otherwise this screen is the owner and `readSize` is the
  /// starting point. The ternary that used to be here returned the same field on
  /// both branches, so it read as a decision and made none.
  ReadSize get _size => widget.readSize;

  void _toggleAll() => setState(() {
        _showAllChinese = !_showAllChinese;
        if (!_showAllChinese) _opened.clear();
      });

  void _resize(ReadSize next) {
    if (widget.onReadSize != null) widget.onReadSize!(next);
  }

  /// Long-press: hear this line. The mark stays until the reader long-presses
  /// again to stop it, or taps a word (which is a different question).
  void _onSentenceLongPress(int index) {
    setState(() {
      final bool wasOpen = _opened.remove(index);
      if (!wasOpen) _opened.add(index);
      if (!wasOpen) widget.onSpeakSentence(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final ReadSize size = _size;

    return PageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 6, Gap.gutter, 40),
        children: <Widget>[
          _header(context, c),
          const SizedBox(height: 18),
          // The title is the first thing a reader meets and often the hardest
          // words in the piece. Its words are tappable, same lookup as the body.
          _TappableTitle(
            text: widget.article.title,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: (context.texts.titleLarge?.fontSize ?? 21) + 3,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.02,
              color: c.ink,
            ),
            onWordTap: (String w) => widget.onWordTap(w, -1),
          ),
          // The Chinese title, when the writer produced one. Empty is normal
          // for older articles — the tappable words above still work.
          if (widget.article.titleCn.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              widget.article.titleCn,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 15,
                height: 1.5,
                color: c.ink2,
              ),
            ),
          ],
          const SizedBox(height: 5),
          // What this is about, in the writer's own words. The same mono line
          // the card carries, so the article and the card that led to it agree.
          Text(
            widget.article.keywords.isEmpty
                ? 'no keywords'
                : widget.article.keywords.join(' · '),
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 11,
              color: c.ink3,
            ),
          ),
          if (widget.fromLibrary && widget.ledgerMeta != null) ...<Widget>[
            const SizedBox(height: 14),
            _banner(context, c),
          ],
          const SizedBox(height: 20),
          _toolbar(context, c),
          const SizedBox(height: 22),
          for (int i = 0; i < widget.article.sentences.length; i++) ...<Widget>[
            _SentenceView(
              key: ValueKey<int>(i),
              index: i,
              sentence: widget.article.sentences[i],
              marks: _marksIn(i),
              onWordTap: (String w) => widget.onWordTap(w, i),
              onLongPress: () => _onSentenceLongPress(i),
              showChinese: _showAllChinese || _opened.contains(i),
              speaking: widget.speakingIndex == i,
              sizePx: size.px,
            ),
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 16),
          _endMark(context, c),
          const SizedBox(height: 24),
          _countButton(context, c),
        ],
      ),
    );
  }

  List<Mark> _marksIn(int sentenceIndex) => widget.article.marks
      .where((Mark m) => m.sentenceIndex == sentenceIndex)
      .toList();

  Widget _header(BuildContext context, Palette c) {
    return Row(
      children: <Widget>[
        BackLabel(
          label: widget.fromLibrary ? '‹ Library' : '‹ Queue',
          onTap: widget.onBack,
        ),
        const Spacer(),
        Text(
          // Same line, same mono, same quiet colour as the card. The label is
          // an estimate of the TEXT — the words the writer thought would be
          // hard — and Settings → The small print says so at length. What it
          // is not is a verdict on the reader, which is why it sits with the
          // word count rather than anywhere it could be mistaken for a score.
          <String>[
            '${widget.article.wordCount} words',
            '≈ ${widget.article.minuteEstimate} min',
            if (widget.article.difficulty != null)
              widget.article.difficulty!.label,
          ].join(' · '),
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 10.5,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  /// One row, at the top: the translation switch and the reading size.
  ///
  /// Everything a line used to carry sits here instead, which is why the page
  /// below is only text. The sound control is NOT here on purpose — the reader
  /// hears a word from its sheet and a line by pressing it, and the whole-article
  /// listen view already exists as the second tab. Three controls is enough.
  Widget _toolbar(BuildContext context, Palette c) {
    final Widget translate = _Toggle(
      icon: Icons.translate,
      label: 'Translation',
      active: _showAllChinese,
      onTap: _toggleAll,
    );

    if (widget.onReadSize == null) {
      return Row(children: <Widget>[translate]);
    }

    return Row(
      children: <Widget>[
        translate,
        const Spacer(),
        _SizeBtn(
          icon: Icons.text_decrease,
          tip: 'Smaller text',
          onTap: _size == ReadSize.small
              ? null
              : () => _resize(_size.smaller),
        ),
        const SizedBox(width: 6),
        Text(
          _size.label,
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 10.5,
            color: c.ink3,
          ),
        ),
        const SizedBox(width: 6),
        _SizeBtn(
          icon: Icons.text_increase,
          tip: 'Larger text',
          onTap: _size == ReadSize.large
              ? null
              : () => _resize(_size.larger),
        ),
      ],
    );
  }

  /// The banner shown when an article is reopened from the shelf. It exists so
  /// Back goes to the Library and the counts on screen are the ARCHIVED ones —
  /// DESIGN's own rule: "reads and listens still work".
  Widget _banner(BuildContext context, Palette c) {
    final String? meta = widget.ledgerMeta;
    final String line = meta == null || meta.isEmpty
        ? 'From your library · reading it again counts'
        : 'From your library · $meta · reading it again counts';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.bookmark_outline, size: 15, color: c.ink3),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              line,
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 12,
                color: c.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The end of the article. A hairline and a rule — not a "you have reached the
  /// end" card.
  Widget _endMark(BuildContext context, Palette c) {
    return Column(
      children: <Widget>[
        Hairline(color: c.hair),
        const SizedBox(height: 12),
        Text(
          '·  ·  ·',
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 11,
            letterSpacing: 0.4,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  /// What the reader has actually done with this article, in one line.
  ///
  /// THIS LINE IS THE FEATURE. It used to be a static prompt — "finished
  /// reading?" before, "counted. read it again and it will count again." after —
  /// and the second one never appeared on a fresh visit, because the flag behind
  /// it was never passed in. So the button behaved identically whether the
  /// reader had counted the article four times or never: press it, read a toast
  /// that fades in three seconds, and the screen is unchanged. The obvious
  /// conclusion is that it did not work, and the obvious response is to press it
  /// again.
  ///
  /// A number that changes is the only honest receipt. So the line states the
  /// count, before and after, and it comes from the database rather than from
  /// this session's memory.
  String get _countLine {
    if (widget.readsToday == 0) {
      // Not counted today. The history still matters: an article the reader has
      // been through four times should not greet them as a stranger.
      if (widget.readsInAll == 0) return 'finished reading?';
      return 'finished reading? · read ${times(widget.readsInAll)} before, '
          'not today';
    }
    if (widget.readsInAll <= 1) return 'counted · the first read';
    return 'counted ${times(widget.readsToday)} today · '
        '${widget.readsInAll} in all';
  }

  /// The only button on this screen. It counts; it does not finish.
  ///
  /// DESIGN: "You read it. Count it? — it stays in your queue afterwards."
  /// That "afterwards" is the invariant. There is no variant of this screen
  /// where reading removes anything.
  Widget _countButton(BuildContext context, Palette c) {
    return Column(
      children: <Widget>[
        Text(
          _countLine,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: widget.counted ? c.ink2 : c.ink3,
          ),
        ),
        const SizedBox(height: 9),
        Btn(
          label: widget.counting
              ? 'Counting…'
              : widget.counted
                  ? 'Count it again'
                  : 'Count this read',
          primary: false,
          busy: widget.counting,
          onPressed: widget.onCountRead,
        ),
        const SizedBox(height: 11),
        Text(
          'it stays in your queue. reading never removes anything.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 11.5,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}

/// One toolbar control: an icon and a word, in a compact pill.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: active ? c.vermWash : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? c.verm : c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: active ? c.vermInk : c.ink2,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? c.vermInk : c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeBtn extends StatelessWidget {
  const _SizeBtn({
    required this.icon,
    required this.tip,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final Widget button = SizedBox(
      width: 34,
      height: 32,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.hair),
            ),
            child: Icon(
              icon,
              size: 16,
              color: onTap == null ? c.ink3.withValues(alpha: 0.45) : c.ink2,
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: tip, child: button);
  }
}

/// One sentence: tappable words, a mark while it is being spoken, and the
/// translation underneath when it is wanted.
class _SentenceView extends StatelessWidget {
  const _SentenceView({
    super.key,
    required this.index,
    required this.sentence,
    required this.marks,
    required this.onWordTap,
    required this.onLongPress,
    required this.showChinese,
    required this.speaking,
    required this.sizePx,
  });

  final int index;
  final Sentence sentence;
  final List<Mark> marks;
  final void Function(String surface) onWordTap;
  final VoidCallback onLongPress;
  final bool showChinese;

  /// True while this line is the one being heard. A wash and a left rule, not a
  /// highlight colour across the words: the sentence has to stay readable while
  /// it is being read aloud.
  final bool speaking;
  final double sizePx;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final Widget line = TappableSentence(
      text: sentence.english,
      marks: marks,
      onWordTap: onWordTap,
      onLongPress: onLongPress,
      sizePx: sizePx,
      baseColor: c.ink,
    );

    if (!showChinese) {
      return speaking ? _marked(c, line) : line;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        speaking ? _marked(c, line) : line,
        const SizedBox(height: 6),
        Text(
          sentence.chinese,
          // The translation is read, so it takes the reading face too. This is
          // the line where the choice is most visible: a serif English
          // sentence over sans Chinese is exactly what the reader is picking
          // a face to avoid.
          style: context.readingFace
              .style(c.ink2, 14.5, height: 1.7),
        ),
      ],
    );
  }

  /// The speaking mark. A left rule in vermilion and a barely-there wash — the
  /// reader must still be able to read the line while they listen to it.
  Widget _marked(Palette c, Widget line) {
    return Container(
      decoration: BoxDecoration(
        color: c.vermWash.withValues(alpha: 0.5),
        border: Border(
          left: BorderSide(color: c.verm, width: 2.5),
        ),
      ),
      padding: const EdgeInsets.only(left: 10),
      child: line,
    );
  }
}

/// The sentence, split into tappable words.
///
/// A marked word is COLOURED and carries a thin underline rather than a filled
/// box: a rectangle would hide the word it is annotating, and the sentence
/// around it has to stay readable.
///
/// Hit-testing asks the [RenderParagraph] that drew the sentence, rather than a
/// per-span recogniser or a painter rebuilt from the string. A recogniser per
/// word loses the punctuation spacing — the tap area has to include the space
/// after the word, or half of every tap misses. A rebuilt painter loses it a
/// different way: it agrees with the screen about nothing, and the disagreement
/// grows with the font size, which is the mis-hit this replaced.
class TappableSentence extends StatelessWidget {
  TappableSentence({
    super.key,
    required this.text,
    required this.marks,
    required this.onWordTap,
    required this.onLongPress,
    required this.sizePx,
    required this.baseColor,
  });

  final String text;
  final List<Mark> marks;
  final void Function(String surface) onWordTap;
  final VoidCallback onLongPress;
  final double sizePx;
  final Color baseColor;

  static final RegExp _word = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  /// The RenderParagraph that drew this sentence.
  ///
  /// A key rather than a context captured in build, because [_resolve] runs
  /// from a gesture and the gesture's context is the GestureDetector's, one
  /// level above the text. The current context is read at tap time, which is
  /// when it is valid.
  final GlobalKey _bodyKey = GlobalKey();

  /// Offsets of every word, so a tap can be mapped back to one. Computed once
  /// per build rather than per tap.
  List<({int start, int end, String word})> _tokens() {
    final List<({int start, int end, String word})> out =
        <({int start, int end, String word})>[];
    for (final RegExpMatch m in _word.allMatches(text)) {
      out.add((start: m.start, end: m.end, word: m.group(0)!));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final ReadingFace face = context.readingFace;
    final Map<String, MarkTier> tiers = <String, MarkTier>{
      for (final Mark m in marks) m.surface.toLowerCase(): m.tier,
    };

    final List<TextSpan> spans = <TextSpan>[];
    int cursor = 0;
    for (final ({int start, int end, String word}) t in _tokens()) {
      if (t.start > cursor) {
        // The gap carries the face too. It used to inherit whatever size the
        // ambient default style happened to pick, which made punctuation a
        // different size from the words around it — and made every caret
        // measured by [_resolve] drift by a fraction of a glyph against what
        // is actually on screen.
        spans.add(TextSpan(
          text: text.substring(cursor, t.start),
          style: face.style(baseColor, sizePx, height: 1.86),
        ));
      }
      final MarkTier? tier = tiers[t.word.toLowerCase()];
      spans.add(TextSpan(
        text: t.word,
        style: face.style(
          switch (tier) {
            MarkTier.unfamiliar => c.vermInk,
            MarkTier.difficult => c.jade,
            null => baseColor,
          },
          sizePx,
          height: 1.86,
        ).copyWith(
          decoration: tier == null ? TextDecoration.none : TextDecoration.underline,
          decorationColor: tier == MarkTier.unfamiliar ? c.verm : c.jade,
          decorationThickness: 1.6,
        ),
      ));
      cursor = t.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: face.style(baseColor, sizePx, height: 1.86),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails d) => _resolve(d.globalPosition),
      // Long press is how a LINE is heard. A tap is a question about a word;
      // a press-and-hold is a question about the sentence around it, and the
      // two never compete for the same gesture.
      onLongPress: onLongPress,
      child: Text.rich(
        key: _bodyKey,
        TextSpan(style: TextStyle(color: baseColor), children: spans),
      ),
    );
  }

  /// Which word was tapped, asked of the RenderParagraph that is ALREADY on
  /// screen rather than of a painter rebuilt here.
  ///
  /// This is the fix for the long-standing mis-hit. The previous version built
  /// a TextPainter from the same string and measured against that, and it
  /// drifted from what the reader was looking at in four separate ways: it
  /// omitted the underline decoration the marked words carry (which changes
  /// line height), it passed no textScaler, it measured at the LayoutBuilder's
  /// maxWidth instead of the width the text actually wrapped at, and it knew
  /// nothing about the 10px of left padding a speaking sentence gains. Every
  /// one of those is invisible on a small short sentence and obvious on a
  /// large-font long one, which is why the bug read as "sometimes".
  ///
  /// The RenderParagraph has none of that problem: it IS the layout. Same
  /// font, same scaler, same wrapping, same decorations, same padding, because
  /// it is the object that drew the words the reader pointed at.
  ///
  /// A miss still reports the nearest word rather than nothing: the reader
  /// pointed at the text, and answering with an empty card would read as the
  /// app being broken.
  void _resolve(Offset globalPosition) {
    final List<({int start, int end, String word})> tokens = _tokens();
    if (tokens.isEmpty) return;

    final RenderObject? ro = _bodyKey.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) {
      // Not laid out yet — a tap that arrives between builds. The old code
      // would have answered from a painter, so answer from the first token
      // rather than dropping the gesture on the floor.
      onWordTap(tokens.first.word);
      return;
    }

    // The paragraph's own coordinate space. globalPosition comes from the
    // gesture, so it has to come back to local before the render object can
    // use it.
    final Offset position = ro.globalToLocal(globalPosition);

    // Ask where the tap landed in TEXT, then take the word under it. An x-only
    // band test cannot tell line 2 from line 1 on a wrapped sentence: the same
    // x exists on every line, so a tap on line 2 kept answering with whatever
    // line 1 happened to put at that x.
    final TextPosition caret = ro.getPositionForOffset(position);
    final TextRange range = ro.getWordBoundary(caret);
    if (range.isValid && !range.isCollapsed) {
      for (final ({int start, int end, String word}) t in tokens) {
        // Word boundaries and the tokenizer can split differently around
        // apostrophes and hyphens; any overlap with a token is that token.
        if (t.start < range.end && t.end > range.start) {
          onWordTap(t.word);
          return;
        }
      }
    }

    // Tap on whitespace or punctuation (or a boundary that matched no token).
    // Nearest means nearest in BOTH axes, measured to the word's painted
    // rects: a caret-rect test on x alone would still hand line 2's tap to a
    // line-1 word sitting at the same x, and a wrapped word has its end caret
    // to the LEFT of its start caret, which no start→end x band can contain.
    ({int start, int end, String word}) best = tokens.first;
    double bestDist = double.infinity;
    for (final ({int start, int end, String word}) t in tokens) {
      double wordDist = double.infinity;
      final List<TextBox> boxes = ro.getBoxesForSelection(
        TextSelection(baseOffset: t.start, extentOffset: t.end),
      );
      for (final TextBox box in boxes) {
        final double dx = position.dx < box.left
            ? box.left - position.dx
            : position.dx > box.right
                ? position.dx - box.right
                : 0.0;
        final double dy = position.dy < box.top
            ? box.top - position.dy
            : position.dy > box.bottom
                ? position.dy - box.bottom
                : 0.0;
        // Squared distance: the comparison never needs the root.
        final double d = dx * dx + dy * dy;
        if (d < wordDist) wordDist = d;
      }
      if (wordDist < bestDist) {
        bestDist = wordDist;
        best = t;
      }
    }
    onWordTap(best.word);
  }
}

/// The title, with its words tappable for meaning.
///
/// A title is short and wraps little, so a Wrap of word runs is enough —
/// unlike the body, there is no multi-line hit-test to get wrong. Punctuation
/// and spaces are not targets. Same one-level lookup as every other word.
class _TappableTitle extends StatelessWidget {
  const _TappableTitle({
    required this.text,
    required this.style,
    required this.onWordTap,
  });

  final String text;
  final TextStyle style;
  final void Function(String word) onWordTap;

  static final RegExp _word = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int at = 0;
    for (final Match m in _word.allMatches(text)) {
      if (m.start > at) {
        spans.add(TextSpan(text: text.substring(at, m.start)));
      }
      final String w = m.group(0)!;
      spans.add(WidgetSpan(
        baseline: TextBaseline.alphabetic,
        style: style,
        child: GestureDetector(
          onTap: () => onWordTap(w),
          child: Text(w, style: style),
        ),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }
}
