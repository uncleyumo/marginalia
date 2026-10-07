// DESIGN §12 — the design system, declared at the APP level.
//
// Why this file exists and why nothing may hold a colour literal of its own:
// the prototype records the exact bug. A token scoped to one widget's ancestor
// resolves to nothing outside that subtree and renders TRANSPARENT. Every
// bottom sheet before v9 was invisible for that reason — short ones hid it
// because their own content covered the gap, tall scrolling ones did not.
//
// So: two palettes, one definition, resolved from the app's ThemeData. A
// feature file that needs a colour asks for `context.colors.verm`, never
// `Color(0xFFC83122)`.

import 'package:flutter/material.dart';

/// The two surfaces. There is no day/night SWITCH — the day/night distinction
/// was removed, not renamed (invariant 5). This is a one-time appearance
/// choice, living in Settings → The small print, with no time semantics.
///
/// The OKLCH values from the prototype were converted to sRGB because Flutter
/// 3.44 has no OKLCH in its ColorSpace enum (`sRGB`, `extendedSRGB`,
/// `displayP3` only). The conversion script and its reasoning live in
/// `tools/`; the source OKLCH of each value is noted beside it so the two can
/// be reconciled if a future SDK gains OKLCH.
@immutable
class Palette {
  const Palette({
    required this.name,
    required this.paper,
    required this.paperSunk,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hair,
    required this.rule,
    required this.verm,
    required this.vermInk,
    required this.vermWash,
    required this.jade,
    required this.jadeWash,
    required this.lamp,
    required this.lampWash,
    required this.shadow,
  });

  final String name;

  /// Page background. oklch(97.4% .014 84) / oklch(21% .018 66)
  final Color paper;

  /// A recessed well: segmented controls, storage bars. oklch(94.2% .018 82)
  final Color paperSunk;

  /// A raised card or sheet. oklch(99.4% .006 86)
  final Color surface;

  /// Body text. oklch(23% .026 58)
  final Color ink;

  /// Secondary text, definitions. oklch(41% .020 60)
  final Color ink2;

  /// Quiet text: meta lines, hints. oklch(56% .014 66)
  final Color ink3;

  /// The hairline that replaces a card border. oklch(88.5% .014 80)
  final Color hair;

  /// A slightly stronger divider. oklch(84% .016 78)
  final Color rule;

  /// Primary action, a starred word, a new word. oklch(55% .19 30)
  final Color verm;

  /// Vermilion for TEXT on a light wash — vermilion itself fails contrast
  /// there. oklch(45% .17 28)
  final Color vermInk;

  /// The pencil-underline wash behind a marked word. oklch(95.5% .045 34)
  final Color vermWash;

  /// ready / met before / done. oklch(58% .10 168)
  final Color jade;

  final Color jadeWash;

  /// Still writing. oklch(72% .13 70)
  final Color lamp;

  final Color lampWash;

  /// Two-part: a tight contact shadow plus a wide lift.
  final List<BoxShadow> shadow;

  static const warmPaper = Palette(
    name: 'warm paper',
    paper: Color(0xFFFBF6EC),
    paperSunk: Color(0xFFF2EBDF),
    surface: Color(0xFFFFFDF9),
    ink: Color(0xFF261A11),
    ink2: Color(0xFF534840),
    ink3: Color(0xFF7A736C),
    hair: Color(0xFFDED8CF),
    rule: Color(0xFFD0C9BF),
    verm: Color(0xFFC83122),
    vermInk: Color(0xFF9E1614),
    vermWash: Color(0xFFFFE6DD),
    jade: Color(0xFF2E8D6F),
    jadeWash: Color(0xFFD4F6E8),
    lamp: Color(0xFFD8953D),
    lampWash: Color(0xFFFFECC7),
    shadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x12000000),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color(0x381F1208),
        offset: Offset(0, 10),
        blurRadius: 26,
        spreadRadius: -14,
      ),
    ],
  );

  /// The prototype's default: one warm low-glare ink for night and long reads.
  static const warmInk = Palette(
    name: 'warm ink',
    paper: Color(0xFF1E1710),
    paperSunk: Color(0xFF271F16),
    surface: Color(0xFF292119),
    ink: Color(0xFFEFEBE2),
    ink2: Color(0xFFC2BDB4),
    ink3: Color(0xFF9E978F),
    hair: Color(0xFF3B342D),
    rule: Color(0xFF4B433C),
    verm: Color(0xFFFA7F59),
    vermInk: Color(0xFFFFAA86),
    vermWash: Color(0xFF45231A),
    jade: Color(0xFF5BC19D),
    jadeWash: Color(0xFF113227),
    lamp: Color(0xFFF6C16B),
    lampWash: Color(0xFF412B06),
    shadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x73000000),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color(0xB3000000),
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -16,
      ),
    ],
  );
}

