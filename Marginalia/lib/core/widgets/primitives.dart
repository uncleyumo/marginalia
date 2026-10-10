// The three primitives every screen is made of.
//
// Hairline (in texture.dart), Sheet+Scrim, and Toast. DESIGN §12 warns that the
// prototype's own bottom sheets once rendered fully transparent because a token
// was scoped too narrowly, and short sheets hid the bug while tall scrolling
// ones did not. So the sheet here resolves its colours from the ambient Theme
// exactly once, at the top, and passes them down.
//
// Two layout rules were learned the hard way and are now stated here so they
// cannot be undone a second time:
//
//   1. A sheet's height cap is measured against the height LEFT OVER after the
//      keyboard. `0.8 × screen` plus a keyboard inset is taller than the screen,
//      and the sheet grows off the top until its own title is under the status
//      bar — which is exactly what a screenshot of the API-key sheet showed.
//   2. There is ONE Close, and it belongs to the frame. Content that also draws
//      a Close produced two of them, stacked, which read as a broken dialog.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'texture.dart';

/// A card. One level only — the design has no cards inside cards, so this is
/// never nested.
class Card0 extends StatelessWidget {
  const Card0({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.cardPad),
    this.onTap,
    this.borderRadius,
    this.borderColor,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? borderColor;

  /// The queue's `ready` card carries a shadow; a row inside a list does not.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final BorderRadius r = borderRadius ?? Radii.cardAll;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: r,
        border: Border.all(color: borderColor ?? c.hair, width: 1),
        boxShadow: elevated ? c.shadow : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A button. Vermilion when it is the thing the screen is waiting for; paper
/// with a hairline when it is not.
class Btn extends StatelessWidget {
  const Btn({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = true,
    this.icon,
    this.dense = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// A short glyph in the same weight as the label. Never a Chinese character:
  /// the interface is English, and the only Chinese on screen is a translation.
  final String? icon;
  final bool dense;

  /// The tap has been taken and the work has not finished.
  ///
  /// A button that looks the same before and after the tap is a button the
  /// reader taps again — and on the queue screen a second tap is a second paid
  /// request, because the slot is still `planned` until the article lands. So
  /// `busy` draws the receipt: the glyph becomes a spinner, the label says what
  /// is happening, and [onPressed] is forced to null so the second tap cannot
  /// reach the network even if the caller forgot to guard it.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final Color bg = primary ? c.verm : c.surface;
    final Color fg = primary ? c.paper : c.ink;
    // Dimmed while busy, because a disabled control that looks fully enabled is
    // the thing this parameter exists to prevent.
    final double alpha = busy ? 0.72 : 1.0;
    return SizedBox(
      width: double.infinity,
      child: Opacity(
        opacity: alpha,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: busy ? null : onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: primary
                  ? null
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.hair),
                    ),
              padding: EdgeInsets.symmetric(
                vertical: dense ? 10 : 13,
                horizontal: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (busy) ...<Widget>[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ] else if (icon != null) ...<Widget>[
                    Text(icon!, style: TextStyle(color: fg, fontSize: 14)),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: dense ? 13.5 : 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact square action used in toolbars and beside a button.
///
/// Deliberately small and outlined: it is the second thing on the row, and a
/// second thing drawn at the same weight as the first one turns a row of two
/// actions into a wall.
class MiniBtn extends StatelessWidget {
  const MiniBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tip,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final String? tip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final Widget button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: active ? c.vermWash : c.surface,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: active ? c.verm : c.hair),
            ),
            child: Icon(
              icon,
              size: size * 0.42,
              color: onTap == null
                  ? c.ink3.withValues(alpha: 0.5)
                  : (active ? c.vermInk : c.ink2),
            ),
          ),
        ),
      ),
    );
    return tip == null ? button : Tooltip(message: tip!, child: button);
  }
}

/// The eyebrow: mono, wide-tracked, uppercase, vermilion.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: MarginaliaTheme.eyebrow(context.colors, color: color),
      );
}

/// A section label with a hairline running out to the right edge.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.block, bottom: 9),
      child: Row(
        children: <Widget>[
          Text(text.toUpperCase(), style: MarginaliaTheme.sectionLabel(c)),
          const SizedBox(width: 9),
          Expanded(child: Hairline(color: c.hair)),
        ],
      ),
    );
  }
}

