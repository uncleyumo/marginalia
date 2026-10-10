// Listening.
//
// This is use case #2 and it is not a smaller version of reading — a commuter
// with the screen in their pocket cannot look at a paragraph. So the Listen view
// shows ONE sentence at a time, very large, with the controls underneath and
// nothing else competing for attention.
//
// Two facts about audio that the interface is honest about:
//
//  - With no recorded voice the article has NO pre-built audio. The app does not
//    pretend otherwise: it falls back to the device engine per sentence, which
//    is slower and flatter but always available, free and offline.
//  - Playing counts as a LISTEN and never as a read. Conflating them would put a
//    number on the shelf that the reader did not earn by reading, and they would
//    have no way to tell.
//
// Two things were wrong here and both are fixed rather than restyled:
//
//  - `player.play(index)` had no text argument, and the player read the sentence
//    from a field the view never set. Every sentence on this screen was handed
//    to the engine as an empty string: silence, behind a play button that looked
//    alive. The text is now an argument.
//  - The transport used typographic characters (⏮ ❚❚ ▶ ⏭), which render as
//    emoji boxes on Android — orange squares, not controls. They are Material
//    icons now, which are drawn by the platform and look the same everywhere.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../data/handler.dart';
import '../../domain/models.dart';

// The contract lives with the audio layer, not here. A screen that declared its
// own copy of `SentencePlayer` and `VoiceSource` produced two enums with the same
// name in the same program, and every call site became ambiguous.
import '../../data/audio.dart';

/// The sizes the sentence can be set to. A line held at arm's length on a phone
/// needs three or four stops between "too small to read on a train" and "one word
/// per line", and a fixed 26px served neither.
enum ListenSize {
  medium(24.0, 'Medium'),
  large(30.0, 'Large'),
  huge(38.0, 'Huge');

  const ListenSize(this.px, this.label);

  final double px;
  final String label;

  ListenSize get smaller =>
      index == 0 ? this : ListenSize.values[index - 1];

  ListenSize get larger => index == ListenSize.values.length - 1
      ? this
      : ListenSize.values[index + 1];
}

class ListenScreen extends StatefulWidget {
  const ListenScreen({
    super.key,
    required this.article,
    required this.player,
    required this.onCountListen,
    required this.onBack,
    this.hasAudio = false,
    this.listened = 0,
    this.size = ListenSize.large,
    this.onSize,
    this.voiceLabel = '',
    this.audioHandler,
    this.autoPlay = false,
    this.active = true,
    this.onWordTap,
    this.onFinished,
    this.onNextArticle,
  });

  final Article article;
  final SentencePlayer player;
  final VoidCallback onCountListen;

  /// The lock screen and the media notification. Null when the platform refused
  /// to start the foreground service — the tab still works in the foreground,
  /// and this screen simply has nothing to publish to.
  final MarginaliaAudioHandler? audioHandler;

  /// The header label is a button, so it needs somewhere to go.
  final VoidCallback onBack;

  /// Whether this article has a recorded voice at all.
  final bool hasAudio;

  final int listened;

  final ListenSize size;
  final ValueChanged<ListenSize>? onSize;

  /// Which engine is speaking, stated in words rather than implied.
  final String voiceLabel;

  /// Whether opening this screen starts speaking.
  ///
  /// Default OFF, and that is deliberate: a screen that starts talking the
  /// moment it is opened surprises people in quiet rooms, and "surprised" is
  /// the opposite of what a Listen tab is for. Combined with [active], it
  /// means "when I switch to Listen, start" — not "when this widget happens
  /// to be built underneath an IndexedStack".
  final bool autoPlay;

  /// Whether this screen is the one the reader is looking at.
  ///
  /// The Read/Listen switch keeps both children alive so the sentence index
  /// survives a glance at Read. Auto-play must still only fire when Listen is
  /// the tab in front, and only the first time.
  final bool active;

  /// Word meaning, same contract as the Read screen — including the fact that
  /// a lookup is one tap deep and stops there.
  final ValueChanged<String>? onWordTap;

  /// The article played to its last sentence. Fires once per completed pass;
  /// the caller is what decides whether that is a listen to count.
  final VoidCallback? onFinished;

