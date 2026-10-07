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
  });

  final Article article;
  final SentencePlayer player;
  final VoidCallback onCountListen;

  /// The header label is a button, so it needs somewhere to go.
  final VoidCallback onBack;

  /// Whether this article has a recorded voice at all.
  final bool hasAudio;

  final int listened;

  final ListenSize size;
  final ValueChanged<ListenSize>? onSize;

  /// Which engine is speaking, stated in words rather than implied.
  final String voiceLabel;

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
    unawaited(_playCurrent());
  }

  @override
  void dispose() {
    // Bump the generation first: a `_playFrom` further down the stack may still
    // be awaiting the engine, and it must not setState after this State is gone.
    _generation++;
    unawaited(widget.player.stop());
    super.dispose();
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
    while (generation == _generation && mounted) {
      if (_index >= widget.article.sentences.length) {
        setState(() => _playing = false);
        return;
      }
      setState(() => _playing = true);
      await widget.player.play(_index, widget.article.sentences[_index].english);
      if (generation != _generation || !mounted) return;
      if (_index < widget.article.sentences.length - 1) {
        setState(() => _index++);
      } else {
        setState(() => _playing = false);
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
      return;
    }
    // Resuming speaks this sentence again from its start, because no engine on
    // every platform can continue mid-word. Said on screen rather than hidden.
    setState(() => _playing = true);
    await widget.player.resume();
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

  void _resize(ListenSize next) {
    final ValueChanged<ListenSize>? cb = widget.onSize;
    if (cb != null) {
      cb(next);
    } else {
      setState(() {});
    }
  }

  ListenSize get _size => widget.onSize == null ? widget.size : widget.size;

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
                  child: Text(
                    widget.article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    // pocket rather than for reading at arm's length
                    Text(
                      _current.english,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: _size.px,
                        height: 1.4,
                        letterSpacing: -0.02,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // The translation is available but not shown by default, so
                    // listening is not the same as reading with the answer up.
                    _ChineseReveal(text: _current.chinese, color: c),
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

class _ChineseReveal extends StatefulWidget {
  const _ChineseReveal({required this.text, required this.color});

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
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 15,
            height: 1.7,
            color: c.ink2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'hide',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 11,
            color: c.ink3,
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