/// A small pill. Used for a topic, a state, a tier.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color,
    this.background,
    this.mono = true,
    this.onTap,
    this.trailing,
    this.borderColor,
  });

  final String text;
  final Color? color;
  final Color? background;

  /// Lets a selected pill carry its own edge, so the active filter does not
  /// have to be distinguished by fill alone.
  final Color? borderColor;

  /// Mono for data, sans for something you read. A topic is operated, so sans.
  final bool mono;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final Color fg = color ?? c.ink2;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chip,
        child: Container(
          decoration: BoxDecoration(
            color: background ?? c.paperSunk,
            borderRadius: Radii.chip,
            border: Border.all(color: borderColor ?? c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Flexible, because a pill's text is not always short enough for
              // one line. Inside a `Wrap` the Row is capped at the available
              // width, and without this a long label overflows its own chip —
              // "Never start with background — go straight to the point" did,
              // by 1.8 pixels, which is the kind of number that grows the
              // moment somebody changes a font.
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontFamily: mono ? TypeScale.mono : TypeScale.sans,
                    fontSize: 11,
                    color: fg,
                    fontWeight: mono ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 6),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How a sheet behaves, and the one rule that matters.
///
/// DESIGN: "The scrim refuses to dismiss while a paid-for result is
/// unaccepted — you may swipe away a blank sheet, never discard a result you
/// paid for by tapping outside it."
///
/// So [locked] is a first-class parameter rather than a convention.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.leading,
    this.locked = false,
    this.onClose,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final Widget? leading;
  final bool locked;
  final VoidCallback? onClose;

  /// Show a sheet. The frame — grab handle, optional header, one Close — belongs
  /// to the FRAME, so the builder returns CONTENT and never draws its own
  /// Close. That is the whole reason there is only one of them.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    Widget? trailing,
    bool locked = false,
    String? lockMessage,
    String? closeLabel,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.ink.withValues(alpha: 0.5),
      isDismissible: false,
      enableDrag: !locked,
      useSafeArea: useSafeArea,
      builder: (BuildContext ctx) => AppSheetFrame(
        title: title,
        trailing: trailing,
        locked: locked,
        lockMessage: lockMessage,
        closeLabel: closeLabel,
        onClose: () => Navigator.of(ctx).maybePop(),
        builder: builder,
      ),
    );
  }

  /// Show a sheet whose [locked] state can CHANGE while it is open.
  ///
  /// [show] takes `locked` as a value fixed at show time, which is right for a
  /// sheet that asks one question before it does anything. It is wrong for the
  /// plan editor: that sheet starts unlocked (the reader is typing a request),
  /// and becomes locked the moment a PAID-FOR answer arrives and has not been
  /// accepted yet. The state is a [ValueNotifier] the sheet body owns, and the
  /// frame rebuilds from it.
  ///
  /// The cost of gating dynamically is that this sheet cannot be dragged away —
  /// `enableDrag` has to be false from the start, because `showModalBottomSheet`
  /// fixes it when the route is pushed. For a sheet that can be holding a
  /// result somebody paid for, that is the behaviour we want anyway.
  static Future<T?> showGated<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    required ValueNotifier<bool> locked,
    String? title,
    Widget? trailing,
    String? lockMessage,
    String? closeLabel,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.ink.withValues(alpha: 0.5),
      isDismissible: false,
      enableDrag: false,
      useSafeArea: useSafeArea,
      builder: (BuildContext ctx) => ValueListenableBuilder<bool>(
        valueListenable: locked,
        builder: (BuildContext _, bool isLocked, Widget? __) => AppSheetFrame(
          title: title,
          trailing: trailing,
          locked: isLocked,
          lockMessage: lockMessage,
          closeLabel: closeLabel,
          onClose: () => Navigator.of(ctx).maybePop(),
          builder: builder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetFrame(
      locked: locked,
      onClose: onClose,
      title: title,
      trailing: trailing,
      leading: leading,
      builder: (BuildContext _) => child,
    );
  }
}

/// The frame: scrim, grab handle, optional header, the keyboard-aware height
/// cap, and exactly one Close.
class AppSheetFrame extends StatelessWidget {
  const AppSheetFrame({
    super.key,
    required this.builder,
    this.title,
    this.trailing,
    this.leading,
    this.locked = false,
    this.lockMessage,
    this.closeLabel,
    this.onClose,
  });

  final WidgetBuilder builder;
  final String? title;
  final Widget? trailing;
  final Widget? leading;
  final bool locked;
  final String? lockMessage;