  /// Skip to the next article in the auto-continue chain (or the queue).
  /// Null when there is nothing to go to, and the control is then not drawn.
  final VoidCallback? onNextArticle;

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  int _index = 0;
  bool _playing = false;
  bool _busy = false;
  int _generation = 0;

  Sentence get _current => widget.article.sentences[_index];

  @override
  void initState() {
    super.initState();
    _attachTransport();
    // Only when the reader asked for it AND this screen is already in front.
    // A parent that keeps this widget alive under an IndexedStack must not
    // make the article start speaking from underneath the Read tab.
    if (widget.autoPlay && widget.active) {
      _autoStarted = true;
      unawaited(_playCurrent());
    }
  }

  /// One auto-start per screen. Flipping Read↔Listen must not replay the
  /// article from the top every time — that was the "it talks at me" complaint.
  bool _autoStarted = false;

  @override
  void didUpdateWidget(ListenScreen old) {
    super.didUpdateWidget(old);
    if (widget.autoPlay && widget.active && !_autoStarted && !_playing) {
      _autoStarted = true;
      unawaited(_playCurrent());
    }
  }

  @override
  void dispose() {
    // Bump the generation first: a `_playFrom` further down the stack may still
    // be awaiting the engine, and it must not setState after this State is gone.
    _generation++;
    // Hand the transport back BEFORE the State goes away, so a lock-screen tap
    // arriving a moment later finds nobody home instead of calling into a
    // disposed State.
    widget.audioHandler?.detach();
    unawaited(widget.player.stop());
    super.dispose();
  }

  /// Let the lock screen, the media notification and the headset buttons drive
  /// this screen. DESIGN's use case #2 is a commuter with the phone in a pocket,
  /// and a transport that only exists inside the app does not serve it.
  void _attachTransport() {
    final MarginaliaAudioHandler? h = widget.audioHandler;
    if (h == null) return;
    h.onPlay = () {
      if (!_playing) unawaited(_toggle());
    };
    h.onPause = () {
      if (_playing) unawaited(_toggle());
    };
    h.onNext = () => unawaited(_jump(1));
    h.onPrevious = () => unawaited(_jump(-1));
    _publish();
  }

  /// State what is being heard, so the lock screen is never a guess.
  void _publish() {
    final MarginaliaAudioHandler? h = widget.audioHandler;
    if (h == null) return;
    if (_index < 0 || _index >= widget.article.sentences.length) return;
    h.publish(
      articleTitle: widget.article.title,
      sentence: _current.english,
      index: _index,
      total: widget.article.sentences.length,
      playing: _playing,
    );
  }

  /// Play [index] and roll into the next one, unless the reader has interrupted.
  ///
  /// The generation counter is what makes the auto-advance stoppable. Without it
  /// a jump or a pause left the old chain running, so the app kept speaking a
  /// sentence the reader had already navigated away from — and setState fired on
  /// a disposed State, which is the crash behind the red screen a screenshot
  /// showed.
  Future<void> _playFrom(int index, int generation) async {
    setState(() => _index = index);
    _publish();
    while (generation == _generation && mounted) {
      if (_index >= widget.article.sentences.length) {
        setState(() => _playing = false);
        _publish();
        // A completed pass, not a completed sentence. One `onFinished` per
        // play-through: the caller decides whether that is a listen to count,
        // and an interruption (pause, jump, dispose) never reaches here.
        widget.onFinished?.call();
        return;
      }
      setState(() => _playing = true);
      _publish();
      await widget.player.play(_index, widget.article.sentences[_index].english);
      if (generation != _generation || !mounted) return;
      if (_index < widget.article.sentences.length - 1) {
        setState(() => _index++);
        _publish();
      } else {
        setState(() => _playing = false);
        _publish();
        widget.onFinished?.call();
        return;
      }
    }
  }

  Future<void> _playCurrent() async {
    if (_busy) return;
    _busy = true;
    try {
      await _playFrom(_index, _generation);
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      _generation++;
      await widget.player.pause();
      if (mounted) setState(() => _playing = false);
      _publish();
      return;
    }
    // Resuming speaks this sentence again from its start, because no engine on
    // every platform can continue mid-word. Said on screen rather than hidden.
    //
    // It goes through _playCurrent and deliberately NOT through
    // `player.resume()`. Once the article had finished, the player had already
    // been stopped and its current text cleared, so `resume()` returned on its
    // first line: the button flipped to a pause icon, the ticks sat still, and
    // no sound came out. Restarting the sentence is both what the screen
    // promises and the only thing that actually plays.
    _generation++;
    await _playCurrent();
  }