/// Type. Three families, and the rule that decides which:
///
///   serif  → anything READ
///   sans   → anything OPERATED
///   mono   → data: IPA, timestamps, keys, counters
///
/// DESIGN §9: in a data view the LABEL is mono and the VALUE is serif, so the
/// eye can tell what KIND of thing this is from what it SAYS, without reading
/// either.
/// Type. Three families, and the rule that decides which:
///
///   serif  → anything READ
///   sans   → anything OPERATED
///   mono   → data: IPA, timestamps, keys, counters
///
/// DESIGN §9: in a data view the LABEL is mono and the VALUE is serif, so the
/// eye can tell what KIND of thing this is from what it SAYS, without reading
/// either.
///
/// These are top-level constants rather than a class: an earlier version had
/// both instance fields and statics of the same names, which is not expressible
/// in Dart and made every call site ambiguous.
abstract final class TypeScale {
  /// Serif for anything read. Optical size axis kept as a variable font.
  static const String serif = 'Newsreader';

  /// Grotesque for anything operated.
  static const String sans = 'SchibstedGrotesk';

  /// Mono for data: IPA, timestamps, API keys, counters.
  static const String mono = 'IBMPlexMono';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

/// The prototype's `--t-*` ladder: a 1.25–1.3 modular scale. The `clamp()`
/// display sizes become screen-width aware on the Dart side, which is why
/// [display] and [hero] are functions rather than constants.
abstract final class AppType {
  static const double twoXs = 10;
  static const double xs = 11;
  static const double sm = 13;
  static const double base = 15;
  static const double md = 17;

  static double lg(double width) => _clamp(width, 18, 22);
  static double xl(double width) => _clamp(width, 24, 32);
  static double hero(double width) => _clamp(width, 32, 45);

  /// The prototype clamps against viewport width between roughly 360 and 1280.
  static double _clamp(double width, double min, double max) {
    final double t = ((width - 360) / (1280 - 360)).clamp(0.0, 1.0);
    return min + (max - min) * t;
  }
}

/// Spacing. The prototype's page gutter is 18, cards pad 15–16 and sit 10–12
/// apart, blocks are separated by 22. These are the only numbers a feature may
/// reach for.
abstract final class Gap {
  static const double hair = 4;
  static const double xs = 8;
  static const double sm = 10;
  static const double gutter = 18;
  static const double cardPad = 16;
  static const double block = 22;
  static const double sheetPad = 20;
}

/// Corner radii: a card is 16–18, a big card 20–22, a sheet's top 24 with no
/// radius below.
abstract final class Radii {
  static const double input = 12;
  static const double card = 16;
  static const double bigCard = 20;
  static const double sheet = 24;
  static const BorderRadius chip = BorderRadius.all(Radius.circular(999));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius bigCardAll =
      BorderRadius.all(Radius.circular(bigCard));
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Motion: 120 / 300 / 500 ms on cubic-bezier(.16,1,.3,1) — the "expo out"
/// curve, which is what makes a sheet feel like it was already moving before
/// it arrived.
///
/// Flutter exposes no cubic-bezier directly, so the curve is approximated with
/// a [Cubic] built from the control points. `.16, 1, .3, 1` is
/// `Cubic(0.16, 1.0, 0.3, 1.0)` in this constructor's terms.
abstract final class Ease {
  static const Cubic outExpo = Cubic(0.16, 1.0, 0.3, 1.0);

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration mid = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  /// The prototype honours `prefers-reduced-motion` globally. Flutter exposes
  /// this through `MediaQuery.disableAnimationsOf(context)`, so anything that
  /// animates must check it — see `lib/core/util/motion.dart`.
}

/// Where a colour, type or metric is read from the ambient Theme. Extension
/// methods keep call sites short without introducing a second source of truth:
/// `context.colors.verm` and `Theme.of(context).extension<MarginaliaTheme>()`
/// cannot disagree.
extension ThemeContext on BuildContext {
  Palette get colors =>
      Theme.of(this).extension<MarginaliaTheme>()?.palette ?? Palette.warmInk;

