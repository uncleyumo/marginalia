// The queue card.
//
// DESIGN: "A state the user cannot see at a glance is a state the user will
// trust wrongly." So the two slot states are told apart by FOUR signals at once —
// border style, dot style, the verb on the button, and a line of words — and
// never by colour alone. A reader who cannot distinguish red from green still
// knows which card costs money, because one says `planned · not written yet`
// and the other offers `Read`.
//
// The cost line sits on the card that would spend, and nowhere else. That is
// the whole cost ceiling made visible.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart';
import '../../domain/library.dart';
import '../../domain/models.dart';
import '../../domain/queue.dart';

/// One slot. [onWrite] is only ever wired on a planned card, and [onReroll] only
/// on a planned card too — neither exists on a ready one, because neither is
/// meaningful there.
class QueueCard extends StatelessWidget {
  const QueueCard({
    super.key,
    required this.slot,
    required this.onOpen,
    required this.onMenu,
    this.onWrite,
    this.onReroll,
    this.writing = false,
    this.research = false,
    this.isSample = false,
  });

  final QueueSlot slot;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final VoidCallback? onWrite;
  final VoidCallback? onReroll;
  final bool writing;

  /// Whether the writer may look something up before it writes.
  ///
  /// This is the ONLY reason the cost line on this card can differ, and it is
  /// passed in rather than read from a global because a price on screen has to
  /// be the price this particular tap will be charged.
  final bool research;

  /// Bundled sample, not something the writer produced.
  ///
  /// Without this the card is indistinguishable from a generated one, and a
  /// reader reasonably concludes the writer keeps producing the same article.
  /// The tag is a fact about where the text came from, not a grade.
  final bool isSample;

  CostKind get _cost =>
      research ? CostKind.researchedArticle : CostKind.oneArticle;

  @override
  Widget build(BuildContext context) {
    return slot.isPlanned ? _planned(context) : _ready(context);
  }

