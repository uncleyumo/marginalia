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
/// was removed, not renamed (invariant 5). A reader picks one, or asks the app
/// to follow the phone; nothing here is ever chosen by a clock.
///
/// [brightness] is a FIELD rather than a comparison against [warmInk], because
/// the comparison was an identity check dressed up as a rule: it read "is this
/// the dark palette" and answered a question about one particular constant. A
/// third palette would have silently been treated as light.
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
    required this.brightness,
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

  /// Light or dark. Read by `MarginaliaTheme.themeFor` to pick the Material
  /// brightness, and by `main()` to flip the status-bar icons — which have to
  /// invert with the surface or they disappear into it.
  final Brightness brightness;

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
    brightness: Brightness.light,
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
    brightness: Brightness.dark,
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

/// Which surface to show. Three answers, and "system" is the default because a
/// phone that has already been told what its owner prefers should not be asked
/// again.
///
/// This is not a day/night switch. Nothing in the app consults a clock; the
/// only thing that can change the surface on its own is the PHONE's own
/// setting, which is a thing the reader chose somewhere else.
enum AppearanceMode {
  light('Light'),
  dark('Dark'),
  system('Follow the phone');

  const AppearanceMode(this.label);

  final String label;

  /// The palette for this mode, given what the phone currently says.
  Palette paletteFor(Brightness platform) => switch (this) {
        AppearanceMode.light => Palette.warmPaper,
        AppearanceMode.dark => Palette.warmInk,
        AppearanceMode.system =>
          platform == Brightness.dark ? Palette.warmInk : Palette.warmPaper,
      };
}

/// The face the ARTICLE is set in. A reading preference, and the only thing it
/// touches is the body text — buttons, labels and data rows keep the three
/// families in [TypeScale], because DESIGN §8's split between what is READ and
/// what is OPERATED is not a matter of taste.
///
/// ## Why these six, and why the default is the one it is
///
/// Every article in this app is BILINGUAL: English sentences, Chinese
/// translations. A face is only good here if the CHINESE beside it looks right
/// too, and that is not a property of the Latin font at all — it is a property
/// of what Android substitutes for the characters the Latin font does not have.
///
/// A bundled Latin font (Newsreader, the app's own reading serif) has no CJK
/// glyphs, so Chinese falls through to the system's default: **Noto Sans CJK**,
/// a sans. Serif English beside sans Chinese. That is what the app shipped
/// with, and it is the reason this list is mostly SYSTEM families.
///
/// Android's `fonts.xml` answers the CJK question per family
/// (`fallbackFor="serif"`), so:
///
///  · `serif`          → Noto Serif (Latin) + **Noto Serif CJK** — matched pair
///  · `sans-serif`     → Roboto + **Noto Sans CJK** — matched pair
///  · `source-sans-pro`→ Adobe's reading face; Noto Sans CJK is its sibling,
///                        drawn by the same team to the same proportions
///
/// [notoSerif] is the default for that reason: it is the only option that is
/// BOTH always present (it is in the AOSP baseline, unlike `source-sans-pro`)
/// AND a matched serif pair, which is what DESIGN asks a reading surface to be.
enum ReadingFace {
  notoSerif(
    'Noto Serif',
    'serif',
    <String>[],
    'Serif English with serif Chinese — the one pair that truly matches.',
  ),
  roboto(
    'Roboto',
    'sans-serif',
    <String>[],
    'The phone\'s own face. Clear letterforms, sans Chinese.',
  ),
  sourceSans(
    'Source Sans',
    'source-sans-pro',
    <String>['sans-serif'],
    'Adobe\'s reading face. Its Chinese sibling is Noto Sans CJK.',
  ),
  newsreader(
    'Newsreader',
    TypeScale.serif,
    <String>['serif'],
    'The app\'s own reading serif. Chinese falls back to the phone\'s sans.',
  ),
  condensed(
    'Roboto Condensed',
    'sans-serif-condensed',
    <String>['sans-serif'],
    'Narrower, so more words fit on a line.',
  ),
  mono(
    'Roboto Mono',
    'monospace',
    <String>['sans-serif'],
    'Every letter the same width. Useful for telling shapes apart.',
  );

  const ReadingFace(this.label, this.family, this.fallback, this.note);

  /// Shown verbatim on the row.
  final String label;

  /// Passed to `TextStyle.fontFamily`.
  final String family;

  /// Tried in order when [family] is not on the device.
  ///
  /// Not decoration: `source-sans-pro` is NOT in the AOSP baseline, so on a
  /// phone without it the row would look like it did nothing. Naming the
  /// system sans as the fallback makes it degrade to a face that is there.
  final List<String> fallback;

  /// One line under the row, saying what the reader gets.
  final String note;

  /// The style an article's body is set in.
  TextStyle style(Color color, double size, {double? height}) => TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback.isEmpty ? null : fallback,
        fontSize: size,
        color: color,
        height: height,
      );

  /// Read the current face off the widget tree.
  static ReadingFace of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadingFaceScope>()?.face ??
      ReadingFace.notoSerif;
}

/// Carries [ReadingFace] down the tree.
///
/// An InheritedWidget rather than a parameter, because the alternative is
/// threading a font choice through every screen, sheet and sentence widget that
/// happens to draw body text — and the ones that would be forgotten are exactly
/// the ones nobody looks at twice.
class ReadingFaceScope extends InheritedWidget {
  const ReadingFaceScope({
    super.key,
    required this.face,
    required super.child,
  });

  final ReadingFace face;

  @override
  bool updateShouldNotify(ReadingFaceScope old) => old.face != face;
}

extension ReadingFaceContext on BuildContext {
  /// The reading face in force. Defaults to [ReadingFace.notoSerif] outside a
  /// scope, so a widget shown in isolation still renders.
  ReadingFace get readingFace => ReadingFace.of(this);
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
      brightness: p.brightness,
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