  Future<void> _jump(int delta) async {
    final int next =
        (_index + delta).clamp(0, widget.article.sentences.length - 1);
    if (next == _index) return;
    _generation++;
    await widget.player.stop();
    if (!mounted) return;
    unawaited(_playFrom(next, _generation));
  }

  /// Start this article again from sentence one, and speak it.
  ///
  /// Distinct from `_jump` back to zero only in that it always speaks: a
  /// reader who reaches for "from the beginning" wants to hear it, not to sit
  /// on sentence 1 with the play button still meaning "resume here".
  Future<void> _restart() async {
    _generation++;
    await widget.player.stop();
    if (!mounted) return;
    unawaited(_playFrom(0, _generation));
  }

  void _resize(ListenSize next) {
    final ValueChanged<ListenSize>? cb = widget.onSize;
    if (cb != null) {
      cb(next);
    } else {
      setState(() {});
    }
  }

  /// The size the sentence is drawn at. The parent owns it when it hands down an
  /// `onSize`; otherwise this screen is the owner and [ListenSize.large] is the
  /// starting point. The ternary that used to be here returned `widget.size` on
  /// both branches, which is a decision that reads as one and is not.
  ListenSize get _size => widget.size;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final int total = widget.article.sentences.length;

    return PageScaffold(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 4, Gap.gutter, 0),
            child: Row(
              children: <Widget>[
                BackLabel(label: '‹ Queue', onTap: widget.onBack),
                const Spacer(),
                // No percentage and no "3 / 11". DESIGN: "no bar, no estimate,
                // no progress. Those would make a reader feel behind."
                Flexible(
                  child: _TappableWords(
                    text: widget.article.title,
                    align: TextAlign.right,
                    onWordTap: widget.onWordTap,
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10.5,
                      color: c.ink3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The Chinese title, when the writer produced one. A title is the
          // first thing a reader meets and often the hardest words in the
          // piece; the translation answers that before the first sentence.
          if (widget.article.titleCn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, 2, Gap.gutter, 0),
              child: Text(
                widget.article.titleCn,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 12,
                  color: c.ink3,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.gutter, vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // one sentence, large, centred — built for a glance from a
                    // pocket rather than for reading at arm's length.
                    // Words are tappable, with the same lookup as Read.
                    _TappableWords(
                      text: _current.english,
                      align: TextAlign.center,
                      onWordTap: widget.onWordTap,
                      style: context.readingFace
                          .style(c.ink, _size.px, height: 1.4)
                          .copyWith(letterSpacing: -0.02),
                    ),
                    const SizedBox(height: 20),
                    // The translation is available but not shown by default, so
                    // listening is not the same as reading with the answer up.
                    _ChineseReveal(
                      text: _current.chinese,
                      color: c,
                      key: ValueKey<String>('${widget.article.id}/$_index'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _controls(context, c, total),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, Palette c, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 12, Gap.gutter, 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hair)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            // an honest statement about which voice is speaking
            Text(
              widget.voiceLabel.isEmpty
                  ? (widget.hasAudio
                      ? 'a recorded voice · offline after the first build'
                      : "the phone's own voice · free · offline · airplane mode")
                  : widget.voiceLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 11,
                color: c.ink3,
              ),
            ),
            const SizedBox(height: 12),
            // The size control sits ABOVE the transport, not inside it: it is a
            // setting for the sentence, and the transport is for the machine.
            _sizeRow(context, c),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Round(
                  icon: Icons.skip_previous,
                  tip: 'Previous sentence',
                  size: 46,
                  onTap: () => _jump(-1),
                ),
                const SizedBox(width: 16),
                _Round(
                  icon: _playing ? Icons.pause : Icons.play_arrow,
                  tip: _playing ? 'Pause' : 'Play',
                  size: 68,
                  primary: true,
                  onTap: _toggle,
                ),
                const SizedBox(width: 16),
                _Round(
                  icon: Icons.skip_next,
                  tip: 'Next sentence',
                  size: 46,
                  onTap: () => _jump(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Article-level transport. Sentences above, the piece as a whole
            // here: "again from the start" and "the next article" are the two
            // things a commuter asks for once a piece ends, and neither is a
            // sentence jump.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Round(
                  icon: Icons.replay,
                  tip: 'From the beginning',
                  size: 42,
                  onTap: _restart,
                ),
                if (widget.onNextArticle != null) ...<Widget>[
                  const SizedBox(width: 14),
                  _Round(
                    icon: Icons.playlist_play,
                    tip: 'Next article',
                    size: 42,
                    onTap: widget.onNextArticle!,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // A row of ticks, not a progress bar: it shows where you are without
            // implying you are behind. It is not tappable — it is a position,
            // not a target.
            _Ticks(total: total, index: _index, color: c),
            const SizedBox(height: 11),
            Text(
              widget.listened > 0
                  ? 'heard ${widget.listened}× · listening is not reading'
                  : 'listening is not reading — this never counts as a read',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: c.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeRow(BuildContext context, Palette c) {
    final bool canGrow = _size != ListenSize.huge;
    final bool canShrink = _size != ListenSize.medium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        MiniBtn(
          icon: Icons.text_decrease,
          tip: 'Smaller',
          size: 34,
          onTap: canShrink ? () => _resize(_size.smaller) : null,
        ),
        SizedBox(
          width: 74,
          child: Center(
            child: Text(
              _size.label,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
          ),
        ),
        MiniBtn(
          icon: Icons.text_increase,
          tip: 'Larger',
          size: 34,
          onTap: canGrow ? () => _resize(_size.larger) : null,
        ),
      ],
    );
  }
}

/// Words the reader can tap for meaning.
///
/// The Listen screen shows one sentence at a time, so a `Wrap` of word runs is
/// enough: there is no multi-line hit-test to get wrong, and each word is its
/// own target. Punctuation and spaces are not targets. Same lookup as the Read
/// screen, one level deep, by wiring `onWordTap` to the same sheet.
class _TappableWords extends StatelessWidget {
  const _TappableWords({
    required this.text,
    required this.style,
    required this.align,
    this.onWordTap,
  });

  final String text;
  final TextStyle style;
  final TextAlign align;
  final ValueChanged<String>? onWordTap;

  static final RegExp _word = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  @override
  Widget build(BuildContext context) {
    final ValueChanged<String>? tap = onWordTap;
    if (tap == null) {
      return Text(text, textAlign: align, style: style);
    }
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
          onTap: () => tap(w),
          child: Text(w, style: style),
        ),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return RichText(
      textAlign: align,
      text: TextSpan(style: style, children: spans),
    );
  }
}

class _ChineseReveal extends StatefulWidget {
  const _ChineseReveal({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Palette color;

  @override
  State<_ChineseReveal> createState() => _ChineseRevealState();
}

class _ChineseRevealState extends State<_ChineseReveal> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final Palette c = widget.color;
    if (!_open) {
      return TextButton(
        onPressed: () => setState(() => _open = true),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Chinese translation',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: c.ink3,
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        Text(
          widget.text,
          textAlign: TextAlign.center,
          style: context.readingFace.style(c.ink2, 15, height: 1.7),
        ),
        const SizedBox(height: 6),
        // The close has to be a real control. It used to be a bare `Text` with
        // the word "hide" on it, which looked like a button and did nothing —
        // the one way to stop seeing the translation was to leave the screen.
        TextButton(
          onPressed: () => setState(() => _open = false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'hide',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11,
              color: c.ink3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Where you are, without a percentage.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.total, required this.index, required this.color});

  final int total;
  final int index;
  final Palette color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < total; i++)
            Container(
              width: 3,
              height: i == index ? 12 : 5,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: i <= index ? color.verm : color.hair,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// One transport control. Material icons, an outlined circle, and a filled
/// vermilion one for the thing the screen is waiting for.
class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.tip,
    required this.size,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String tip;
  final double size;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Tooltip(
      message: tip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: primary ? c.verm : c.paperSunk,
          shape: CircleBorder(
            side: BorderSide(color: primary ? c.verm : c.hair),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Icon(
              icon,
              size: primary ? size * 0.44 : size * 0.36,
              color: primary ? c.paper : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}