  // ── planned: a dashed card that says so in words ──────────────────────
  Widget _planned(BuildContext context) {
    final Palette c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.verm.withValues(alpha: 0.42), width: 1.4),
      ),
      padding: const EdgeInsets.all(Gap.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Dot(color: c.verm, filled: false, dashed: true),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The reader's own sentence, or the word `Anything`.
                    //
                    // An instruction is a sentence and can be long, so this is
                    // capped at two lines: a card is a glance, and a card whose
                    // title pushes the Write it button off the screen has
                    // stopped being one. The full text is in the ⋯ menu, which
                    // is where it is edited.
                    Text(
                      slot.subjectLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.015,
                        color: slot.isFreePick ? c.ink3 : c.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      slot.subjectNote,
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 11.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              _menu(context),
            ],
          ),
          const SizedBox(height: 12),
          // The words, not a colour: this card has cost nothing.
          //
          // While a write is in flight the line says the opposite, because by
          // then it is no longer true — the call has gone out and the money is
          // committed. DESIGN's rule is that a price on screen must be the real
          // one, and that applies to this sentence as much as to the number on
          // the button.
          //
          // Wrapped, not a Row with one Text. On a 1080px screen at 480dpi the
          // card is about 300dp wide, and this line is 47 characters of mono —
          // it did not fit and threw a RenderFlex overflow by 87px. The words
          // matter more than the single line they were written on.
          Text(
            writing
                ? 'writing · the call is in flight · it has been paid for'
                : 'planned · not written yet · nothing has been paid for',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 10,
              height: 1.5,
              letterSpacing: 0.02,
              color: c.verm,
            ),
          ),
          // What the card is GOING to be. Without this the reader picks a
          // length from the ⋯ menu, taps Use this, and the card looks exactly
          // as it did before — the choice went into the database and nowhere
          // they can see it.
          //
          // The band's name AND the number, because they are two facts: two
          // bands can share a length, and a reader who typed a custom 300 did
          // not ask for `medium`.
          if (!writing) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              slot.lengthLabel,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10,
                height: 1.5,
                letterSpacing: 0.02,
                color: c.ink3,
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  label: writing ? 'Writing…' : _cost.buttonLabel,
                  icon: writing ? null : '✦',
                  // Dense, because this is the SECOND card-sized block on the
                  // page and at full height it read as a button the size of the
                  // card above it.
                  dense: true,
                  busy: writing,
                  onPressed: writing ? null : onWrite,
                ),
              ),
              const SizedBox(width: Gap.xs),
              // Reroll is free and needs no input: the plan sheet forces a
              // decision and this does not, and the difference between "I must
              // choose" and "show me another" is the difference between a chore
              // and a queue you keep.
              //
              // Closed while a write is in flight, because it replaces the very
              // plan that call is using — the article would arrive for a topic
              // the card no longer shows.
              _FlatBtn(
                label: '↻',
                tooltip: writing
                    ? 'a write is in flight'
                    : 'a different plan · free',
                onTap: writing ? null : onReroll,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ready: the article exists, so the button is an invitation ─────────
  Widget _ready(BuildContext context) {
    final Palette c = context.colors;
    final Article a = slot.article!;
    // Same bottom margin the planned card carries. Without it a ready card
    // sits flush against the next one and the queue reads as one slab rather
    // than three cards.
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: Card0(
        onTap: onOpen,
        padding: const EdgeInsets.all(Gap.cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Dot(color: c.jade, filled: true),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        a.title,
                        style: TextStyle(
                          fontFamily: TypeScale.serif,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // What the article is about, in the writer's own words.
                      //
                      // This is the line that replaced the topic, and it is the
                      // reason the topic could go: three or four words the writer
                      // produced say more than one label the reader had to choose
                      // in advance, and they cost nobody any maintenance. Mono,
                      // because they are data rather than prose.
                      Row(
                        children: <Widget>[
                          if (isSample) ...<Widget>[
                            Text(
                              'SAMPLE',
                              style: TextStyle(
                                fontFamily: TypeScale.mono,
                                fontSize: 10,
                                letterSpacing: 0.12,
                                color: c.verm,
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Expanded(
                            child: Text(
                              a.keywords.isEmpty
                                  ? 'no keywords'
                                  : a.keywords.join(' · '),
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
                    ],
                  ),
                ),
                _menu(context),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              // The difficulty rides on the meta line rather than getting a
              // badge of its own. It is a fact about the text, in the same class
              // as its length and its reading time — and this card already
              // spends its one accent on the jade "ready" dot. A second colour
              // here would be the second emphasis the design forbids.
              <String>[
                '${a.wordCount} words',
                '${a.minuteEstimate} min read',
                if (a.difficulty != null) a.difficulty!.label,
              ].join(' · '),
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
            const SizedBox(height: 11),
            // A `ready` card whose text is not on this phone gets no Read button.
            //
            // Two ways to arrive here, and both are real: the reader freed the
            // bytes from the library, or the article was written by a version
            // that kept bodies in memory only. Either way the old card offered
            // `Read` and opened onto an empty page, which is the app lying about
            // a state it knows is empty. The ⋯ menu is where the way out is —
            // `Done with it` (free, archives it, plans a replacement) or
            // `Write it again`.
            if (a.sentences.isEmpty)
              Text(
                'the text is no longer on this phone · ⋯ to replace it',
                style: TextStyle(
                  fontFamily: TypeScale.mono,
                  fontSize: 10,
                  height: 1.5,
                  letterSpacing: 0.02,
                  color: c.ink3,
                ),
              )
            else
              Btn(
                label: 'Read',
                icon: '▸',
                onPressed: onOpen,
              ),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onMenu,
          customBorder: const CircleBorder(),
          child: Center(
            child: Text(
              '⋯',
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 17,
                color: context.colors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A state dot that is told apart by SHAPE as well as colour.
///
/// filled+round = ready. hollow+dashed = planned. A reader who cannot separate
/// the two hues still gets the right answer from the outline.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.filled, this.dashed = false});

  final Color color;
  final bool filled;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return CustomPaint(
      size: const Size(9, 9),
      painter: _RingPainter(color: color, dashed: dashed),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 1;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    if (!dashed) {
      canvas.drawCircle(centre, radius, paint);
      return;
    }
    // Four arcs. A dashed ring reads as "not yet" at 9 pixels in a way a hollow
    // one does not, and it survives a greyscale screenshot.
    const int segments = 4;
    const double gap = 0.42;
    final Rect rect = Rect.fromCircle(center: centre, radius: radius);
    for (int i = 0; i < segments; i++) {
      final double start = i * (2 * 3.14159265 / segments) + gap / 2;
      canvas.drawArc(rect, start, (2 * 3.14159265 / segments) - gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// A small square button, for the one action on a card that is not the main one.
class _FlatBtn extends StatelessWidget {
  const _FlatBtn({required this.label, required this.tooltip, this.onTap});

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.paperSunk,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.hair),
            ),
            width: 46,
            height: 48,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 16,
                  color: onTap == null ? c.ink3 : c.ink2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The storage line, shown once above the cards.
class StorageLine extends StatelessWidget {
  const StorageLine({
    super.key,
    required this.usedKb,
    required this.freedKb,
    required this.goneCount,
  });

  final int usedKb;
  final int freedKb;
  final int goneCount;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final double fraction =
        (usedKb / kStorageBudgetKb).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HatchedBar(
          fraction: fraction,
          color: c.verm,
          height: 5,
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Text(
              '${formatKb(usedKb)} of ${formatKb(kStorageBudgetKb)}',
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
            const Spacer(),
            if (freedKb > 0)
              Text(
                '$goneCount deleted · ${formatKb(freedKb)} freed · '
                'their read counts are still counted',
                style: TextStyle(
                  fontFamily: TypeScale.mono,
                  fontSize: 10.5,
                  color: c.ink3,
                ),
              ),
          ],
        ),
      ],
    );
  }
}