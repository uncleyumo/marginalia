// The smallest widget that can host a tappable sentence.
//
// `_TappableSentence` reads the palette and the reading face off the context,
// so a test has to give it both. The face defaults to notoSerif on its own,
// but the palette has no default — it comes from a scope this app installs at
// the root, and reproducing the whole app to test one tap would be a great deal
// of machinery for a very small question.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marginalia/domain/models.dart';

/// Every word in [text] with its offsets, by the same rule the widget uses.
List<({int start, int end, String word})> tokensOf(String text) {
  final RegExp word = RegExp(r"[A-Za-z][A-Za-z'\-]*");
  final List<({int start, int end, String word})> out =
      <({int start, int end, String word})>[];
  for (final RegExpMatch m in word.allMatches(text)) {
    out.add((start: m.start, end: m.end, word: m.group(0)!));
  }
  return out;
}

/// Host [child] inside the scopes a reading widget needs and nothing else.
///
/// Scrolling, because the real article is a ListView and a sentence at a large
/// size or a large system font is taller than the screen. Without a viewport
/// here a long sentence lays out past the bottom of the test window and taps
/// land outside it — which is a fact about the test window, not about the
/// widget.
Widget harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(width: 320, child: child),
          ),
        ),
      ),
    ),
  );
}

/// The screen coordinate of the middle of [box] inside [para].
///
/// `getBoxesForSelection` answers in the paragraph's own space, but a tap is
/// delivered in global screen space. Getting this conversion wrong is exactly
/// the class of bug the widget was fixed for, so the tests do it the same way
/// the widget does — through the render object — rather than by hand.
Offset globalCentre(RenderParagraph para, TextBox box) {
  final Offset local = Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  return para.localToGlobal(local);
}
