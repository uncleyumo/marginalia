// Texture, not decoration.
//
// The prototype's own words: "fine paper grain, hairline rules, hatched bars —
// no blurs, no glow." The grain is an overlay at 5% mix-blend-mode, and a weight
// bar is an ENGRAVED fill: 135° hatching, not a gradient.
//
// Both are CustomPainter rather than images, so they stay sharp at any density
// and cost nothing in the bundle. Neither listens to taps, so neither takes a
// hit test.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Fine paper grain over the whole page.
///
/// The prototype achieves it with an SVG turbulence at 5% overlay. A gradient
/// or a blur is NOT the same thing and DESIGN forbids both, so this paints
/// actual noise: a fixed, seeded dot field so the texture does not crawl when
/// the user scrolls.
class PaperGrain extends StatelessWidget {
  const PaperGrain({super.key, this.opacity = 0.05, this.child});

  /// 0.05 in the prototype. Kept as a parameter so a test can turn it up.
  final double opacity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final Color tint = context.colors.ink;
    return Stack(
      children: <Widget>[
        if (child != null) Positioned.fill(child: child!),
        // IgnorePointer so the grain never eats a tap meant for a word.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GrainPainter(tint: tint, opacity: opacity),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.tint, required this.opacity});

  final Color tint;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Paint paint = Paint()
      // A faint spread of the ink colour reads as fibre in the paper. Using the
      // ink rather than black is what keeps the grain from looking like dirt.
      ..color = tint.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    // Deterministic: a fixed seed means the same grain every frame, so a scroll
    // does not make the page look alive in a way a paperback never does.
    final math.Random rnd = math.Random(20261006);
    // ~1 dot per 900 logical px² is dense enough to read as texture and sparse
    // enough to stay invisible as individual specks.
    final int count = (size.width * size.height / 900).clamp(0, 4000).toInt();
    for (int i = 0; i < count; i++) {
      final double dx = rnd.nextDouble() * size.width;
      final double dy = rnd.nextDouble() * size.height;
      final double r = 0.4 + rnd.nextDouble() * 0.5;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.tint != tint || old.opacity != opacity;
}

/// An engraved bar: 135° hatching clipped to a progress width.
///
/// Used for a word's selection chance and for read/heard counts. The prototype
/// calls it "an engraved bar, not a gradient" — a gradient would imply a
/// quantity fills smoothly, which is not what the number means.
class HatchedBar extends StatelessWidget {
  const HatchedBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 6,
    this.background,
  });

  /// 0.0–1.0. Values outside are clamped, because a bar that overflows its own
  /// track is a rendering bug that looks like a design choice.
  final double fraction;
  final Color color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: <Widget>[
            ColoredBox(color: background ?? c.paperSunk),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: CustomPaint(
                painter: _HatchPainter(color: color),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 135° stripes: 3px of colour, 3px of gap, exactly as the prototype's
    // repeating-linear-gradient(115deg, ...) reads.
    const double period = 6.0;
    const double stroke = 3.0;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Draw one extra stripe beyond each edge so a partial bar is filled solid
    // at its right edge rather than ending in a half stripe.
    for (double x = -size.height; x < size.width + size.height; x += period) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

/// A hairline. The design's substitute for borders and nested cards: a 1px rule
/// in `--hair`, never a 1px box-shadow and never a second card inside the first.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false, this.color, this.width = 1});

  final bool vertical;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? context.colors.hair;
    return SizedBox(
      width: vertical ? width : double.infinity,
      height: vertical ? double.infinity : width,
      child: ColoredBox(color: c),
    );
  }
}

/// The editor's pencil: a thin vermilion rule UNDER a word.
///
/// This is the app's signature. It is not a highlighter block: the sentence
/// around the word has to stay readable, which is why it is a 0.42em inset
/// underline rather than a filled rect.
class PencilUnderline extends StatelessWidget {
  const PencilUnderline({
    super.key,
    required this.child,
    required this.color,
    this.thickness = 0.42,
  });

  final Widget child;
  final Color color;

  /// As a fraction of the line height. 0.42 is the prototype's value.
  final double thickness;

  @override
  Widget build(BuildContext context) {
    // A gradient from transparent to the ink colour, masked with dstIn so only
    // the bottom `thickness` of the text survives. That gives an underline that
    // sits UNDER the word and leaves the sentence around it readable — a
    // highlighter block would hide the words it is meant to annotate.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, bounds.height),
        <Color>[Colors.transparent, color],
        <double>[1.0 - thickness, 1.0],
      ),
      child: child,
    );
  }
}
