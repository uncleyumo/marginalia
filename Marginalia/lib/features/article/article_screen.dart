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
    this.counted = false,
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

  /// Already counted today. The button re-arms either way: reading twice is
  /// normal, and an article the reader returns to is the whole point.
  final bool counted;

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
          Text(
            widget.article.title,
            // The article title is the one thing on this screen that should feel
            // like a title. `texts.titleLarge` is nullable because it comes off a
            // TextTheme, so the size is read defensively rather than with `!` at
            // three call sites.
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: (context.texts.titleLarge?.fontSize ?? 21) + 3,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.02,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.article.focus.isEmpty
                ? widget.article.topic
                : '${widget.article.topic} · ${widget.article.focus}',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 12,
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
          '${widget.article.wordCount} words · ${widget.article.minuteEstimate} min',
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

  /// The only button on this screen. It counts; it does not finish.
  ///
  /// DESIGN: "You read it. Count it? — it stays in your queue afterwards."
  /// That "afterwards" is the invariant. There is no variant of this screen
  /// where reading removes anything.
  Widget _countButton(BuildContext context, Palette c) {
    return Column(
      children: <Widget>[
        Text(
          widget.counted
              ? 'counted. read it again and it will count again.'
              : 'finished reading?',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 9),
        Btn(
          label: widget.counted ? 'Count it again' : 'Count this read',
          primary: false,
          onPressed: widget.onCountRead,
        ),
        const SizedBox(height: 11),
        Text(
          'it stays in your queue. reading never removes anything.',
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
    final Widget line = _TappableSentence(
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
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 14.5,
            height: 1.7,
            color: c.ink2,
          ),
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
/// Hit-testing goes through [TextPainter] rather than a per-span recogniser,
/// because a recogniser per word loses the punctuation spacing — the tap area
/// has to include the space after the word, or half of every tap misses.
class _TappableSentence extends StatelessWidget {
  const _TappableSentence({
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
    final Map<String, MarkTier> tiers = <String, MarkTier>{
      for (final Mark m in marks) m.surface.toLowerCase(): m.tier,
    };

    final List<TextSpan> spans = <TextSpan>[];
    int cursor = 0;
    for (final ({int start, int end, String word}) t in _tokens()) {
      if (t.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, t.start)));
      }
      final MarkTier? tier = tiers[t.word.toLowerCase()];
      spans.add(TextSpan(
        text: t.word,
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: sizePx,
          height: 1.86,
          color: switch (tier) {
            MarkTier.unfamiliar => c.vermInk,
            MarkTier.difficult => c.jade,
            null => baseColor,
          },
          decoration: tier == null ? TextDecoration.none : TextDecoration.underline,
          decorationColor: tier == MarkTier.unfamiliar ? c.verm : c.jade,
          decorationThickness: 1.6,
        ),
      ));
      cursor = t.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) =>
              _resolve(d.localPosition, constraints.maxWidth),
          // Long press is how a LINE is heard. A tap is a question about a word;
          // a press-and-hold is a question about the sentence around it, and the
          // two never compete for the same gesture.
          onLongPress: onLongPress,
          child: Text.rich(
            TextSpan(style: TextStyle(color: baseColor), children: spans),
          ),
        );
      },
    );
  }

  /// Which word was tapped, by asking a painter for the offset of each one.
  ///
  /// A miss still reports the nearest word rather than nothing: the reader
  /// pointed at the text, and answering with an empty card would read as the app
  /// being broken.
  void _resolve(Offset position, double width) {
    final List<({int start, int end, String word})> tokens = _tokens();
    if (tokens.isEmpty) return;

    // Build a painter with the same metrics this widget uses, then ask it where
    // each word sits. A width of zero means the layout has not happened yet;
    // fall back to the first word rather than crashing.
    final TextPainter painter = TextPainter(
      text: TextSpan(
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: sizePx,
          height: 1.86,
        ),
        children: <InlineSpan>[
          for (final ({int start, int end, String word}) t in tokens)
            TextSpan(text: '${t.word} '),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
    )..layout(maxWidth: width > 0 ? width : 400.0);

    ({int start, int end, String word}) best = tokens.first;
    double bestDx = double.infinity;
    for (final ({int start, int end, String word}) t in tokens) {
      final Offset dx = painter.getOffsetForCaret(
        TextPosition(offset: t.start),
        Rect.zero,
      );
      final Offset endDx = painter.getOffsetForCaret(
        TextPosition(offset: t.end),
        Rect.zero,
      );
      // the tap band runs from the word's start to the space after it
      if (position.dx >= dx.dx - 3 && position.dx <= endDx.dx + 4) {
        painter.dispose();
        onWordTap(t.word);
        return;
      }
      if ((position.dx - dx.dx).abs() < bestDx) {
        bestDx = (position.dx - dx.dx).abs();
        best = t;
      }
    }
    painter.dispose();
    onWordTap(best.word);
  }
}