  TextTheme get texts => Theme.of(this).textTheme;
}

/// Registered once by `MaterialApp.theme`.
@immutable
class MarginaliaTheme extends ThemeExtension<MarginaliaTheme> {
  const MarginaliaTheme({required this.palette});

  final Palette palette;

  @override
  MarginaliaTheme copyWith({Palette? palette}) =>
      MarginaliaTheme(palette: palette ?? this.palette);

  @override
  MarginaliaTheme lerp(ThemeExtension<MarginaliaTheme>? other, double t) {
    if (other is! MarginaliaTheme) return this;
    // Palettes are not interpolated: a cross-fade between two warm surfaces
    // would pass through mud. The appearance choice snaps.
    return t < 0.5 ? this : other;
  }

  static ThemeData themeFor(Palette p) {
    final TextTheme t = _textTheme(p);
    return ThemeData(
      useMaterial3: true,
      brightness: p == Palette.warmInk ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      textTheme: t,
      extensions: <ThemeExtension<dynamic>>[MarginaliaTheme(palette: p)],
      // The design has no Material ripples, no default splash, no Material
      // colour accents: a paperback under a lamp, not a dashboard.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      dividerTheme: DividerThemeData(color: p.hair, thickness: 1, space: 1),
    );
  }

  /// The full type ramp. Serif for read, sans for operate, mono for data.
  static TextTheme _textTheme(Palette p) {
    TextStyle serif(double size, {FontWeight w = FontWeight.w400,
        double? height, double? spacing}) =>
        TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: size,
          fontWeight: w,
          color: p.ink,
          height: height,
          letterSpacing: spacing,
        );
    TextStyle sans(double size, {FontWeight w = FontWeight.w400,
        Color? color, double? height}) =>
        TextStyle(
          fontFamily: TypeScale.sans,
          fontSize: size,
          fontWeight: w,
          color: color ?? p.ink,
          height: height,
        );
    return TextTheme(
      // The article body. 17.5 on a 1.86 line height is the prototype's single
      // most important number: it is the reason a paragraph reads like a page
      // instead of a form.
      bodyLarge: serif(17.5, height: 1.86, spacing: -0.005),
      bodyMedium: serif(15, height: 1.6),
      // Buttons, chips, labels — everything operated.
      labelLarge: sans(15, w: FontWeight.w700),
      labelMedium: sans(13, w: FontWeight.w700),
      labelSmall: sans(11, w: FontWeight.w600, color: p.ink3),
      // Section headings, card titles.
      titleLarge: serif(21, w: FontWeight.w600, height: 1.2, spacing: -0.02),
      titleMedium: serif(16.5, w: FontWeight.w600, height: 1.25),
      titleSmall: serif(15.5, w: FontWeight.w500, spacing: -0.012),
    );
  }

  /// The eyebrow: mono, wide-tracked, uppercase — `.eyebrow` in the prototype.
  /// It is a named helper rather than a TextTheme slot because there is only
  /// ever one of these on a screen, and every call site wants the same letterspacing.
  static TextStyle eyebrow(Palette p, {Color? color}) => TextStyle(
        fontFamily: TypeScale.mono,
        fontSize: AppType.twoXs,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.18,
        color: color ?? p.verm,
      );

  /// A section divider label: `.sec` — mono, tracked, with a hairline running
  /// out to the right edge.
  static TextStyle sectionLabel(Palette p) => TextStyle(
        fontFamily: TypeScale.mono,
        fontSize: AppType.twoXs,
        letterSpacing: 0.12,
        color: p.ink3,
      );

  /// The lemma line on a word card: 33px serif is the single largest type in
  /// the app besides the hero, because the word IS the content.
  static TextStyle lemma(Palette p) => TextStyle(
        fontFamily: TypeScale.serif,
        fontSize: 33,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.025,
        height: 1.1,
        color: p.ink,
      );

  /// IPA, timestamps, counters, keys — anything that is data, not language.
  static TextStyle data(Palette p, double size, {Color? color}) => TextStyle(
        fontFamily: TypeScale.mono,
        fontSize: size,
        color: color ?? p.ink3,
      );
}