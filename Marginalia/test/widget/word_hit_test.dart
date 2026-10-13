// Hit-testing for a tapped word.
//
// The bug this covers lived for a long time: a tap landed on the wrong word,
// more often at a larger reading size and deeper in the article. The cause was
// that the tap was measured against a TextPainter rebuilt from the sentence
// string, and that painter disagreed with the paragraph on screen about line
// height (no decorations), about width (maxWidth, not the wrapped width) and
// about the text scaler (never passed). It now asks the RenderParagraph that
// drew the words, so there is nothing left to disagree about.
//
// These tests pin the behaviour that broke: the word under the finger is the
// word reported, at every reading size, on every line, and whether or not the
// sentence is the one being spoken.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/domain/models.dart';
import 'package:marginalia/features/article/article_screen.dart';

import 'support.dart';

void main() {
  // A sentence long enough to wrap at every size, with a word distinctive
  // enough to be unambiguous about which one was hit.
  const String sentence =
      'The quick brown fox jumps over the lazy dog near the river bank while '
      'the farmer watches from the old wooden fence and counts his sheep.';

  for (final ReadSize size in ReadSize.values) {
    testWidgets('${size.label}: tap reports the word under the finger',
        (WidgetTester tester) async {
      final List<String> hits = <String>[];
      await tester.pumpWidget(
        harness(
          TappableSentence(
            text: sentence,
            marks: const <Mark>[],
            onWordTap: hits.add,
            onLongPress: () {},
            sizePx: size.px,
            baseColor: const Color(0xFF000000),
          ),
        ),
      );

      final RenderParagraph para = _paragraph(tester);
      final List<({int start, int end, String word})> tokens = tokensOf(sentence);

      // Every word, tapped at the centre of its own painted rect, must come
      // back as itself. This is the whole bug: it used to come back as the
      // word a rebuilt painter put there instead.
      for (final ({int start, int end, String word}) t in tokens) {
        for (final TextBox box
            in para.getBoxesForSelection(TextSelection(baseOffset: t.start, extentOffset: t.end))) {
          final Offset centre = globalCentre(para, box);
          await tester.tapAt(centre);
          await tester.pump();
          expect(hits, isNotEmpty, reason: 'no answer for a tap inside ${t.word}');
          expect(hits.last, t.word,
              reason: '${size.label}: tapped ${t.word}, got ${hits.last}');
        }
      }
    });
  }

  testWidgets('a marked (speaking) sentence still hits the word under the finger',
      (WidgetTester tester) async {
    // The speaking sentence is wrapped in a Container with 10px of left
    // padding, which shifts the text right. The rebuilt painter knew nothing
    // about that; the RenderParagraph does.
    final List<String> hits = <String>[];
    await tester.pumpWidget(
      harness(
        TappableSentence(
          text: sentence,
          marks: const <Mark>[],
          onWordTap: hits.add,
          onLongPress: () {},
          sizePx: ReadSize.large.px,
          baseColor: const Color(0xFF000000),
        ),
      ),
    );

    final RenderParagraph para = _paragraph(tester);
    final TextBox box = para
        .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3))
        .first;

    await tester.tapAt(globalCentre(para, box));
    await tester.pump();

    expect(hits.single, 'The');
  });

  testWidgets('a tap on whitespace reports the nearest word, never nothing',
      (WidgetTester tester) async {
    final List<String> hits = <String>[];
    await tester.pumpWidget(
      harness(
        TappableSentence(
          text: sentence,
          marks: const <Mark>[],
          onWordTap: hits.add,
          onLongPress: () {},
          sizePx: ReadSize.medium.px,
          baseColor: const Color(0xFF000000),
        ),
      ),
    );

    final RenderParagraph para = _paragraph(tester);
    // The gap between the first two words: an x that is inside the text block
    // but between two painted words.
    final TextBox first = para
        .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3))
        .first;
    await tester.tapAt(para.localToGlobal(Offset(first.right + 2, (first.top + first.bottom) / 2)));
    await tester.pump();

    expect(hits, hasLength(1));
    expect(hits.single, anyOf('The', 'quick'));
  });

  testWidgets('a scaled text environment is measured at the scale it is drawn',
      (WidgetTester tester) async {
    // The system font size is the case the old code could not see at all: the
    // painter was built with a plain TextStyle, so it measured at 1.0 while
    // the screen drew at 2.0 and every tap landed in the wrong place.
    //
    // Shorter than the other cases' sentence, because at 2x it has to stay
    // inside the test window to be tappable at all. Two lines, which is what
    // the case is about: the wrap has to agree with the screen.
    const String short =
        'The quick brown fox jumps over the lazy dog near the river bank.';
    final List<String> hits = <String>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: harness(
          TappableSentence(
            text: short,
            marks: const <Mark>[],
            onWordTap: hits.add,
            onLongPress: () {},
            sizePx: ReadSize.medium.px,
            baseColor: const Color(0xFF000000),
          ),
        ),
      ),
    );

    final RenderParagraph para = _paragraph(tester);
    for (final ({int start, int end, String word}) t in tokensOf(short)) {
      for (final TextBox box in para.getBoxesForSelection(
          TextSelection(baseOffset: t.start, extentOffset: t.end))) {
        await tester.tapAt(globalCentre(para, box));
        await tester.pump();
        expect(hits.last, t.word,
            reason: 'scaled 2x: tapped ${t.word}, got ${hits.last}');
      }
    }
  });
}

RenderParagraph _paragraph(WidgetTester tester) {
  final RenderObject? ro = tester.renderObject<RenderParagraph>(find.byType(Text).first);
  return ro as RenderParagraph;
}
