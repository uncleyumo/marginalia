// The bottom bar.
//
// DESIGN's frequency reasoning, which decides the ORDER and the labels:
// Queue every day · Article twice · Library every week · History most weeks ·
// Words half a minute a day.
//
// So the bar is not a nav bar with five equal icons; it is a statement about how
// often each thing is wanted. "Words" therefore reads as a count — how many words
// want another look — instead of a label, because that is the number the reader
// would actually check.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design/tokens.dart';
import '../core/util/motion.dart';

/// Named `Dest` rather than `Tab`, which Flutter's material library already
/// has. Two tabs in one file scope is a collision waiting to happen.
enum Dest { queue, article, library, history, words }

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.current,
    required this.wordsWanting,
    required this.onSelect,
  });

  final Dest current;

  /// How many words are above the active threshold. Shown on the tab, so the
  /// bar doubles as a status light.
  final int wordsWanting;

  final void Function(Dest tab) onSelect;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hair)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: <Widget>[
              _item(context, c, Dest.queue, 'Queue', null),
              _item(context, c, Dest.article, 'Article', null),
              _item(context, c, Dest.library, 'Library', null),
              _item(context, c, Dest.history, 'History', null),
              _item(
                context,
                c,
                Dest.words,
                // The name AND the count. A bare `8` in the last tab read as
                // a stray badge — nothing on screen said it meant words.
                wordsWanting == 0 ? 'Words' : 'Words $wordsWanting',
                wordsWanting > 0
                    ? '$wordsWanting words want another look'
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    Palette c,
    Dest tab,
    String label,
    String? tooltip,
  ) {
    final bool on = tab == current;
    final Duration d = motionDuration(context, Ease.fast);
    // Both the rule and the label animate between states, so switching tabs
    // reads as a movement rather than a repaint. The values are unchanged —
    // this is the same mark, arriving instead of appearing.
    final Widget label0 = AnimatedDefaultTextStyle(
      duration: d,
      curve: Ease.outExpo,
      style: TextStyle(
        fontFamily: TypeScale.mono,
        fontSize: on ? 11 : 10,
        color: on ? c.ink : c.ink3,
        fontWeight: on ? FontWeight.w500 : FontWeight.w400,
      ),
      child: Text(label),
    );
    final Widget child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // the active tab is marked by a rule above the label, not by colour
        // alone — it survives a greyscale screenshot
        AnimatedContainer(
          duration: d,
          curve: Ease.outExpo,
          width: on ? 18 : 0,
          height: 2,
          decoration: BoxDecoration(
            color: c.verm,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 7),
        label0,
      ],
    );

    void tap() {
      // A tab is a physical destination. The tick is the smallest useful
      // confirmation and costs nothing when the platform has no haptics.
      HapticFeedback.selectionClick();
      onSelect(tab);
    }

    return Expanded(
      child: tooltip == null
          ? InkWell(onTap: tap, child: child)
          : Tooltip(
              message: tooltip,
              child: InkWell(onTap: tap, child: child),
            ),
    );
  }
}
