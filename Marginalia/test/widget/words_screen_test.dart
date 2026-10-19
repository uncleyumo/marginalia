// The Words screen must render its rows at all: it is a plain list, and a
// screen that paints nothing is the kind of failure the app cannot report.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marginalia/core/design/tokens.dart';
import 'package:marginalia/features/words/words_screen.dart';

void main() {
  testWidgets('the words screen renders a starred row and its quota',
      (WidgetTester tester) async {
    const WordRow row = WordRow(
      lemma: 'pointers',
      encounters: 3,
      starred: true,
      starCount: 3,
      starRemaining: 2,
      fraction: 0.2,
    );

    await tester.pumpWidget(MaterialApp(
      theme: MarginaliaTheme.themeFor(Palette.warmInk),
      home: WordsScreen(
        crucial: const <WordRow>[row],
        all: const <WordRow>[row],
        onStar: (String _) {},
        onUnstar: (String _) {},
        onOpen: (String _) {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('pointers'), findsWidgets);
    expect(find.text('starred 3×'), findsWidgets);
    expect(find.textContaining('2 more articles'), findsOneWidget);
  });
}