  /// What the frame's one Close says. `Close` is right for a sheet that asked a
  /// question; a sheet that only TOLD the reader something is dismissed by
  /// acknowledging it, and `Got it` is the honest label there.
  ///
  /// It exists so that a sheet never adds a second dismiss button of its own to
  /// say the same thing in different words. Two controls for one action is the
  /// bug this frame was built to prevent.
  final String? closeLabel;

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final double screen = MediaQuery.sizeOf(context).height;
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    // The cap is a share of what is LEFT, not of the screen. With the keyboard
    // up, `0.8 × screen` plus the inset is taller than the screen itself, and
    // the sheet climbs off the top and hides its own title.
    final double room = (screen - keyboard).clamp(200.0, screen);
    final double cap = (room * 0.9).clamp(160.0, screen);

    return Padding(
      // Lift clear of the keyboard and the system gesture bar.
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: cap),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.sheetTop,
          border: Border(
            top: BorderSide(color: c.hair),
            left: BorderSide(color: c.hair),
            right: BorderSide(color: c.hair),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0x47000000),
              offset: const Offset(0, -14),
              blurRadius: 44,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // the grab handle
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: c.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) _header(context, c),
            Flexible(
              child: SingleChildScrollView(
                // A sheet holds a keyboard half the time; without this the
                // focused field can sit behind it.
                padding: EdgeInsets.only(
                  bottom: keyboard > 0 ? 4 : 0,
                ),
                child: builder(context),
              ),
            ),
            _close(context, c),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Palette c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 2, Gap.sheetPad, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Text(
              title!,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.02,
                color: c.ink,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  /// The one Close. It is deliberately quiet: on Android the sheet also closes
  /// on a back gesture and on a tap outside, so this is the third way in, not
  /// the only one, and it should not shout about it.
  Widget _close(BuildContext context, Palette c) {
    final String label = locked
        ? (lockMessage ?? 'Choose an option first')
        : (closeLabel ?? 'Close');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.sheetPad,
        8,
        Gap.sheetPad,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: locked ? c.paperSunk : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              if (locked) return;
              if (onClose != null) {
                onClose!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: locked ? Colors.transparent : c.hair),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: locked ? c.ink3 : c.ink2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The toast. Mono, small, and honest: it only ever states what happened, never
/// what it means.
class Toast {
  Toast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Show a message for [seconds]. A second call replaces the first rather than
  /// stacking, because two toasts at once is noise.
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    // A toast is fired from an async callback more often than not, and a
    // context whose element has already gone throws rather than showing
    // anything. Silently not showing is the right outcome there: the thing the
    // toast was reporting has already happened.
    if (!context.mounted) return;
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _dismiss();

    final Palette c = context.colors;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext ctx) => Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.paddingOf(ctx).bottom + 78,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: Ease.mid,
            curve: Ease.outExpo,
            builder: (BuildContext _, double t, Widget? child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - t)),
                child: child,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: c.ink,
                  borderRadius: Radii.chip,
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 12,
                    height: 1.35,
                    color: c.paper,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    final OverlayEntry? entry = _current;
    _current = null;
    if (entry == null) return;
    // Removing an entry whose overlay has gone throws; the toast is already gone
    // from the reader's point of view either way.
    try {
      entry.remove();
    } catch (_) {}
  }
}

/// The screen every route wraps itself in: paper, grain, and the rise animation
/// the prototype plays on entering a screen.
///
/// The top safe area is consumed HERE, once, for every screen. Handling it per
/// screen is how the Settings title ended up underneath the clock: a screen
/// added later, with a plain `EdgeInsets.fromLTRB(gutter, 8, ...)`, silently
/// drew under the status bar because nothing above it stopped it.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.child,
    this.bottomBar,
  });

  final Widget child;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: context.colors.paper,
      body: SafeArea(
        bottom: bottomBar == null,
        child: PaperGrain(
          child: Column(
            children: <Widget>[
              Expanded(
                child: reduce
                    ? child
                    : TweenAnimationBuilder<double>(
                        key: const ValueKey<String>('rise'),
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: Ease.slow,
                        curve: Ease.outExpo,
                        builder: (BuildContext _, double t, Widget? c) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: c,
                          ),
                        ),
                        child: child,
                      ),
              ),
              if (bottomBar != null) bottomBar!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Blur helper kept for the scrim only. DESIGN forbids blur as decoration, but
/// the prototype's scrim itself carries `backdrop-filter: blur(2px)` so a sheet
/// reads as being above the page rather than pasted onto it.
BackdropFilter scrimBlur() => BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: const SizedBox.shrink(),
    );